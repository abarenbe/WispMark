use tauri::{AppHandle, Emitter, Manager};
use tauri_plugin_global_shortcut::{GlobalShortcutExt, Code, Modifiers, Shortcut};

/// Register global hotkeys for the application
/// - Ctrl+Shift+M: Toggle window visibility
/// - Ctrl+Alt+I: Inject selected text
pub fn register_hotkeys(app: &AppHandle) -> Result<(), Box<dyn std::error::Error>> {
    // Toggle window with Ctrl+Shift+M
    let toggle_shortcut = Shortcut::new(Some(Modifiers::CONTROL | Modifiers::SHIFT), Code::KeyM);
    let app_handle = app.clone();

    app.global_shortcut().on_shortcut(toggle_shortcut, move |_app, _shortcut, _event| {
        if let Some(window) = app_handle.get_webview_window("main") {
            match window.is_visible() {
                Ok(true) => {
                    let _ = window.hide();
                }
                Ok(false) => {
                    let _ = window.show();
                    let _ = window.set_focus();
                }
                Err(e) => eprintln!("Error checking window visibility: {}", e),
            }
        }
    })?;

    // Inject text with Ctrl+Alt+I
    let inject_shortcut = Shortcut::new(Some(Modifiers::CONTROL | Modifiers::ALT), Code::KeyI);
    let app_handle = app.clone();

    app.global_shortcut().on_shortcut(inject_shortcut, move |_app, _shortcut, _event| {
        // Emit event to frontend to get selected note content
        if let Some(window) = app_handle.get_webview_window("main") {
            let _ = window.emit("inject-text-requested", ());
        }
    })?;

    Ok(())
}

/// Unregister all global hotkeys
#[allow(dead_code)]
pub fn unregister_hotkeys(app: &AppHandle) -> Result<(), Box<dyn std::error::Error>> {
    let toggle_shortcut = Shortcut::new(Some(Modifiers::CONTROL | Modifiers::SHIFT), Code::KeyM);
    let inject_shortcut = Shortcut::new(Some(Modifiers::CONTROL | Modifiers::ALT), Code::KeyI);

    app.global_shortcut().unregister(toggle_shortcut)?;
    app.global_shortcut().unregister(inject_shortcut)?;
    Ok(())
}

#[tauri::command]
pub fn register_custom_hotkey(
    _app: AppHandle,
    _shortcut: String,
    _action: String,
) -> Result<(), String> {
    // This allows the frontend to register custom hotkeys if needed
    // For now, we just return an error as custom hotkeys aren't implemented
    Err("Custom hotkeys not yet implemented".to_string())
}
