mod clients;
mod extract;
mod innertube;

use anyhow::{Context, Result, bail};
use clap::{Parser, Subcommand};
use clients::{Client, TRY_ORDER};
use extract::{PlayerResult, best_audio, extension_for, parse_player, total_size};
use futures_util::{StreamExt, future::join_all};
use innertube::InnerTube;
use serde_json::json;
use std::io::Write;
use std::time::Duration;
use tokio::fs::File;
use tokio::io::AsyncWriteExt;

#[derive(Parser)]
#[command(
    name = "yt-extract",
    about = "Lightweight in-process YouTube audio extractor"
)]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// Resolve stream manifests for a video across the client ladder
    Manifest {
        video_id: String,
        /// Pin a single client identity instead of walking the ladder
        #[arg(short, long)]
        client: Option<Client>,
    },
    /// Download the best ad-free audio stream to a file
    Audio {
        video_id: String,
        #[arg(short, long, default_value = "out")]
        output: String,
        #[arg(short, long)]
        client: Option<Client>,
    },
    /// Stream the best ad-free audio and play it through mpv or ffplay
    Play {
        video_id: String,
        #[arg(short, long)]
        client: Option<Client>,
    },
    /// Search YouTube and print candidate tracks
    Search {
        query: String,
        #[arg(long)]
        json: bool,
    },
}

/// Accepts a bare 11-char id, a watch URL (also shorts/live/embed) or a
/// youtu.be link. Everything downstream interpolates this into URLs and the
/// /tmp play path, so it must be validated before use, not after.
fn is_valid_id(s: &str) -> bool {
    s.len() == 11
        && s.bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'-' || b == b'_')
}

fn normalize_video_id(input: &str) -> Result<String> {
    let s = input.trim();
    if is_valid_id(s) {
        return Ok(s.to_string());
    }
    let query_id = s.split(['?', '&']).find_map(|p| p.strip_prefix("v="));
    let path_id = ["youtu.be/", "/shorts/", "/live/", "/embed/", "/v/"]
        .iter()
        .find_map(|marker| s.split_once(*marker))
        .map(|(_, rest)| rest.split('/').next().unwrap_or_default());
    let candidate = query_id
        .or(path_id)
        .unwrap_or(s)
        .split(['&', '#', '/', '?'])
        .next()
        .unwrap_or_default();
    if is_valid_id(candidate) {
        return Ok(candidate.to_string());
    }
    bail!("'{input}' is not a YouTube video id, watch URL or youtu.be link")
}

/// One HTTP client for stream fetches per run: it carries the same identity
/// as the resolving client (googlevideo pairs URL and user-agent) and a
/// timeout, so a stalled connection cannot hang the download forever.
fn stream_client(user_agent: &str) -> Result<reqwest::Client> {
    reqwest::Client::builder()
        .user_agent(user_agent)
        .timeout(Duration::from_secs(30))
        .build()
        .context("building stream http client")
}

/// Whether the stream URL should be considered directly fetchable.
async fn probe_url(http: &reqwest::Client, url: &str) -> bool {
    http.get(url)
        .header(reqwest::header::RANGE, "bytes=0-1023")
        .send()
        .await
        .map(|r| r.status().is_success() || r.status().as_u16() == 206)
        .unwrap_or(false)
}

/// Walks the client ladder and returns the first client that yields usable
/// audio. If the walk ends bot-gated (LOGIN_REQUIRED), the cached session is
/// the suspect: reset it and walk once more with a freshly planted session —
/// a stored jar can go stale while still looking young inside its TTL.
async fn resolve(
    it: &mut InnerTube,
    video_id: &str,
    pinned: Option<Client>,
) -> Result<(Client, PlayerResult)> {
    let clients = pinned.map_or_else(|| TRY_ORDER.to_vec(), |c| vec![c]);
    let mut last_http_error: Option<String> = None;
    for attempt in 0..2 {
        it.bootstrap(
            &format!("https://www.youtube.com/watch?v={video_id}&hl=en"),
            clients[0],
        )
        .await;
        let mut saw_bot_gate = false;
        let mut last: Option<(Client, PlayerResult)> = None;
        for &client in &clients {
            let response = match it.player(client, video_id).await {
                Ok(r) => r,
                Err(e) => {
                    eprintln!("  [{}] error: {e:#}", client.label());
                    last_http_error = Some(format!("[{}] {e:#}", client.label()));
                    continue;
                }
            };
            let result = parse_player(&response);
            if result.status == "OK" && !result.streams.is_empty() {
                return Ok((client, result));
            }
            eprintln!(
                "  [{}] {}",
                client.label(),
                if result.streams.is_empty() && result.status == "OK" {
                    "OK but no fetchable audio streams".to_string()
                } else {
                    format!("{} {}", result.status, result.reason)
                }
            );
            if result.status == "LOGIN_REQUIRED" {
                saw_bot_gate = true;
            }
            last = Some((client, result));
        }
        if attempt == 0 && saw_bot_gate && pinned.is_none() {
            it.reset_session();
            continue;
        }
        match last {
            Some((_, result)) => bail!(
                "all clients failed for {video_id}: last status {} - {}",
                result.status,
                result.reason
            ),
            // Every call errored at the HTTP level — report the cause, not a
            // bare "no client could be reached".
            None => bail!(
                "no client could be reached for {video_id}: {}",
                last_http_error.unwrap_or_else(|| "no attempts made".to_string())
            ),
        };
    }
    unreachable!("resolve loop always returns")
}

