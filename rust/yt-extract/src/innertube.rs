use std::collections::BTreeMap;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use anyhow::{Context, Result, bail};
use reqwest::Client as Http;
use reqwest::header::{HeaderMap, HeaderName, HeaderValue, SET_COOKIE};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

use crate::clients::{API_KEY, Client};

const SESSION_TTL: Duration = Duration::from_secs(12 * 3600);

#[derive(Clone, Default, Serialize, Deserialize)]
struct Session {
    visitor_data: Option<String>,
    cookies: BTreeMap<String, String>,
    /// When the session was formed. The TTL is measured from this, not from
    /// last use: refreshing on every response would let a session in constant
    /// use live past the point where YouTube considers it stale.
    #[serde(default, alias = "saved_at")]
    created_at: u64,
}

fn now_secs() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

/// $XDG_CACHE_HOME/yt-extract, falling back to $HOME/.cache/yt-extract.
/// An embedding app that needs a specific location can set XDG_CACHE_HOME
/// before calling in.
fn session_dir() -> Option<PathBuf> {
    if let Some(cache) = std::env::var_os("XDG_CACHE_HOME") {
        let p = PathBuf::from(cache);
        if p.is_absolute() {
            return Some(p.join("yt-extract"));
        }
    }
    let home = std::env::var_os("HOME")?;
    Some(PathBuf::from(home).join(".cache").join("yt-extract"))
}

fn load_session() -> Session {
    let fresh = |s: &Session| now_secs().saturating_sub(s.created_at) <= SESSION_TTL.as_secs();
    let Some(dir) = session_dir() else {
        return Session::default();
    };
    let Ok(Ok(session)) = std::fs::read_to_string(dir.join("session.json"))
        .map(|j| serde_json::from_str::<Session>(&j))
    else {
        return Session::default();
    };
    if !fresh(&session) || session.created_at == 0 {
        return Session::default();
    }
    eprintln!(
        "  cached session loaded ({} cookies{})",
        session.cookies.len(),
        if session.visitor_data.is_some() {
            ", visitorData"
        } else {
            ""
        }
    );
    session
}

/// Cookies are credentials: write 0600, through a temp file, then rename, so
/// a crash mid-write never leaves a half-written (or half-permissioned) jar.
fn save_session(session: &Session) {
    let Some(dir) = session_dir() else {
        return;
    };
    if std::fs::create_dir_all(&dir).is_err() {
        return;
    }
    let Ok(json) = serde_json::to_string(session) else {
        return;
    };
    let tmp = dir.join("session.json.tmp");
    if std::fs::write(&tmp, json).is_err() {
        return;
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let _ = std::fs::set_permissions(&tmp, std::fs::Permissions::from_mode(0o600));
    }
    let _ = std::fs::rename(&tmp, dir.join("session.json"));
}

fn delete_session_file() {
    if let Some(dir) = session_dir() {
        let _ = std::fs::remove_file(dir.join("session.json"));
    }
}

/// Store name=value pairs from Set-Cookie headers. A Set-Cookie that deletes
/// (Max-Age=0 or an empty value) removes the cookie instead of planting a
/// corpse in the jar. Never touches created_at — TTL counts from formation.
fn harvest_cookies(headers: &HeaderMap, session: &Mutex<Session>) {
    let mut ops = Vec::new();
    for value in headers.get_all(SET_COOKIE) {
        let Ok(text) = value.to_str() else { continue };
        let mut parts = text.split(';');
        let Some((name, data)) = parts.next().unwrap_or_default().split_once('=') else {
            continue;
        };
        if name.is_empty() {
            continue;
        }
        let deletes = data.is_empty()
            || parts
                .map(|attr| attr.trim_start().to_ascii_lowercase())
                .any(|a| a == "max-age=0" || a.starts_with("max-age=-"));
        ops.push((name.to_string(), data.to_string(), deletes));
    }
    if ops.is_empty() {
        return;
    }
    let mut session = session.lock().unwrap();
    let mut changed = false;
    for (name, data, deletes) in ops {
        if deletes {
            changed |= session.cookies.remove(&name).is_some();
        } else if session.cookies.get(&name) != Some(&data) {
            session.cookies.insert(name, data);
            changed = true;
        }
    }
    if changed && session.created_at == 0 {
        session.created_at = now_secs();
    }
    if changed {
        save_session(&session);
    }
}

