import { useState, useEffect } from 'react';
import { invoke } from '@tauri-apps/api/core';
import { Theme, themeNames } from '../themes';

interface SettingsProps {
  currentTheme: string;
  onThemeChange: (themeName: string) => void;
  onClose: () => void;
  theme: Theme;
}

interface AppSettings {
  theme: string;
  hotkey: string;
  stripTitles: boolean;
  stripTags: boolean;
  stripWikiLinks: boolean;
}

export const Settings: React.FC<SettingsProps> = ({
  currentTheme,
  onThemeChange,
  onClose,
  theme,
}) => {
  const [settings, setSettings] = useState<AppSettings>({
    theme: currentTheme,
    hotkey: 'Ctrl+Shift+Space',
    stripTitles: false,
    stripTags: false,
    stripWikiLinks: false,
  });

  useEffect(() => {
    loadSettings();
  }, []);

  const loadSettings = async () => {
    try {
      const loaded = await invoke<AppSettings>('load_settings');
      setSettings({ ...loaded, theme: currentTheme });
    } catch (error) {
      console.error('Failed to load settings:', error);
    }
  };

  const saveSettings = async (newSettings: AppSettings) => {
    try {
      await invoke('save_settings', { settings: newSettings });
      setSettings(newSettings);
    } catch (error) {
      console.error('Failed to save settings:', error);
    }
  };

  const handleThemeChange = (themeName: string) => {
    const newSettings = { ...settings, theme: themeName };
    saveSettings(newSettings);
    onThemeChange(themeName);
  };

  const handleToggle = (key: keyof AppSettings) => {
    const newSettings = {
      ...settings,
      [key]: !settings[key],
    };
    saveSettings(newSettings);
  };

  return (
    <div className="settings-overlay" onClick={onClose}>
      <div
        className="settings-panel"
        onClick={(e) => e.stopPropagation()}
        style={{
          backgroundColor: theme.background,
          borderColor: theme.border,
        }}
      >
        <div className="settings-header" style={{ borderBottomColor: theme.border }}>
          <h2 style={{ color: theme.text }}>Settings</h2>
          <button
            className="settings-close"
            onClick={onClose}
            style={{ color: theme.icon }}
          >
            ✕
          </button>
        </div>

        <div className="settings-content">
          <div className="settings-section">
            <h3 style={{ color: theme.text }}>Appearance</h3>
            <div className="settings-item">
              <label style={{ color: theme.text }}>Theme</label>
              <select
                value={settings.theme}
                onChange={(e) => handleThemeChange(e.target.value)}
                style={{
                  backgroundColor: theme.sidebarBackground,
                  color: theme.text,
                  borderColor: theme.border,
                }}
              >
                {themeNames.map((name) => (
                  <option key={name} value={name}>
                    {name}
                  </option>
                ))}
              </select>
            </div>
          </div>

          <div className="settings-section">
            <h3 style={{ color: theme.text }}>Keyboard Shortcut</h3>
            <div className="settings-item">
              <label style={{ color: theme.text }}>Toggle Window</label>
              <input
                type="text"
                value={settings.hotkey}
                readOnly
                style={{
                  backgroundColor: theme.sidebarBackground,
                  color: theme.secondaryText,
                  borderColor: theme.border,
                }}
                title="Hotkey configuration will be available in a future update"
              />
            </div>
            <p style={{ color: theme.secondaryText, fontSize: '12px', marginTop: '8px' }}>
              Default: Ctrl+Shift+Space (customization coming soon)
            </p>
          </div>

          <div className="settings-section">
            <h3 style={{ color: theme.text }}>Text Injection</h3>
            <p style={{ color: theme.secondaryText, fontSize: '13px', marginBottom: '12px' }}>
              When pasting note content elsewhere, automatically remove:
            </p>

            <div className="settings-item-checkbox">
              <label style={{ color: theme.text }}>
                <input
                  type="checkbox"
                  checked={settings.stripTitles}
                  onChange={() => handleToggle('stripTitles')}
                />
                <span>Strip title lines (# Heading)</span>
              </label>
            </div>

            <div className="settings-item-checkbox">
              <label style={{ color: theme.text }}>
                <input
                  type="checkbox"
                  checked={settings.stripTags}
                  onChange={() => handleToggle('stripTags')}
                />
                <span>Strip tags (#tag)</span>
              </label>
            </div>

            <div className="settings-item-checkbox">
              <label style={{ color: theme.text }}>
                <input
                  type="checkbox"
                  checked={settings.stripWikiLinks}
                  onChange={() => handleToggle('stripWikiLinks')}
                />
                <span>Strip wiki links ([[Note Title]])</span>
              </label>
            </div>
          </div>
        </div>

        <div className="settings-footer" style={{ borderTopColor: theme.border }}>
          <button
            className="settings-done-button"
            onClick={onClose}
            style={{
              backgroundColor: theme.link,
              color: theme.background,
            }}
          >
            Done
          </button>
        </div>
      </div>
    </div>
  );
};
