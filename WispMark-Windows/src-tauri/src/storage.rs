use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;
use uuid::Uuid;
use chrono::{DateTime, Utc};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Note {
    pub id: Uuid,
    pub content: String,
    pub created_at: DateTime<Utc>,
    pub modified_at: DateTime<Utc>,
    pub is_pinned: bool,
}

impl Note {
    pub fn new() -> Self {
        let now = Utc::now();
        Note {
            id: Uuid::new_v4(),
            content: String::new(),
            created_at: now,
            modified_at: now,
            is_pinned: false,
        }
    }
}

impl Default for Note {
    fn default() -> Self {
        Self::new()
    }
}

/// Determines the storage path for notes.json
/// Priority:
/// 1. If .portable file exists next to executable, use data/ folder next to exe
/// 2. If data/ folder exists next to executable, use it (portable mode)
/// 3. Otherwise use system AppData folder
pub fn get_storage_path() -> Result<PathBuf, Box<dyn std::error::Error>> {
    // Get the directory where the executable is located
    let exe_path = std::env::current_exe()?;
    let exe_dir = exe_path.parent().ok_or("Could not determine exe directory")?;

    let portable_marker = exe_dir.join(".portable");
    let data_dir = exe_dir.join("data");

    // Check for portable mode
    let storage_dir = if portable_marker.exists() || data_dir.exists() {
        // Portable mode - store data next to executable
        if !data_dir.exists() {
            fs::create_dir_all(&data_dir)?;
        }
        data_dir
    } else {
        // Standard mode - use AppData
        let app_data = dirs::data_dir()
            .ok_or("Could not determine AppData directory")?
            .join("WispMark");

        if !app_data.exists() {
            fs::create_dir_all(&app_data)?;
        }
        app_data
    };

    Ok(storage_dir.join("notes.json"))
}

/// Load notes from storage
pub fn load_notes() -> Result<Vec<Note>, Box<dyn std::error::Error>> {
    let path = get_storage_path()?;

    if !path.exists() {
        // Return empty vec if file doesn't exist yet
        return Ok(Vec::new());
    }

    let contents = fs::read_to_string(&path)?;
    let notes: Vec<Note> = serde_json::from_str(&contents)?;
    Ok(notes)
}

/// Save notes to storage
pub fn save_notes(notes: &[Note]) -> Result<(), Box<dyn std::error::Error>> {
    let path = get_storage_path()?;

    // Ensure parent directory exists
    if let Some(parent) = path.parent() {
        if !parent.exists() {
            fs::create_dir_all(parent)?;
        }
    }

    let json = serde_json::to_string_pretty(notes)?;
    fs::write(&path, json)?;
    Ok(())
}

// Tauri commands for frontend communication

#[tauri::command]
pub fn get_notes() -> Result<Vec<Note>, String> {
    load_notes().map_err(|e| e.to_string())
}

#[tauri::command]
pub fn save_notes_command(notes: Vec<Note>) -> Result<(), String> {
    save_notes(&notes).map_err(|e| e.to_string())
}

#[tauri::command]
pub fn create_note() -> Result<Note, String> {
    Ok(Note::new())
}

#[tauri::command]
pub fn update_note(note: Note) -> Result<(), String> {
    let mut notes = load_notes().map_err(|e| e.to_string())?;

    if let Some(existing) = notes.iter_mut().find(|n| n.id == note.id) {
        *existing = note;
        save_notes(&notes).map_err(|e| e.to_string())?;
        Ok(())
    } else {
        Err("Note not found".to_string())
    }
}

#[tauri::command]
pub fn delete_note(id: String) -> Result<(), String> {
    let uuid = Uuid::parse_str(&id).map_err(|e| e.to_string())?;
    let mut notes = load_notes().map_err(|e| e.to_string())?;

    notes.retain(|n| n.id != uuid);
    save_notes(&notes).map_err(|e| e.to_string())?;
    Ok(())
}

#[tauri::command]
pub fn get_storage_location() -> Result<String, String> {
    get_storage_path()
        .map(|p| p.to_string_lossy().to_string())
        .map_err(|e| e.to_string())
}