pub struct InnerTube {
    http: Http,
    session: Arc<Mutex<Session>>,
}

impl InnerTube {
    pub fn new() -> Result<Self> {
        let session = Arc::new(Mutex::new(load_session()));
        let http = Http::builder()
            // Bootstrap follows redirects manually so Set-Cookie headers
            // from every hop are captured, not just the final one.
            .redirect(reqwest::redirect::Policy::none())
            .timeout(Duration::from_secs(15))
            .build()
            .context("building http client")?;
        Ok(Self { http, session })
    }

    /// YouTube bot-gates cold anonymous player calls ("Sign in to confirm
    /// you're not a bot"). Visiting a watch page first plants session
    /// cookies (VISITOR_INFO1_LIVE, YSC, GPS, __Secure-YNID) and yields
    /// visitorData; player calls carrying both pass the gate. Mirrors what
    /// yt-dlp and NewPipe do on every cold session. The result is cached to
    /// ~/.cache/yt-extract so repeated runs never re-hit the HTML tier
    /// (which is what rate-limits and captcha-walls an IP).
    pub async fn bootstrap(&mut self, url: &str, client: Client) {
        if self.session.lock().unwrap().visitor_data.is_some() {
            return;
        }
        // Bootstrap is an upgrade, not a requirement: captcha walls and rate
        // limits (429 -> /sorry) must not abort extraction. The player API is
        // attempted regardless; gated videos then surface their real status.
        let mut target = url.to_string();
        let mut html = String::new();
        for _ in 0..7 {
            let mut builder = self
                .http
                .get(&target)
                .header(reqwest::header::USER_AGENT, client.user_agent())
                .header(reqwest::header::ACCEPT_LANGUAGE, "en");
            if let Some(cookie) = self.cookie_header() {
                builder = builder.header(reqwest::header::COOKIE, cookie);
            }
            let resp = match builder.send().await {
                Ok(resp) => resp,
                Err(e) => {
                    eprintln!("  session bootstrap skipped: {e}");
                    return;
                }
            };
            harvest_cookies(resp.headers(), &self.session);
            let next = resp
                .headers()
                .get(reqwest::header::LOCATION)
                .and_then(|l| l.to_str().ok())
                .and_then(|loc| resp.url().join(loc).ok());
            if let Some(next) = next {
                target = next.to_string();
                continue;
            }
            if !resp.status().is_success() {
                eprintln!(
                    "  session bootstrap skipped: watch page HTTP {} (rate limit/captcha?)",
                    resp.status()
                );
                return;
            }
            html = resp.text().await.unwrap_or_default();
            break;
        }
        let visitor_data = extract_visitor_data(&html);
        let mut session = self.session.lock().unwrap();
        session.visitor_data = visitor_data;
        if session.created_at == 0 {
            session.created_at = now_secs();
        }
        save_session(&session);
        let vd_len = session.visitor_data.as_ref().map(String::len);
        drop(session);
        match vd_len {
            Some(len) => eprintln!("  session established (visitorData {len} bytes)"),
            None => eprintln!("  warning: no visitorData found in watch page"),
        }
    }

    /// Drop the cached session entirely, so the next bootstrap plants a
    /// fresh one. Used when a stored session starts getting bot-gated.
    pub fn reset_session(&mut self) {
        *self.session.lock().unwrap() = Session::default();
        delete_session_file();
        eprintln!("  session reset (bot-gated); re-bootstrapping");
    }

    fn cookie_header(&self) -> Option<String> {
        let session = self.session.lock().unwrap();
        if session.cookies.is_empty() {
            return None;
        }
        Some(
            session
                .cookies
                .iter()
                .map(|(k, v)| format!("{k}={v}"))
                .collect::<Vec<_>>()
                .join("; "),
        )
    }

    fn visitor_id(&self) -> String {
        self.session
            .lock()
            .unwrap()
            .visitor_data
            .clone()
            .unwrap_or_default()
    }

