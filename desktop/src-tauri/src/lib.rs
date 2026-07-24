mod lan;
mod screenshot;

use parking_lot::Mutex;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tauri::menu::{Menu, MenuItem};
use tauri::tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent};
use tauri::{AppHandle, Emitter, Manager, WindowEvent};
use tauri_plugin_global_shortcut::{GlobalShortcutExt, Shortcut, ShortcutState};

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct LanPeer {
    #[serde(rename = "deviceId")]
    pub device_id: String,
    pub name: String,
    pub platform: String,
    pub host: String,
    pub port: u16,
}

struct AppState {
    lan: Arc<Mutex<Option<lan::LanService>>>,
    screenshots: Arc<Mutex<Option<screenshot::ScreenshotWatcher>>>,
}

// ─────────────────────────── LAN commands ───────────────────────────

#[tauri::command]
fn lan_start(
    state: tauri::State<'_, AppState>,
    app: AppHandle,
    device_id: String,
    name: String,
) -> Result<(), String> {
    let mut guard = state.lan.lock();
    if guard.is_none() {
        let svc = lan::LanService::start(app.clone()).map_err(|e| e.to_string())?;
        *guard = Some(svc);
    }
    if let Some(svc) = guard.as_ref() {
        svc.advertise(&device_id, &name).map_err(|e| e.to_string())?;
    }
    Ok(())
}

#[tauri::command]
fn lan_update_name(
    state: tauri::State<'_, AppState>,
    device_id: String,
    name: String,
) -> Result<(), String> {
    let guard = state.lan.lock();
    if let Some(svc) = guard.as_ref() {
        svc.advertise(&device_id, &name).map_err(|e| e.to_string())?;
    }
    Ok(())
}

#[tauri::command]
fn lan_stop(state: tauri::State<'_, AppState>) -> Result<(), String> {
    let mut guard = state.lan.lock();
    if let Some(svc) = guard.take() {
        svc.stop();
    }
    Ok(())
}

// ─────────────────────────── Screenshot commands ─────────────────────

#[tauri::command]
fn screenshots_start(state: tauri::State<'_, AppState>, app: AppHandle) -> Result<(), String> {
    let mut guard = state.screenshots.lock();
    if guard.is_some() { return Ok(()); }
    let w = screenshot::ScreenshotWatcher::start(app.clone()).map_err(|e| e.to_string())?;
    *guard = Some(w);
    Ok(())
}

#[tauri::command]
fn screenshots_stop(state: tauri::State<'_, AppState>) -> Result<(), String> {
    let mut guard = state.screenshots.lock();
    if let Some(w) = guard.take() { w.stop(); }
    Ok(())
}

// ─────────────────────────── Window helpers ──────────────────────────

#[cfg(target_os = "macos")]
fn set_dock_visible(app: &AppHandle, visible: bool) {
    let policy = if visible {
        tauri::ActivationPolicy::Regular
    } else {
        tauri::ActivationPolicy::Accessory
    };
    let _ = app.set_activation_policy(policy);
}
#[cfg(not(target_os = "macos"))]
fn set_dock_visible(_app: &AppHandle, _visible: bool) {}

fn toggle_main_window(app: &AppHandle) {
    if let Some(win) = app.get_webview_window("main") {
        let visible = win.is_visible().unwrap_or(false);
        let focused = win.is_focused().unwrap_or(false);
        if visible && focused {
            let _ = win.hide();
            set_dock_visible(app, false);
        } else {
            set_dock_visible(app, true);
            let _ = win.show();
            let _ = win.unminimize();
            let _ = win.set_focus();
        }
    }
}

fn show_main_window(app: &AppHandle) {
    if let Some(win) = app.get_webview_window("main") {
        set_dock_visible(app, true);
        let _ = win.show();
        let _ = win.unminimize();
        let _ = win.set_focus();
    }
}

#[tauri::command]
fn show_window(app: AppHandle) { show_main_window(&app); }

// ─────────────────────────── File I/O commands ───────────────────────
//
// Bypass the fs plugin (which requires the JS side to use bundled npm
// packages). We're a plain-<script> frontend, so we call these directly.

#[tauri::command]
fn save_to_downloads(filename: String, bytes: Vec<u8>) -> Result<String, String> {
    let dir = dirs::download_dir()
        .ok_or_else(|| "no download dir".to_string())?;
    std::fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    let safe = filename.replace('/', "_").replace('\\', "_");
    let path = dir.join(safe);
    std::fs::write(&path, &bytes).map_err(|e| e.to_string())?;
    Ok(path.to_string_lossy().into_owned())
}