const CHUNK: u64 = 10 * 1024 * 1024;

/// googlevideo 403s Range-less and open-ended GETs for third-party client
/// URLs (2026 enforcement); only bounded chunk requests answer.
async fn download(
    http: &reqwest::Client,
    url: &str,
    path: &str,
    total: Option<u64>,
) -> Result<u64> {
    let tmp = format!("{path}.part");
    match download_into(http, url, &tmp, total).await {
        // Atomic completion: the target only ever sees a fully written file.
        Ok(written) => {
            tokio::fs::rename(&tmp, path)
                .await
                .with_context(|| format!("renaming {tmp} to {path}"))?;
            Ok(written)
        }
        Err(e) => {
            let _ = std::fs::remove_file(&tmp);
            Err(e)
        }
    }
}

async fn download_into(
    http: &reqwest::Client,
    url: &str,
    tmp: &str,
    total: Option<u64>,
) -> Result<u64> {
    let mut file = File::create(tmp)
        .await
        .with_context(|| format!("creating {tmp}"))?;
    let mut written = 0u64;
    let mut start = 0u64;
    let mut declared_total: Option<u64> = None;
    let mut stdout = std::io::stdout();
    loop {
        let end = match total {
            Some(t) => (start + CHUNK - 1).min(t.saturating_sub(1)),
            None => start + CHUNK - 1,
        };
        let mut resp = None;
        for attempt in 0..3u32 {
            let sent = http
                .get(url)
                .header(reqwest::header::RANGE, format!("bytes={start}-{end}"))
                .send()
                .await;
            match sent {
                Ok(r) => {
                    let status = r.status().as_u16();
                    if status == 416 {
                        break; // requested past EOF: the file is complete
                    }
                    if status == 403 {
                        bail!(
                            "stream rejected (403) at byte {start}: URL expired or identity mismatch, re-run"
                        );
                    }
                    if status == 429 || (500..600).contains(&status) {
                        tokio::time::sleep(Duration::from_secs(1 << attempt)).await;
                        continue;
                    }
                    resp = Some((r, status));
                    break;
                }
                Err(e) => {
                    if attempt == 2 {
                        bail!("stream fetch failed at byte {start}: {e}");
                    }
                    tokio::time::sleep(Duration::from_secs(1 << attempt)).await;
                }
            }
        }
        let Some((resp, status)) = resp else { break };
        // A server that ignores Range and answers 200 sends the whole body.
        // That is only safe as the first (and only) request of the run.
        if status == 200 && start != 0 {
            bail!("server ignored Range at byte {start}; refusing to append a full body");
        }
        // Trust but verify: a 206 whose Content-Range starts somewhere other
        // than the requested offset would append misplaced bytes silently, and
        // its total lets an unknown-length download be validated at the end.
        if status == 206
            && let Some(cr) = resp
                .headers()
                .get(reqwest::header::CONTENT_RANGE)
                .and_then(|v| v.to_str().ok())
            && let Some((range, t)) = cr.split_once('/')
        {
            if total.is_none() {
                declared_total = t.trim().parse::<u64>().ok();
            }
            let got_start = range
                .split_whitespace()
                .last()
                .unwrap_or_default()
                .split('-')
                .next()
                .unwrap_or_default();
            if got_start
                .parse::<u64>()
                .ok()
                .filter(|s| *s == start)
                .is_none()
            {
                bail!("server answered range {cr}, expected it to start at {start}");
            }
        } else if status == 200 {
            declared_total = resp.content_length();
        }
        let mut got = 0u64;
        let mut stream = resp.bytes_stream();
        while let Some(chunk) = stream.next().await {
            let bytes = chunk?;
            file.write_all(&bytes).await?;
            got += bytes.len() as u64;
            written += bytes.len() as u64;
        }
        print!(".");
        stdout.flush()?;
        if status == 200 {
            break; // complete body already written
        }
        if got < end - start + 1 {
            break; // short 206: treat as end of data
        }
        start = end + 1;
    }
    println!();
    let expected = total.or(declared_total);
    if let Some(t) = expected
        && written != t
    {
        bail!("incomplete download: got {written} of {t} bytes");
    }
    Ok(written)
}

