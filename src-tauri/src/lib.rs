//! The native shell: tray/menu-bar item, the dashboard flyout, celebrations, and OS services.
//! Everything the user sees is the shared web UI in `ui/`, identical on macOS and Windows.

mod github;
mod login;
mod push;
mod storage;

use base64::Engine;
use serde_json::json;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};
use tauri::image::Image;
use tauri::menu::{Menu, MenuItem, PredefinedMenuItem};
use tauri::tray::{MouseButton, MouseButtonState, TrayIcon, TrayIconBuilder, TrayIconEvent};
use tauri::{AppHandle, Emitter, Manager, PhysicalPosition, Rect, RunEvent, WebviewWindow, WindowEvent};

const TRAY: &str = "gitgaze";
/// Space above the macOS flyout body for the popover arrow; see `--arrow` in app.css.
const ARROW: f64 = if cfg!(target_os = "macos") { 11.0 } else { 0.0 };
const MARGIN: f64 = 12.0;

#[derive(Default)]
struct Shell {
    tray_rect: Option<Rect>,
    hidden_at: Option<Instant>,
}

static CELEBRATION: AtomicU64 = AtomicU64::new(0);

fn popover(app: &AppHandle) -> WebviewWindow {
    app.get_webview_window("popover").expect("popover window")
}

fn tray_rect(app: &AppHandle) -> Option<Rect> {
    let saved = app.state::<Mutex<Shell>>().lock().unwrap().tray_rect;
    saved.or_else(|| app.tray_by_id(TRAY).and_then(|tray| tray.rect().ok().flatten()))
}

/// Physical anchor (centre x, top, bottom) of the tray item, plus the monitor that contains it.
fn anchor(app: &AppHandle) -> Option<(f64, f64, f64, tauri::Monitor)> {
    let rect = tray_rect(app)?;
    let window = popover(app);
    let (position, size) = match (rect.position, rect.size) {
        (tauri::Position::Physical(p), tauri::Size::Physical(s)) => ((p.x as f64, p.y as f64), (s.width as f64, s.height as f64)),
        (position, size) => {
            let scale = window.scale_factor().unwrap_or(1.0);
            let p = position.to_physical::<f64>(scale);
            let s = size.to_physical::<f64>(scale);
            ((p.x, p.y), (s.width, s.height))
        }
    };
    let centre = position.0 + size.0 / 2.0;
    let monitor = window
        .monitor_from_point(centre, position.1 + size.1 / 2.0)
        .ok()
        .flatten()
        .or_else(|| window.primary_monitor().ok().flatten())?;
    Some((centre, position.1, position.1 + size.1, monitor))
}

/// Places a window of `width`×`height` logical points beside the tray item, inside the work area:
/// below a top menu bar (macOS), or above/below the taskbar (Windows). Returns the anchor's x
/// offset in logical points, for the popover arrow.
fn place(app: &AppHandle, window: &WebviewWindow, width: f64, height: f64, gap: f64) -> f64 {
    let Some((centre, top, bottom, monitor)) = anchor(app) else {
        let _ = window.center();
        return width / 2.0;
    };
    let scale = monitor.scale_factor();
    let area = monitor.work_area();
    let (left, right) = (area.position.x as f64, area.position.x as f64 + area.size.width as f64);
    let (area_top, area_bottom) = (area.position.y as f64, area.position.y as f64 + area.size.height as f64);
    let (w, h) = (width * scale, height * scale);
    let x = (centre - w / 2.0).clamp(left + 6.0 * scale, (right - w - 6.0 * scale).max(left));
    let monitor_middle = monitor.position().y as f64 + monitor.size().height as f64 / 2.0;
    let y = if top < monitor_middle {
        (bottom + gap * scale).max(area_top)
    } else {
        (top.min(area_bottom) - h - gap * scale).max(area_top)
    };
    let _ = window.set_position(PhysicalPosition::new(x.round() as i32, y.round() as i32));
    (centre - x) / scale
}

