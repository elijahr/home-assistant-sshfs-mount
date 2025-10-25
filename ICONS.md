# Icon Files

This add-on uses the following icon files:

- `icon.png` - 96x96 pixels, displayed in the Home Assistant add-on store
- `logo.png` - 256x256 pixels (optional), displayed in the repository listing

## Current Icons

The repository includes SVG source files (`icon.svg` and `logo.svg`) that represent:
- A folder (representing the mount point)
- SSH connection lines
- An arrow indicating the mounting/connection action

## Converting SVG to PNG

To generate the PNG files from the SVG sources:

### Using ImageMagick (recommended)

```bash
# Install ImageMagick if not already installed
# macOS: brew install imagemagick
# Ubuntu/Debian: sudo apt install imagemagick
# Windows: download from https://imagemagick.org

# Convert icon (ImageMagick v7)
magick icon.svg -resize 96x96 icon.png

# Convert logo (ImageMagick v7)
magick logo.svg -resize 256x256 logo.png

# For ImageMagick v6, use 'convert' instead:
# convert -background none icon.svg -resize 96x96 icon.png
# convert -background none logo.svg -resize 256x256 logo.png
```

### Using Inkscape

```bash
# Install Inkscape if not already installed
# macOS: brew install inkscape
# Ubuntu/Debian: sudo apt install inkscape

# Convert icon
inkscape icon.svg --export-type=png --export-width=96 --export-height=96 --export-filename=icon.png

# Convert logo
inkscape logo.svg --export-type=png --export-width=256 --export-height=256 --export-filename=logo.png
```

### Using Online Tools

1. Go to https://cloudconvert.com/svg-to-png
2. Upload `icon.svg`
3. Set width to 96px and height to 96px
4. Convert and download as `icon.png`
5. Repeat for `logo.svg` at 256x256px

## Customizing Icons

Feel free to customize the icon files! Requirements:

- **icon.png**: Must be exactly 96x96 pixels
- **logo.png**: Recommended 256x256 pixels (optional)
- Format: PNG with transparency preferred
- Design: Should represent the add-on's purpose (SSH mounting + Samba sharing)

After customizing, make sure to:
1. Keep the SVG source files updated
2. Generate new PNG files
3. Test how they look in the Home Assistant UI