/// Hand the downloaded file to the first available CLI player and wait for
/// it to finish, so Ctrl-C in the terminal stops playback, not the tool.
fn play_file(path: &str) -> Result<()> {
    let players = [
        ("mpv", vec!["--no-video", "--really-quiet"]),
        ("ffplay", vec!["-nodisp", "-autoexit", "-loglevel", "quiet"]),
    ];
    for (bin, args) in players {
        if which(bin).is_none() {
            continue;
        }
        let status = std::process::Command::new(bin)
            .args(args)
            .arg(path)
            .status()
            .with_context(|| format!("spawning {bin}"))?;
        return match status.code() {
            Some(0) => Ok(()),
            other => bail!("{bin} exited with status {other:?}"),
        };
    }
    bail!("no player found (install mpv or ffmpeg/ffplay); file kept at {path}")
}

fn which(bin: &str) -> Option<std::path::PathBuf> {
    std::env::split_paths(&std::env::var_os("PATH")?)
        .map(|dir| dir.join(bin))
        .find(|p| p.is_file())
}

/// InnerTube text nodes come in four shapes depending on renderer and era:
/// `{simpleText}`, `{runs:[{text}]}`, and both nested under `.text`. Try all
/// of them everywhere instead of guessing per-field.
fn text_of(node: &serde_json::Value) -> Option<&str> {
    node["simpleText"]
        .as_str()
        .or_else(|| node["runs"][0]["text"].as_str())
        .or_else(|| node["text"]["simpleText"].as_str())
        .or_else(|| node["text"]["runs"][0]["text"].as_str())
}