fn show_popover(app: &AppHandle) {
    let window = popover(app);
    let gap = if cfg!(target_os = "macos") { 0.0 } else { MARGIN };
    let _ = window.set_size(tauri::LogicalSize::new(384.0, 640.0 + ARROW));
    let arrow = place(app, &window, 384.0, 640.0 + ARROW, gap);
    let _ = window.emit("popover-shown", json!({ "arrow": arrow }));
    let _ = window.show();
    let _ = window.set_focus();
}

fn toggle_popover(app: &AppHandle) {
    let window = popover(app);
    if window.is_visible().unwrap_or(false) {
        let _ = window.hide();
        return;
    }
    // A click on the tray item first blurs (and hides) the open flyout; don't reopen it.
    let hidden_at = app.state::<Mutex<Shell>>().lock().unwrap().hidden_at;
    if hidden_at.is_some_and(|at| at.elapsed() < Duration::from_millis(300)) {
        return;
    }
    show_popover(app);
}

#[tauri::command]
fn hide_popover(app: AppHandle) {
    let _ = popover(&app).hide();
}

#[tauri::command]
fn platform() -> &'static str {
    if cfg!(target_os = "macos") { "macos" } else if cfg!(windows) { "windows" } else { "linux" }
}

/// Replaces the tray image with one the UI rendered. `width`/`height` are in points; macOS
/// otherwise forces every status item image to 18 points tall.
#[tauri::command]
fn set_tray(app: AppHandle, png: String, width: f64, height: f64, tooltip: String) -> Result<(), String> {
    let tray = app.tray_by_id(TRAY).ok_or("No tray")?;
    let bytes = base64::engine::general_purpose::STANDARD.decode(png).map_err(|e| e.to_string())?;
    let image = Image::from_bytes(&bytes).map_err(|e| e.to_string())?;
    tray.set_icon(Some(image)).map_err(|e| e.to_string())?;
    #[cfg(target_os = "macos")]
    let _ = tray.with_inner_tray_icon(move |inner| {
        if let Some(item) = inner.ns_status_item() {
            if let Some(mtm) = objc2_foundation::MainThreadMarker::new() {
                if let Some(image) = item.button(mtm).and_then(|button| button.image()) {
                    image.setSize(objc2_foundation::NSSize::new(width, height));
                }
            }
        }
    });
    #[cfg(not(target_os = "macos"))]
    let _ = (width, height);
    tray.set_tooltip(Some(tooltip)).map_err(|e| e.to_string())
}

/// Whether the menu bar behind the status item is dark. It can differ from the system appearance:
/// macOS tints the menu bar from the wallpaper.
#[tauri::command]
fn menu_bar_dark(app: AppHandle) -> Option<bool> {
    #[cfg(target_os = "macos")]
    {
        let tray = app.tray_by_id(TRAY)?;
        tray.with_inner_tray_icon(|inner| {
            use objc2_app_kit::{NSAppearanceCustomization, NSAppearanceNameAqua, NSAppearanceNameDarkAqua};
            let mtm = objc2_foundation::MainThreadMarker::new()?;
            let button = inner.ns_status_item()?.button(mtm)?;
            let names = unsafe { objc2_foundation::NSArray::from_slice(&[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]) };
            let best = button.effectiveAppearance().bestMatchFromAppearancesWithNames(&names)?;
            Some(&*best == unsafe { NSAppearanceNameDarkAqua })
        })
        .ok()
        .flatten()
    }
    #[cfg(not(target_os = "macos"))]
    {
        let _ = app;
        None
    }
}