#[tauri::command]
fn open_file(path: String) -> Result<(), String> {
    // macOS `open` handles anything (Preview, QuickTime, TextEdit, …).
    #[cfg(target_os = "macos")]
    { std::process::Command::new("open").arg(&path).spawn().map_err(|e| e.to_string())?; }
    #[cfg(target_os = "windows")]
    { std::process::Command::new("cmd").args(["/C", "start", "", &path]).spawn().map_err(|e| e.to_string())?; }
    #[cfg(all(unix, not(target_os = "macos")))]
    { std::process::Command::new("xdg-open").arg(&path).spawn().map_err(|e| e.to_string())?; }
    Ok(())
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_clipboard_manager::init())
        .plugin(tauri_plugin_fs::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_updater::Builder::new().build())
        .plugin(tauri_plugin_process::init())
        .plugin(
            tauri_plugin_global_shortcut::Builder::new()
                .with_handler(|app, shortcut, event| {
                    if event.state() != ShortcutState::Pressed { return; }
                    let key = shortcut.to_string();
                    // Toggle window on Cmd/Ctrl + Shift + A
                    if key.contains("KeyA") || key.ends_with("+A") {
                        toggle_main_window(app);
                    }
                    // Push clipboard on Cmd/Ctrl + Shift + V
                    if key.contains("KeyV") || key.ends_with("+V") {
                        let _ = app.emit("shortcut-push-clipboard", ());
                        show_main_window(app);
                    }
                })
                .build(),
        )
        .setup(|app| {
            app.manage(AppState {
                lan: Arc::new(Mutex::new(None)),
                screenshots: Arc::new(Mutex::new(None)),
            });

            // ── System tray ──────────────────────────────────────────
            let show_item = MenuItem::with_id(app, "show", "Show Poof", true, None::<&str>)?;
            let send_item = MenuItem::with_id(app, "send", "Send file…", true, None::<&str>)?;
            let clip_item = MenuItem::with_id(app, "clip", "Push clipboard", true, None::<&str>)?;
            let quit_item = MenuItem::with_id(app, "quit", "Quit", true, None::<&str>)?;
            let menu = Menu::with_items(app, &[&show_item, &send_item, &clip_item, &quit_item])?;

            let _tray = TrayIconBuilder::with_id("main-tray")
                .icon(app.default_window_icon().unwrap().clone())
                .icon_as_template(true)
                .tooltip("Poof")
                .menu(&menu)
                .show_menu_on_left_click(false)
                .on_menu_event(|app, event| match event.id.as_ref() {
                    "show" => show_main_window(app),
                    "send" => {
                        show_main_window(app);
                        let _ = app.emit("tray-send-file", ());
                    }
                    "clip" => {
                        let _ = app.emit("shortcut-push-clipboard", ());
                    }
                    "quit" => {
                        app.exit(0);
                    }
                    _ => {}
                })
                .on_tray_icon_event(|tray, event| {
                    if let TrayIconEvent::Click {
                        button: MouseButton::Left,
                        button_state: MouseButtonState::Up,
                        ..
                    } = event
                    {
                        toggle_main_window(tray.app_handle());
                    }
                })
                .build(app)?;

            // ── Global shortcuts ─────────────────────────────────────
            let handle = app.handle();
            if let (Ok(sc_toggle), Ok(sc_clip)) = (
                "CommandOrControl+Shift+A".parse::<Shortcut>(),
                "CommandOrControl+Shift+V".parse::<Shortcut>(),
            ) {
                let _ = handle.global_shortcut().register(sc_toggle);
                let _ = handle.global_shortcut().register(sc_clip);
            }

            Ok(())
        })
        .on_window_event(|window, event| {
            // Close button hides to tray instead of quitting.
            if let WindowEvent::CloseRequested { api, .. } = event {
                if window.label() == "main" {
                    api.prevent_close();
                    let _ = window.hide();
                    set_dock_visible(&window.app_handle(), false);
                }
            }
        })
        .invoke_handler(tauri::generate_handler![
            lan_start,
            lan_update_name,
            lan_stop,
            screenshots_start,
            screenshots_stop,
            show_window,
            save_to_downloads,
            open_file,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