/// One search row from any of the renderers the search endpoint emits.
fn parse_search_row(
    v: &serde_json::Map<String, serde_json::Value>,
) -> Option<(String, String, String, String)> {
    let id = v.get("videoId")?.as_str()?.to_string();
    let title = ["title", "shortVideoTitle"]
        .iter()
        .find_map(|key| v.get(*key).and_then(text_of))
        .unwrap_or("?")
        .to_string();
    let author = ["ownerText", "longBylineText", "shortBylineText"]
        .iter()
        .find_map(|key| v.get(*key).and_then(text_of))
        .unwrap_or("?")
        .to_string();
    // videoRenderer/compactVideoRenderer carry lengthText directly (as runs);
    // thumbnailOverlayTimeStatusRenderer lives inside the thumbnailOverlays
    // *array* — reading it as a direct key never matched.
    let duration = ["lengthText", "thumbnailOverlayTimeStatusRenderer"]
        .iter()
        .find_map(|key| v.get(*key).and_then(text_of))
        .or_else(|| {
            v.get("thumbnailOverlays")?
                .as_array()?
                .iter()
                .find_map(|o| text_of(&o["thumbnailOverlayTimeStatusRenderer"]["text"]))
        })
        .unwrap_or("?")
        .to_string();
    Some((id, title, author, duration))
}

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();
    let mut it = InnerTube::new()?;

    match cli.command {
        Command::Manifest { video_id, client } => {
            let video_id = normalize_video_id(&video_id)?;
            eprintln!("resolving {video_id}...");
            let (client, result) = resolve(&mut it, &video_id, client).await?;
            let http = stream_client(client.user_agent())?;
            // Probing is one ranged GET per stream; do them together.
            let fetchable = join_all(result.streams.iter().map(|s| probe_url(&http, &s.url))).await;
            let streams: Vec<_> = result
                .streams
                .iter()
                .zip(fetchable)
                .map(|(s, fetchable)| {
                    json!({
                        "itag": s.itag,
                        "mime": s.mime,
                        "bitrate": s.bitrate,
                        "audioQuality": s.audio_quality,
                        "contentLength": s.content_length,
                        "audioTrack": s.is_default_track,
                        "audioTrackId": s.audio_track_id,
                        "isDrc": s.is_drc,
                        "throttledN": s.throttled_n,
                        "needsDecipher": s.needs_decipher,
                        "fetchable": fetchable,
                        "url": s.url,
                    })
                })
                .collect();
            println!(
                "{}",
                json!({
                    "videoId": video_id,
                    "title": result.title,
                    "isLive": result.is_live,
                    "client": client.label(),
                    "streams": streams,
                })
            );
        }
        Command::Audio {
            video_id,
            output,
            client,
        } => {
            let video_id = normalize_video_id(&video_id)?;
            eprintln!("resolving {video_id}...");
            let (client, result) = resolve(&mut it, &video_id, client).await?;
            if result.is_live {
                bail!(
                    "'{}' is a live stream; segment-based playback is out of scope",
                    result.title
                );
            }
            let stream = best_audio(&result)
                .ok_or_else(|| anyhow::anyhow!("no directly-usable audio stream found"))?;
            let path = format!("{output}.{}", extension_for(&stream.mime));
            eprintln!(
                "title={} client={} itag={} {}kbps quality={} -> {path}",
                result.title,
                client.label(),
                stream.itag,
                stream.bitrate / 1000,
                stream.audio_quality
            );
            let http = stream_client(client.user_agent())?;
            let bytes = download(&http, &stream.url, &path, total_size(stream)).await?;
            println!("wrote {bytes} bytes");
        }
        Command::Play { video_id, client } => {
            let video_id = normalize_video_id(&video_id)?;
            eprintln!("resolving {video_id}...");
            let (client, result) = resolve(&mut it, &video_id, client).await?;
            if result.is_live {
                bail!(
                    "'{}' is a live stream; segment-based playback is out of scope",
                    result.title
                );
            }
            let stream = best_audio(&result)
                .ok_or_else(|| anyhow::anyhow!("no directly-usable audio stream found"))?;
            // video_id is validated here; the pid suffix keeps the path
            // unpredictable in shared /tmp.
            let path = format!(
                "/tmp/yt-extract-{video_id}-{}.{}",
                std::process::id(),
                extension_for(&stream.mime)
            );
            eprintln!(
                "playing '{}' ({} kbps via {})...",
                result.title,
                stream.bitrate / 1000,
                client.label()
            );
            let http = stream_client(client.user_agent())?;
            download(&http, &stream.url, &path, total_size(stream)).await?;
            let played = play_file(&path);
            let _ = std::fs::remove_file(&path);
            played?;
        }
        Command::Search { query, json } => {
            it.bootstrap("https://www.youtube.com/", Client::VisionOs)
                .await;
            let response = it.search(Client::VisionOs, &query).await?;
            let two_column = &response["contents"]["twoColumnSearchResultsRenderer"]["primaryContents"]
                ["sectionListRenderer"]["contents"];
            let flat = &response["contents"]["sectionListRenderer"]["contents"];
            let sections = match (two_column.as_array(), flat.as_array()) {
                (Some(arr), _) | (None, Some(arr)) => arr,
                _ => {
                    eprintln!("no video results parsed (unexpected response shape)");
                    return Ok(());
                }
            };
            let mut rows: Vec<(String, String, String, String)> = Vec::new();
            for section in sections {
                for item in section["itemSectionRenderer"]["contents"]
                    .as_array()
                    .map(Vec::as_slice)
                    .unwrap_or_default()
                {
                    let renderer = [
                        "videoRenderer",
                        "compactVideoRenderer",
                        "playlistVideoRenderer",
                    ]
                    .iter()
                    .find_map(|key| item.get(*key).and_then(|v| v.as_object()));
                    if let Some(v) = renderer
                        && let Some(row) = parse_search_row(v)
                    {
                        rows.push(row);
                    }
                }
            }
            if rows.is_empty() {
                eprintln!("no video results parsed");
            } else if json {
                let arr: Vec<_> = rows
                    .iter()
                    .map(|(id, title, author, duration)| {
                        json!({
                            "id": id, "title": title, "author": author, "duration": duration
                        })
                    })
                    .collect();
                println!("{}", serde_json::to_string_pretty(&arr)?);
            } else {
                for (id, title, author, duration) in &rows {
                    println!("{id}  {duration:>8}  {author} — {title}");
                }
            }
        }
    }
    Ok(())
}