    /// A header that fails to parse is a bug or a hostile value, not
    /// something to silently drop — propagate.
    fn headers(&self, client: Client) -> Result<HeaderMap> {
        let mut headers = HeaderMap::new();
        let mut insert = |name: HeaderName, value: String| -> Result<()> {
            headers.insert(name, HeaderValue::from_str(&value).context("header value")?);
            Ok(())
        };
        insert(reqwest::header::USER_AGENT, client.user_agent().to_string())?;
        insert(
            reqwest::header::CONTENT_TYPE,
            "application/json".to_string(),
        )?;
        insert(
            HeaderName::from_static("x-goog-api-key"),
            API_KEY.to_string(),
        )?;
        insert(
            HeaderName::from_static("x-youtube-client-name"),
            client.client_name_id().to_string(),
        )?;
        insert(
            HeaderName::from_static("x-youtube-client-version"),
            client.context()["client"]["clientVersion"]
                .as_str()
                .unwrap_or_default()
                .to_string(),
        )?;
        let visitor = self.visitor_id();
        if !visitor.is_empty() {
            insert(HeaderName::from_static("x-goog-visitor-id"), visitor)?;
        }
        if let Some(cookie) = self.cookie_header() {
            insert(reqwest::header::COOKIE, cookie)?;
        }
        Ok(headers)
    }

    fn player_context(&self, client: Client) -> Value {
        let mut ctx = client.context()["client"].clone();
        let visitor = self.visitor_id();
        if !visitor.is_empty() {
            ctx["visitorData"] = json!(visitor);
        }
        ctx
    }

    async fn post(&self, path: &str, client: Client, body: Value) -> Result<Value> {
        let url = format!("https://www.youtube.com/youtubei/v1/{path}?prettyPrint=false&alt=json");
        let headers = self.headers(client)?;
        // 429/5xx are transient rate limits, not verdicts: back off and try
        // twice more before surfacing the failure.
        let backoffs = [2u64, 5];
        let mut attempt = 0;
        loop {
            let resp = self
                .http
                .post(&url)
                .headers(headers.clone())
                .json(&body)
                .send()
                .await
                .with_context(|| format!("POST {path} as {}", client.label()))?;
            let status = resp.status();
            let retryable = status.as_u16() == 429 || status.is_server_error();
            let headers_clone = resp.headers().clone();
            // Check the status before asking for JSON: an error page is not a
            // JSON body, and the decode failure would mask the real cause.
            if !status.is_success() {
                if retryable && attempt < backoffs.len() {
                    tokio::time::sleep(Duration::from_secs(backoffs[attempt])).await;
                    attempt += 1;
                    continue;
                }
                let text = resp.text().await.unwrap_or_default();
                let msg = serde_json::from_str::<Value>(&text)
                    .ok()
                    .and_then(|v| v["error"]["message"].as_str().map(String::from))
                    .unwrap_or_else(|| text.chars().take(120).collect());
                bail!("{path} failed as {}: HTTP {status}: {msg}", client.label());
            }
            let value: Value = resp
                .json()
                .await
                .with_context(|| format!("decoding {path} response"))?;
            harvest_cookies(&headers_clone, &self.session);
            // Any API answer carries a visitorData the next call can present;
            // picking it up here lets the session form without ever fetching a
            // watch page.
            if let Some(vd) = value["responseContext"]["visitorData"].as_str()
                && self.session.lock().unwrap().visitor_data.is_none()
            {
                let mut session = self.session.lock().unwrap();
                session.visitor_data = Some(vd.to_string());
                if session.created_at == 0 {
                    session.created_at = now_secs();
                }
                save_session(&session);
            }
            return Ok(value);
        }
    }

    pub async fn player(&self, client: Client, video_id: &str) -> Result<Value> {
        self.post(
            "player",
            client,
            json!({
                "context": { "client": self.player_context(client) },
                "videoId": video_id,
                "contentCheckOk": true,
                "racyCheckOk": true,
            }),
        )
        .await
    }

    pub async fn search(&self, client: Client, query: &str) -> Result<Value> {
        self.post(
            "search",
            client,
            json!({
                "context": { "client": self.player_context(client) },
                "query": query,
            }),
        )
        .await
    }
}

fn extract_visitor_data(html: &str) -> Option<String> {
    let marker = "\"visitorData\":\"";
    let start = html.find(marker)? + marker.len();
    let rest = &html[start..];
    let end = rest.find('"')?;
    let raw = &rest[..end];
    if raw.is_empty() {
        None
    } else {
        Some(raw.to_string())
    }
}
