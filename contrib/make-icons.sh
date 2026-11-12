#!/usr/bin/env bash
# Regenerate the app launcher icons (Android + macOS) from the SVG sources in
# contrib/icons/. Requires ImageMagick (`brew install imagemagick`).
#
#   contrib/icons/app_icon.svg            full icon: rounded square + glasses glyph
#   contrib/icons/app_icon_foreground.svg transparent glyph for the Android
#                                         adaptive icon (inside the 66dp safe zone)
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
ICON_DIR="$ROOT/contrib/icons"
ANDROID_RES="$ROOT/android/app/src/main/res"
MACOS_SET="$ROOT/macos/Runner/Assets.xcassets/AppIcon.appiconset"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

render() { # <svg> <size> <out>
  magick -background none -density 96 "$1" -resize "${2}x${2}" \
    -colorspace sRGB -depth 8 -strip "$3"
}

# --- master --------------------------------------------------------------
render "$ICON_DIR/app_icon.svg" 1024 "$TMP/icon_1024.png"

# --- macOS (rounded square included in the SVG) --------------------------
for size in 16 32 64 128 256 512; do
  magick "$TMP/icon_1024.png" -resize "${size}x${size}" -depth 8 -strip \
    "$MACOS_SET/app_icon_${size}.png"
done
cp "$TMP/icon_1024.png" "$MACOS_SET/app_icon_1024.png"

# --- Android legacy launcher icons --------------------------------------
for density_size in mdpi:48 hdpi:72 xhdpi:96 xxhdpi:144 xxxhdpi:192; do
  density=${density_size%%:*}
  size=${density_size##*:}
  magick "$TMP/icon_1024.png" -resize "${size}x${size}" -depth 8 -strip \
    "$ANDROID_RES/mipmap-$density/ic_launcher.png"
done

# --- Android adaptive icon (API 26+) ------------------------------------
# Foreground is 108dp with the glyph kept inside the 66dp safe zone.
# The monochrome variant (Android 13+ themed icons) is the same glyph in white.
for density_size in mdpi:108 hdpi:162 xhdpi:216 xxhdpi:324 xxxhdpi:432; do
  density=${density_size%%:*}
  size=${density_size##*:}
  render "$ICON_DIR/app_icon_foreground.svg" "$size" \
    "$ANDROID_RES/mipmap-$density/ic_launcher_foreground.png"
  magick "$ANDROID_RES/mipmap-$density/ic_launcher_foreground.png" \
    -fill white -colorize 100 -depth 8 -strip \
    "$ANDROID_RES/mipmap-$density/ic_launcher_monochrome.png"
done

mkdir -p "$ANDROID_RES/mipmap-anydpi-v26"
cat > "$ANDROID_RES/mipmap-anydpi-v26/ic_launcher.xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
    <monochrome android:drawable="@mipmap/ic_launcher_monochrome" />
</adaptive-icon>
XML

mkdir -p "$ANDROID_RES/values"
cat > "$ANDROID_RES/values/ic_launcher_background.xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#141418</color>
</resources>
XML

echo "Icons written to:"
echo "  $ANDROID_RES"
echo "  $MACOS_SET"
