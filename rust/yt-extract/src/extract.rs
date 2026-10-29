use serde_json::Value;

#[derive(Debug, Clone)]
pub struct AudioStream {
    pub itag: u32,
    pub url: String,
    pub mime: String,
    pub bitrate: u64,
    pub audio_quality: String,
    pub needs_decipher: bool,
    pub throttled_n: bool,
    /// format.contentLength — googlevideo serves exactly this many bytes.
    pub content_length: Option<u64>,
    /// audioTrack.audioIsDefault; None when the manifest carries no track info.
    pub is_default_track: Option<bool>,
    /// audioTrack.id — distinguishes same-itag dub/original variants.
    pub audio_track_id: Option<String>,
    pub is_drc: bool,
}

#[derive(Debug)]
pub struct PlayerResult {
    pub status: String,
    pub reason: String,
    pub streams: Vec<AudioStream>,
    pub title: String,
    pub is_live: bool,
}

/// The ad-bearing arrays (`adFormats`, `adSlots`, sponsor markers) are never
/// read; only `adaptiveFormats`/`formats` enter here, and anything explicitly
/// role-marked as an ad by the manifest itself is dropped too. Exact role
/// names only — a substring test on "ad" would also match legitimate roles.
fn is_advertised(fmt: &Value) -> bool {
    fmt["contentRole"]["contentRoles"]
        .as_array()
        .map(|roles| {
            roles.iter().any(|r| {
                let up = r.as_str().unwrap_or_default().to_ascii_uppercase();
                up == "CONTENT_ROLE_ADS" || up.ends_with("_ADS")
            })
        })
        .unwrap_or(false)
}

fn parse_stream(fmt: &Value) -> Option<AudioStream> {
    let url = fmt["url"].as_str()?;
    let mime = fmt["mimeType"].as_str()?.to_string();
    if !mime.contains("audio") {
        return None;
    }
    Some(AudioStream {
        itag: fmt["itag"].as_u64()? as u32,
        url: url.to_string(),
        mime,
        bitrate: fmt["bitrate"].as_u64().unwrap_or(0),
        audio_quality: fmt["audioQuality"]
            .as_str()
            .unwrap_or("AUDIO_QUALITY_LOW")
            .to_string(),
        needs_decipher: fmt["signatureCipher"].is_string() || fmt["s"].is_string(),
        throttled_n: url.split(['?', '&']).any(|param| param.starts_with("n=")),
        content_length: fmt["contentLength"].as_str().and_then(|s| s.parse().ok()),
        is_default_track: fmt["audioTrack"]["audioIsDefault"].as_bool(),
        audio_track_id: fmt["audioTrack"]["id"].as_str().map(str::to_string),
        is_drc: fmt["isDrc"].as_bool().unwrap_or(false),
    })
}

pub fn parse_player(response: &Value) -> PlayerResult {
    let playability = &response["playabilityStatus"];
    let status = playability["status"]
        .as_str()
        .unwrap_or("UNKNOWN")
        .to_string();
    let reason = playability["reason"]
        .as_str()
        .unwrap_or_default()
        .to_string();
    let title = response["videoDetails"]["title"]
        .as_str()
        .unwrap_or_default()
        .to_string();
    let is_live = response["videoDetails"]["isLiveContent"]
        .as_bool()
        .unwrap_or(false);

    let mut streams = Vec::new();
    for arr in ["adaptiveFormats", "formats"] {
        if let Some(fmts) = response["streamingData"][arr].as_array() {
            for fmt in fmts {
                if is_advertised(fmt) {
                    continue;
                }
                if let Some(s) = parse_stream(fmt) {
                    streams.push(s);
                }
            }
        }
    }
    use std::cmp::Reverse;
    streams.sort_by_key(|s| Reverse(s.bitrate));
    // Dedup by stream *identity*, not itag alone: manifests legitimately
    // carry same-itag variants for different language tracks or DRC levels,
    // and collapsing them here would hide the choice best_audio is supposed
    // to make. Keeping the first (highest-bitrate) entry per identity.
    let mut seen = std::collections::HashSet::new();
    streams.retain(|s| seen.insert((s.itag, s.audio_track_id.clone(), s.is_drc)));

    PlayerResult {
        status,
        reason,
        streams,
        title,
        is_live,
    }
}

