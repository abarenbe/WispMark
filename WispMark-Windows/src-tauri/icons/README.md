# WispMark Icons

Place the following icon files in this directory:

- `32x32.png` - 32x32 pixel PNG
- `128x128.png` - 128x128 pixel PNG
- `128x128@2x.png` - 256x256 pixel PNG (2x retina)
- `icon.icns` - macOS icon bundle (not needed for Windows, but keep for cross-platform)
- `icon.ico` - Windows icon file (required for Windows build)

## Generating Icons

You can use the WispMark logo (`logo_wispmark.png` in the project root) to generate these icons.

### Using ImageMagick:
```bash
# Install ImageMagick first
# Windows: choco install imagemagick
# macOS: brew install imagemagick

# Generate PNG icons
magick logo_wispmark.png -resize 32x32 32x32.png
magick logo_wispmark.png -resize 128x128 128x128.png
magick logo_wispmark.png -resize 256x256 128x128@2x.png

# Generate ICO (Windows)
magick logo_wispmark.png -define icon:auto-resize=256,128,64,48,32,16 icon.ico
```

### Online Tools:
- https://www.icoconverter.com/ - Convert PNG to ICO
- https://iconverticons.com/ - Multi-format icon converter

## Notes
- The tray icon uses `icon.ico` on Windows
- The application icon uses `icon.ico` for the window and taskbar
- For best results, use a square source image with transparent background