/// Shows the click-through celebration overlay under the tray item for six seconds.
#[tauri::command]
fn celebrate(app: AppHandle, count: u32, record: bool, sample: bool, style: String, reduced: bool, colors: serde_json::Value) -> Result<(), String> {
    let window = app.get_webview_window("celebration").ok_or("No celebration window")?;
    let height = if reduced { 90.0 } else { 340.0 };
    let _ = window.set_size(tauri::LogicalSize::new(440.0, height));
    let anchor = place(&app, &window, 440.0, height, 6.0);
    let id = CELEBRATION.fetch_add(1, Ordering::SeqCst) + 1;
    let _ = window.set_ignore_cursor_events(true);
    let _ = window.emit("celebrate", json!({ "count": count, "record": record, "sample": sample, "style": style, "anchor": anchor, "reduced": reduced,
        "fromBelow": cfg!(windows), "accent": colors["accent"], "accentSoft": colors["accentSoft"], "gold": colors["gold"] }));
    window.show().map_err(|e| e.to_string())?;
    std::thread::spawn(move || {
        std::thread::sleep(Duration::from_secs(6));
        if CELEBRATION.load(Ordering::SeqCst) == id {
            let _ = window.hide();
        }
    });
    Ok(())
}

fn push_callback(app: &AppHandle) -> push::OnPush {
    let app = app.clone();
    Arc::new(move || {
        let _ = app.emit_to("popover", "push", ());
    })
}

#[tauri::command]
fn push_listen(app: AppHandle, monitor: tauri::State<'_, push::Monitor>) -> Result<(), String> {
    monitor.start(push_callback(&app))
}

#[tauri::command]
fn push_configure(app: AppHandle, monitor: tauri::State<'_, push::Monitor>, enabled: bool) -> Result<(), String> {
    push::configure(&monitor, enabled, push_callback(&app))
}

#[tauri::command]
fn quit(app: AppHandle) {
    app.exit(0);
}

fn build_tray(app: &AppHandle) -> tauri::Result<TrayIcon> {
    let menu = Menu::with_items(
        app,
        &[
            &MenuItem::with_id(app, "open", "Open Stoke", true, None::<&str>)?,
            &MenuItem::with_id(app, "refresh", "Refresh", true, Some("CmdOrCtrl+R"))?,
            &PredefinedMenuItem::separator(app)?,
            &MenuItem::with_id(app, "updates", "Check for Updates…", true, None::<&str>)?,
            &MenuItem::with_id(app, "quit", "Quit Stoke", true, Some("CmdOrCtrl+Q"))?,
        ],
    )?;
    TrayIconBuilder::with_id(TRAY)
        .icon(app.default_window_icon().cloned().expect("app icon"))
        .tooltip("Stoke")
        .menu(&menu)
        .show_menu_on_left_click(false)
        .on_menu_event(|app, event| match event.id.as_ref() {
            "open" => show_popover(app),
            "refresh" => drop(app.emit_to("popover", "refresh", ())),
            "updates" => drop(app.emit_to("popover", "check-updates", ())),
            "quit" => app.exit(0),
            _ => {}
        })
        .on_tray_icon_event(|tray, event| {
            let app = tray.app_handle();
            match event {
                TrayIconEvent::Click { button: MouseButton::Left, button_state: MouseButtonState::Up, rect, .. } => {
                    app.state::<Mutex<Shell>>().lock().unwrap().tray_rect = Some(rect);
                    toggle_popover(app);
                }
                TrayIconEvent::Enter { rect, .. } | TrayIconEvent::Move { rect, .. } => {
                    app.state::<Mutex<Shell>>().lock().unwrap().tray_rect = Some(rect);
                }
                _ => {}
            }
        })
        .build(app)
}