/// Stream tiering, most significant first:
/// 1. default language track beats dubs (audioTrack.audioIsDefault); when no
///    manifest carries track info every stream ties and this is inert.
/// 2. Opus/WebM beats AAC — better quality per bit, and the container our
///    players decode without extra negotiation.
/// 3. bitrate.
pub fn best_audio(result: &PlayerResult) -> Option<&AudioStream> {
    result
        .streams
        .iter()
        .filter(|s| !s.needs_decipher)
        .max_by_key(|s| {
            let default_tier = match s.is_default_track {
                Some(true) => 2,
                None => 1,
                Some(false) => 0,
            };
            let codec_tier = if s.mime.contains("opus") || s.mime.contains("webm") {
                1
            } else {
                0
            };
            (default_tier, codec_tier, s.bitrate)
        })
}

pub fn total_size(stream: &AudioStream) -> Option<u64> {
    if let Some(len) = stream.content_length {
        return Some(len);
    }
    // Fallback for manifests that omit contentLength: googlevideo appends the
    // exact byte count of the served representation as clen= in the URL.
    // Parameters continue after '?' as well as '&', so split on both.
    stream
        .url
        .split(['&', '?'])
        .find_map(|p| p.strip_prefix("clen="))?
        .parse()
        .ok()
}

pub fn extension_for(mime: &str) -> &'static str {
    if mime.contains("opus") || mime.contains("webm") {
        "webm"
    } else if mime.contains("mp4") {
        "m4a"
    } else {
        "audio"
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn fmt_json(itag: u32, bitrate: u32, extra: serde_json::Value) -> serde_json::Value {
        let mut f = json!({
            "itag": itag,
            "url": format!("https://googlevideo.example/{itag}?sq=ok"),
            "mimeType": "audio/webm; codecs=\"opus\"",
            "bitrate": bitrate,
        });
        if let serde_json::Value::Object(map) = extra {
            f.as_object_mut().unwrap().extend(map);
        }
        f
    }

    fn player(formats: Vec<serde_json::Value>) -> serde_json::Value {
        json!({
            "playabilityStatus": {"status": "OK"},
            "videoDetails": {"title": "t"},
            "streamingData": {"formats": [], "adaptiveFormats": formats},
        })
    }

    #[test]
    fn same_itag_variants_survive_dedup_for_the_track_preference() {
        // A/best_audio regression: dedup by itag alone kept whichever copy
        // had the higher bitrate, hiding the default-track choice.
        let p = parse_player(&player(vec![
            fmt_json(
                251,
                140_000,
                json!({"audioTrack": {"id": "dub", "audioIsDefault": false}}),
            ),
            fmt_json(
                251,
                130_000,
                json!({"audioTrack": {"id": "orig", "audioIsDefault": true}}),
            ),
            fmt_json(251, 128_000, json!({"isDrc": true})),
        ]));
        assert_eq!(p.streams.len(), 3, "distinct variants must not collapse");
        // Default track wins over the higher-bitrate dub...
        assert_eq!(best_audio(&p).unwrap().is_default_track, Some(true));
    }

    #[test]
    fn exact_dups_dedup_keeping_highest_bitrate() {
        let p = parse_player(&player(vec![
            fmt_json(140, 128_000, json!({})),
            fmt_json(140, 128_000, json!({})),
        ]));
        assert_eq!(p.streams.len(), 1);
    }

    #[test]
    fn ad_roles_drop_only_exact_ad_roles() {
        let p = parse_player(&player(vec![
            fmt_json(
                251,
                130_000,
                json!({"contentRole": {"contentRoles": ["CONTENT_ROLE_ADS"]}}),
            ),
            fmt_json(
                140,
                128_000,
                json!({"contentRole": {"contentRoles": ["CONTENT_ROLE_UNPLUGGED"]}}),
            ),
        ]));
        assert_eq!(p.streams.len(), 1);
        assert_eq!(p.streams[0].itag, 140);
    }

    #[test]
    fn total_size_prefers_content_length_then_clen_in_any_query_slot() {
        let mut s = fmt_json(251, 130_000, json!({}));
        s["contentLength"] = json!("999");
        let st = parse_stream(&s).unwrap();
        assert_eq!(total_size(&st), Some(999));

        s["contentLength"] = json!(null);
        s["url"] = json!("https://gv/x?clen=12&foo=1");
        let st = parse_stream(&s).unwrap();
        assert_eq!(total_size(&st), Some(12), "clen as first param must parse");
    }

    #[test]
    fn decipherable_streams_are_never_selected() {
        let p = parse_player(&player(vec![
            fmt_json(251, 999_000, json!({"signatureCipher": "sig=abc"})),
            fmt_json(140, 128_000, json!({})),
        ]));
        assert_eq!(best_audio(&p).unwrap().itag, 140);
    }
}
