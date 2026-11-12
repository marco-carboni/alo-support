//! ALO: link with the Odoo support ticket (events of controlled-side connections,
//! `alosupport://` scheme registration). The contract is `API-ODOO-V1.md`.
use hbb_common::{config::Config, config::LocalConfig, log, tokio};
use serde::{Deserialize, Serialize};
use std::{path::PathBuf, sync::Mutex, time::Duration};

pub const ALO_VERSION: &str = "1.5.1-alo.2";
const MAX_QUEUE: usize = 50;
const OPT_URL: &str = "alo-odoo-url";
const OPT_TOKEN: &str = "alo-device-token";

static QUEUE_LOCK: Mutex<()> = Mutex::new(());

#[derive(Serialize, Deserialize, Clone)]
struct Event {
    event_id: String,
    event: String,
    occurred_at: String,
    app_version: String,
}

fn allowed_base(base: &str) -> bool {
    let rest = match base.strip_prefix("https://") {
        Some(r) => r,
        None => return false,
    };
    let host = rest.split('/').next().unwrap_or("");
    !host.is_empty()
        && !host.contains(['@', ':', ' '])
        && (host == "alo.zone" || host.ends_with(".alo.zone"))
}

// Read from file: the server process does not see options set later by the UI process.
fn credentials() -> Option<(String, String)> {
    let base = LocalConfig::get_option_from_file(OPT_URL);
    let token = LocalConfig::get_option_from_file(OPT_TOKEN);
    if token.is_empty() || !allowed_base(&base) {
        return None;
    }
    Some((base.trim_end_matches('/').to_owned(), token))
}

fn queue_path() -> PathBuf {
    Config::path("alo-events.json")
}

fn load_queue() -> Vec<Event> {
    std::fs::read_to_string(queue_path())
        .ok()
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or_default()
}

fn store_queue(q: &[Event]) {
    let skip = q.len().saturating_sub(MAX_QUEUE);
    match serde_json::to_string(&q[skip..]) {
        Ok(s) => {
            if let Err(e) = std::fs::write(queue_path(), s) {
                log::warn!("alo: cannot store the event queue: {}", e);
            }
        }
        Err(e) => log::warn!("alo: cannot encode the event queue: {}", e),
    }
}

async fn post_event(base: &str, token: &str, ev: &Event) -> bool {
    let body = serde_json::json!({
        "device_token": token,
        "event_id": ev.event_id,
        "event": ev.event,
        "occurred_at": ev.occurred_at,
        "app_version": ev.app_version,
    })
    .to_string();
    let url = format!("{}/alo_support/api/v1/event", base);
    let res = tokio::time::timeout(
        Duration::from_secs(5),
        crate::post_request(url, body, "Content-Type: application/json"),
    )
    .await;
    match res {
        Ok(Ok(text)) => serde_json::from_str::<serde_json::Value>(&text)
            .map(|v| v.get("ok").and_then(|o| o.as_bool()) == Some(true))
            .unwrap_or(false),
        _ => false,
    }
}

async fn send_pending(new: Option<Event>) {
    let (base, token) = match credentials() {
        Some(c) => c,
        None => return,
    };
    // Order is kept: older queued events first, then the new one.
    let mut pending = {
        let _g = QUEUE_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let mut q = load_queue();
        if let Some(ev) = new {
            q.push(ev);
        }
        store_queue(&q);
        q
    };
    let mut sent = Vec::new();
    for ev in pending.iter() {
        if !post_event(&base, &token, ev).await {
            break;
        }
        sent.push(ev.event_id.clone());
    }
    pending.retain(|e| !sent.contains(&e.event_id));
    let _g = QUEUE_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    // Events queued meanwhile by another task stay in the file.
    let mut current = load_queue();
    current.retain(|e| !sent.contains(&e.event_id));
    store_queue(&current);
}

fn send_event(name: &str) {
    if credentials().is_none() {
        return;
    }
    let ev = Event {
        event_id: uuid::Uuid::new_v4().to_string(),
        event: name.to_owned(),
        occurred_at: chrono::Utc::now().format("%Y-%m-%dT%H:%M:%SZ").to_string(),
        app_version: ALO_VERSION.to_owned(),
    };
    tokio::spawn(send_pending(Some(ev)));
}

pub fn connection_started() {
    send_event("connection_started");
}

pub fn connection_ended() {
    send_event("connection_ended");
}

/// Retries queued events (called at start of the server).
pub fn flush_queue() {
    if credentials().is_some() && !load_queue().is_empty() {
        tokio::spawn(send_pending(None));
    }
}

/// Registers `alosupport://` for the current user only (no administrator rights).
#[cfg(windows)]
pub fn register_scheme() {
    use winreg::{enums::*, RegKey};
    let exe = match std::env::current_exe() {
        Ok(p) => p,
        Err(_) => return,
    };
    let command = format!("\"{}\" \"%1\"", exe.display());
    let hkcu = RegKey::predef(HKEY_CURRENT_USER);
    let res = (|| -> std::io::Result<()> {
        let (root, _) = hkcu.create_subkey("Software\\Classes\\alosupport")?;
        let current: String = root.get_value("").unwrap_or_default();
        let (cmd_key, _) = root.create_subkey("shell\\open\\command")?;
        let cur_cmd: String = cmd_key.get_value("").unwrap_or_default();
        if current == "URL:ALO Support" && cur_cmd == command {
            return Ok(());
        }
        root.set_value("", &"URL:ALO Support")?;
        root.set_value("URL Protocol", &"")?;
        cmd_key.set_value("", &command)?;
        Ok(())
    })();
    if let Err(e) = res {
        log::warn!("alo: cannot register alosupport://: {}", e);
    }
}

#[cfg(test)]
mod tests {
    use super::allowed_base;

    #[test]
    fn base_whitelist() {
        assert!(allowed_base("https://staging.alo.zone"));
        assert!(allowed_base("https://alo.zone"));
        assert!(!allowed_base("http://staging.alo.zone"));
        assert!(!allowed_base("https://evilalo.zone"));
        assert!(!allowed_base("https://alo.zone.evil.com"));
        assert!(!allowed_base("https://x@alo.zone"));
    }
}