/// Stoke was called GitGaze until 1.1.7. On Windows the installer keys everything on the product
/// name, so Stoke installs beside GitGaze; this removes GitGaze (keeping its data, which Stoke
/// shares) and carries over launch at login. Returns whether GitGaze launched at login.
#[cfg(windows)]
fn retire_gitgaze() -> bool {
    let reg_value = |key: &str, name: &str| -> Option<String> {
        let output = github::command("reg").args(["query", key, "/v", name]).output().ok()?;
        let text = String::from_utf8_lossy(&output.stdout).into_owned();
        let value = text.lines().find_map(|line| line.split_once("REG_SZ").map(|(_, value)| value.trim().to_string()))?;
        Some(value)
    };
    let Some(uninstaller) = reg_value(r"HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\GitGaze", "UninstallString") else {
        return false;
    };
    let launched_at_login = reg_value(r"HKCU\Software\Microsoft\Windows\CurrentVersion\Run", "GitGaze").is_some();
    // A running GitGaze holds the single-instance lock Stoke shares, so stop it first.
    let _ = github::command("taskkill").args(["/IM", "GitGaze.exe", "/F"]).output();
    // /S: silent. Without /DELETEAPPDATA the uninstaller leaves the shared settings and cache alone.
    let _ = github::command(uninstaller.trim_matches('"')).arg("/S").spawn();
    launched_at_login
}

pub fn run() {
    let arguments: Vec<String> = std::env::args().collect();
    if arguments.iter().any(|argument| argument == "--listener-smoke-test") {
        return push::smoke_test();
    }
    let smoke = arguments.iter().any(|argument| argument == "--smoke-test");
    #[cfg(windows)]
    let keep_launch_at_login = retire_gitgaze();

    #[allow(unused_mut)]
    let mut builder = tauri::Builder::default()
        .plugin(tauri_plugin_single_instance::init(|app, arguments, _| {
            // Launching Stoke again opens the flyout; `--celebrate` previews a celebration (for testing).
            if arguments.iter().any(|argument| argument == "--celebrate") {
                let _ = app.emit_to("popover", "preview-celebration", ());
            } else {
                show_popover(app);
            }
        }))
        .plugin(tauri_plugin_notification::init())
        .plugin(tauri_plugin_updater::Builder::new().build())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_process::init())
        .plugin(tauri_plugin_opener::init());
    #[cfg(windows)]
    {
        builder = builder.plugin(tauri_plugin_autostart::init(tauri_plugin_autostart::MacosLauncher::LaunchAgent, None));
    }
    let app = builder
        .manage(Mutex::new(Shell::default()))
        .manage(github::Session::default())
        .manage(push::Monitor::default())
        .invoke_handler(tauri::generate_handler![
            github::gh_installed,
            github::github_connect,
            github::github_query,
            github::github_scopes,
            storage::load_state,
            storage::save_preferences,
            storage::save_cache,
            login::launch_at_login,
            login::set_launch_at_login,
            hide_popover,
            platform,
            set_tray,
            menu_bar_dark,
            celebrate,
            push_listen,
            push_configure,
            quit,
        ])
        .setup(move |app| {
            #[cfg(target_os = "macos")]
            app.set_activation_policy(tauri::ActivationPolicy::Accessory);
            #[cfg(windows)]
            if keep_launch_at_login {
                use tauri_plugin_autostart::ManagerExt;
                let _ = app.autolaunch().enable();
            }
            if smoke {
                println!("Stoke {} launch smoke test passed", app.package_info().version);
                std::process::exit(0);
            }
            let handle = app.handle().clone();
            popover(&handle).on_window_event(move |event| {
                if let WindowEvent::Focused(false) = event {
                    handle.state::<Mutex<Shell>>().lock().unwrap().hidden_at = Some(Instant::now());
                    let _ = popover(&handle).hide();
                }
            });
            build_tray(app.handle())?;
            // Timers live here, not in the web view: hidden pages may be throttled.
            let handle = app.handle().clone();
            std::thread::spawn(move || loop {
                std::thread::sleep(Duration::from_secs(30));
                let _ = handle.emit_to("popover", "tick", ());
            });
            Ok(())
        })
        .build(tauri::generate_context!())
        .expect("Stoke failed to start");
    app.run(|_, event| {
        // Hiding the flyout must never quit a tray app.
        if let RunEvent::ExitRequested { api, code: None, .. } = event {
            api.prevent_exit();
        }
    });
}
