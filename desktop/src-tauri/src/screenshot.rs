use notify::{Event, EventKind, RecursiveMode, Watcher};
use serde::Serialize;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::thread;
use tauri::{AppHandle, Emitter};

/// Watches the user's Desktop for freshly-created screenshots and forwards
/// the path to the frontend so it can suggest sending it.
///
/// macOS default:  `~/Desktop/Screenshot 2025-01-01 at 12.34.56.png`
/// French macOS:   `~/Desktop/Capture d’écran ...`
/// Windows Snip:   `%USERPROFILE%\Pictures\Screenshots\Screenshot (n).png`
pub struct ScreenshotWatcher {
    stop: Arc<AtomicBool>,
    _handle: thread::JoinHandle<()>,
}

#[derive(Clone, Debug, Serialize)]
struct ScreenshotEvent {
    path: String,
    name: String,
}

impl ScreenshotWatcher {
    pub fn start(app: AppHandle) -> Result<Self, notify::Error> {
        let stop = Arc::new(AtomicBool::new(false));
        let stop_thread = stop.clone();

        let (tx, rx) = std::sync::mpsc::channel::<notify::Result<Event>>();
        let mut watcher = notify::recommended_watcher(move |res| {
            let _ = tx.send(res);
        })?;

        for dir in watch_dirs() {
            if dir.exists() {
                let _ = watcher.watch(&dir, RecursiveMode::NonRecursive);
            }
        }

        let handle = thread::spawn(move || {
            // Keep watcher alive for the thread's lifetime.
            let _keep = watcher;
            let mut recent: Vec<(PathBuf, std::time::Instant)> = Vec::new();

            while !stop_thread.load(Ordering::Relaxed) {
                match rx.recv_timeout(std::time::Duration::from_millis(500)) {
                    Ok(Ok(event)) => {
                        if !matches!(event.kind, EventKind::Create(_) | EventKind::Modify(_)) {
                            continue;
                        }
                        for path in event.paths {
                            if !is_screenshot(&path) { continue; }

                            // De-duplicate — many watchers fire multiple events per file.
                            let now = std::time::Instant::now();
                            recent.retain(|(_, t)| now.duration_since(*t).as_secs() < 3);
                            if recent.iter().any(|(p, _)| p == &path) { continue; }
                            recent.push((path.clone(), now));

                            let name = path
                                .file_name()
                                .and_then(|n| n.to_str())
                                .unwrap_or("")
                                .to_string();
                            let payload = ScreenshotEvent {
                                path: path.to_string_lossy().to_string(),
                                name,
                            };
                            let _ = app.emit("screenshot-captured", payload);
                        }
                    }
                    Ok(Err(_)) | Err(std::sync::mpsc::RecvTimeoutError::Timeout) => continue,
                    Err(std::sync::mpsc::RecvTimeoutError::Disconnected) => break,
                }
            }
        });

        Ok(Self { stop, _handle: handle })
    }

    pub fn stop(self) {
        self.stop.store(true, Ordering::Relaxed);
    }
}

fn watch_dirs() -> Vec<PathBuf> {
    let mut v = Vec::new();
    if let Some(desk) = dirs::desktop_dir() { v.push(desk); }
    if let Some(pics) = dirs::picture_dir() {
        v.push(pics.join("Screenshots"));
        v.push(pics);
    }
    v
}

fn is_screenshot(path: &std::path::Path) -> bool {
    let Some(name) = path.file_name().and_then(|n| n.to_str()) else { return false };
    let lower = name.to_lowercase();
    if !(lower.ends_with(".png") || lower.ends_with(".jpg") || lower.ends_with(".jpeg")) {
        return false;
    }
    lower.starts_with("screenshot")
        || lower.starts_with("screen shot")
        || lower.starts_with("capture d'écran")
        || lower.starts_with("capture d’écran")
        || lower.starts_with("capture")
        || lower.starts_with("bildschirmfoto")
}
