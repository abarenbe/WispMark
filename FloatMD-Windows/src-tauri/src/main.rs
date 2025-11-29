// Prevents additional console window on Windows in release mode
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use tauri::{Manager, AppHandle};
use tauri::menu::{Menu, MenuItem};
use tauri::tray::{TrayIconBuilder, TrayIconEvent};

mod storage;
mod hotkeys;
mod injection;

use storage::{get_notes, save_notes_command, create_note, update_note, delete_note, get_storage_location};
use hotkeys::{register_hotkeys, register_custom_hotkey};
use injection::{inject_text_command, get_clipboard_text};

/// Create system tray menu
fn create_tray_menu(app: &AppHandle) -> Result<(), Box<dyn std::error::Error>> {
    let toggle_item = MenuItem::with_id(app, "toggle", "Show/Hide", true, None::<&str>)?;
    let new_note_item = MenuItem::with_id(app, "new_note", "New Note", true, None::<&str>)?;
    let separator = tauri::menu::PredefinedMenuItem::separator(app)?;
    let quit_item = MenuItem::with_id(app, "quit", "Quit", true, None::<&str>)?;

    let menu = Menu::with_items(app, &[
        &new_note_item,
        &toggle_item,
        &separator,
        &quit_item,
    ])?;

    let _tray = TrayIconBuilder::new()
        .menu(&menu)
        .icon(app.default_window_icon().unwrap().clone())
        .on_menu_event(|app, event| {
            match event.id().as_ref() {
                "toggle" => {
                    if let Some(window) = app.get_webview_window("main") {
                        match window.is_visible() {
                            Ok(true) => {
                                let _ = window.hide();
                            }
                            Ok(false) => {
                                let _ = window.show();
                                let _ = window.set_focus();
                            }
                            Err(e) => eprintln!("Error checking visibility: {}", e),
                        }
                    }
                }
                "new_note" => {
                    if let Some(window) = app.get_webview_window("main") {
                        let _ = window.show();
                        let _ = window.set_focus();
                        // Emit event to frontend to create new note
                        let _ = window.emit("create-new-note", ());
                    }
                }
                "quit" => {
                    std::process::exit(0);
                }
                _ => {}
            }
        })
        .on_tray_icon_event(|tray, event| {
            if let TrayIconEvent::Click { button, .. } = event {
                if button == tauri::tray::MouseButton::Left {
                    if let Some(app) = tray.app_handle().get_webview_window("main") {
                        match app.is_visible() {
                            Ok(true) => {
                                let _ = app.hide();
                            }
                            Ok(false) => {
                                let _ = app.show();
                                let _ = app.set_focus();
                            }
                            Err(e) => eprintln!("Error toggling visibility: {}", e),
                        }
                    }
                }
            }
        })
        .build(app)?;

    Ok(())
}

fn main() {
    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_global_shortcut::Builder::new().build())
        .setup(|app| {
            // Create system tray
            if let Err(e) = create_tray_menu(&app.handle()) {
                eprintln!("Failed to create tray menu: {}", e);
            }

            // Register global hotkeys
            if let Err(e) = register_hotkeys(&app.handle()) {
                eprintln!("Failed to register hotkeys: {}", e);
            }

            // Show main window
            if let Some(window) = app.get_webview_window("main") {
                let _ = window.show();
            }

            Ok(())
        })
        .on_window_event(|window, event| {
            match event {
                tauri::WindowEvent::CloseRequested { api, .. } => {
                    // Prevent window from closing, hide it instead
                    window.hide().unwrap();
                    api.prevent_close();
                }
                _ => {}
            }
        })
        .invoke_handler(tauri::generate_handler![
            // Storage commands
            get_notes,
            save_notes_command,
            create_note,
            update_note,
            delete_note,
            get_storage_location,
            // Injection commands
            inject_text_command,
            get_clipboard_text,
            // Hotkey commands
            register_custom_hotkey,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
