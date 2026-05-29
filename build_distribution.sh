#!/bin/sh
set -eu

VERSION="${VERSION:-2.8}"
APP_BUNDLE_NAME="HBCSD Classroom Display Tool.app"
EXECUTABLE_NAME="HBCSD Classroom Display Tool"
IDENTIFIER="org.hbcsd.classroom-display-tool"
MIN_MACOS_VERSION="12.0"
export COPYFILE_DISABLE=1
export COPY_EXTENDED_ATTRIBUTES_DISABLE=1
export DITTONORSRC=1

SCRIPT_DIR="$(CDPATH= cd "$(dirname "$0")" && pwd -P)"
DIST_DIR="$SCRIPT_DIR/dist"
BUILD_DIR="${TMPDIR:-/tmp}/hbcsd-classroom-display-build.$$"
STAGING_DIR="$BUILD_DIR/staging"
PKG_ROOT="$BUILD_DIR/pkg-root"
PKG_SCRIPTS="$BUILD_DIR/pkg-scripts"
PRODUCTS_DIR="$BUILD_DIR/products"
SWIFT_SOURCE="$SCRIPT_DIR/Sources/ClassroomDisplayToolApp/main.swift"
BACKEND_SCRIPT="$SCRIPT_DIR/Sources/ClassroomDisplayToolApp/Resources/display_backend.sh"
ICON_SOURCE="$SCRIPT_DIR/assets/macdisplayutilityapp.png"

cleanup() {
  rm -rf "$BUILD_DIR"
}
trap cleanup 0 1 2 15

require_tool() {
  tool="$1"
  if ! command -v "$tool" >/dev/null 2>&1; then
    printf 'Missing required build tool: %s\n' "$tool" >&2
    exit 1
  fi
}

strip_metadata() {
  target="$1"
  find "$target" -name '._*' -delete
  xattr -cr "$target" >/dev/null 2>&1 || true
}

clean_package_metadata() {
  pkg_path="$1"
  expanded_pkg="$BUILD_DIR/expanded-pkg"
  cleaned_pkg="$BUILD_DIR/cleaned.pkg"

  rm -rf "$expanded_pkg" "$cleaned_pkg"
  pkgutil --expand "$pkg_path" "$expanded_pkg"
  find "$expanded_pkg" -name '._*' -delete
  pkgutil --flatten "$expanded_pkg" "$cleaned_pkg"
  mv "$cleaned_pkg" "$pkg_path"
}

build_universal_executable() {
  mkdir -p "$PRODUCTS_DIR"

  swiftc \
    -O \
    -target "arm64-apple-macosx$MIN_MACOS_VERSION" \
    "$SWIFT_SOURCE" \
    -o "$PRODUCTS_DIR/display-tool-arm64"

  swiftc \
    -O \
    -target "x86_64-apple-macosx$MIN_MACOS_VERSION" \
    "$SWIFT_SOURCE" \
    -o "$PRODUCTS_DIR/display-tool-x86_64"

  lipo \
    -create "$PRODUCTS_DIR/display-tool-arm64" "$PRODUCTS_DIR/display-tool-x86_64" \
    -output "$PRODUCTS_DIR/$EXECUTABLE_NAME"
}

write_info_plist() {
  app_bundle="$1"

  cat > "$app_bundle/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>$EXECUTABLE_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$IDENTIFIER</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon.icns</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>HBCSD Classroom Display Tool</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$VERSION</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_MACOS_VERSION</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
EOF
}

make_app_icon() {
  resources_dir="$1"
  iconset_dir="$BUILD_DIR/AppIcon.iconset"

  mkdir -p "$iconset_dir"

  sips -z 16 16 "$ICON_SOURCE" --out "$iconset_dir/icon_16x16.png" >/dev/null
  sips -z 32 32 "$ICON_SOURCE" --out "$iconset_dir/icon_16x16@2x.png" >/dev/null
  sips -z 32 32 "$ICON_SOURCE" --out "$iconset_dir/icon_32x32.png" >/dev/null
  sips -z 64 64 "$ICON_SOURCE" --out "$iconset_dir/icon_32x32@2x.png" >/dev/null
  sips -z 128 128 "$ICON_SOURCE" --out "$iconset_dir/icon_128x128.png" >/dev/null
  sips -z 256 256 "$ICON_SOURCE" --out "$iconset_dir/icon_128x128@2x.png" >/dev/null
  sips -z 256 256 "$ICON_SOURCE" --out "$iconset_dir/icon_256x256.png" >/dev/null
  sips -z 512 512 "$ICON_SOURCE" --out "$iconset_dir/icon_256x256@2x.png" >/dev/null
  sips -z 512 512 "$ICON_SOURCE" --out "$iconset_dir/icon_512x512.png" >/dev/null
  sips -z 1024 1024 "$ICON_SOURCE" --out "$iconset_dir/icon_512x512@2x.png" >/dev/null

  iconutil -c icns "$iconset_dir" -o "$resources_dir/AppIcon.icns"
}

copy_runtime_assets() {
  resources_dir="$1"

  mkdir -p "$resources_dir/assets" "$resources_dir/bin"

  install -m 644 "$SCRIPT_DIR/THIRD_PARTY_NOTICES.md" "$resources_dir/THIRD_PARTY_NOTICES.md"
  install -m 755 "$BACKEND_SCRIPT" "$resources_dir/display_backend.sh"

  install -m 755 "$SCRIPT_DIR/bin/displayplacer-arm64" "$resources_dir/bin/displayplacer-arm64"
  install -m 755 "$SCRIPT_DIR/bin/displayplacer-x86_64" "$resources_dir/bin/displayplacer-x86_64"

  install -m 644 "$SCRIPT_DIR/assets/2-display-mirror-everything.png" "$resources_dir/assets/2-display-mirror-everything.png"
  install -m 644 "$SCRIPT_DIR/assets/2-display-teacher-private-mode.png" "$resources_dir/assets/2-display-teacher-private-mode.png"
  install -m 644 "$SCRIPT_DIR/assets/3-display-mirror-everything.png" "$resources_dir/assets/3-display-mirror-everything.png"
  install -m 644 "$SCRIPT_DIR/assets/3-display-teacher-private-mode.png" "$resources_dir/assets/3-display-teacher-private-mode.png"
  install -m 644 "$SCRIPT_DIR/assets/3-display-extend-all.png" "$resources_dir/assets/3-display-extend-all.png"
  install -m 644 "$SCRIPT_DIR/assets/macdisplayutilityapp.png" "$resources_dir/assets/macdisplayutilityapp.png"
}

create_app_bundle() {
  app_bundle="$1"
  contents_dir="$app_bundle/Contents"
  macos_dir="$contents_dir/MacOS"
  resources_dir="$contents_dir/Resources"

  rm -rf "$app_bundle"
  mkdir -p "$macos_dir" "$resources_dir"

  install -m 755 "$PRODUCTS_DIR/$EXECUTABLE_NAME" "$macos_dir/$EXECUTABLE_NAME"
  write_info_plist "$app_bundle"
  make_app_icon "$resources_dir"
  copy_runtime_assets "$resources_dir"

  strip_metadata "$app_bundle"
  codesign --force --sign - "$app_bundle" >/dev/null
}

require_tool swiftc
require_tool lipo
require_tool codesign
require_tool iconutil
require_tool pkgbuild
require_tool pkgutil
require_tool sips

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR" "$STAGING_DIR" "$PKG_ROOT/Applications" "$PKG_SCRIPTS"

build_universal_executable
create_app_bundle "$STAGING_DIR/$APP_BUNDLE_NAME"
create_app_bundle "$PKG_ROOT/Applications/$APP_BUNDLE_NAME"

cat > "$PKG_SCRIPTS/postinstall" <<'POSTINSTALL'
#!/bin/sh
set -eu

app_dir="/Applications/HBCSD Classroom Display Tool.app"
resources_dir="$app_dir/Contents/Resources"

chmod 755 "$app_dir/Contents/MacOS/HBCSD Classroom Display Tool" || true
chmod 755 "$resources_dir/display_backend.sh" || true
chmod 755 "$resources_dir/bin/displayplacer-arm64" || true
chmod 755 "$resources_dir/bin/displayplacer-x86_64" || true
xattr -dr com.apple.quarantine "$app_dir" >/dev/null 2>&1 || true

exit 0
POSTINSTALL
chmod 755 "$PKG_SCRIPTS/postinstall"

strip_metadata "$STAGING_DIR"
strip_metadata "$PKG_ROOT"
strip_metadata "$PKG_SCRIPTS"

(cd "$STAGING_DIR" && zip -X -r "$DIST_DIR/HBCSD-Classroom-Display-Tool.zip" "$APP_BUNDLE_NAME")

find "$PKG_ROOT" -name '._*' -delete

pkgbuild \
  --root "$PKG_ROOT" \
  --scripts "$PKG_SCRIPTS" \
  --filter '\.DS_Store$' \
  --filter '(^|/)\.svn($|/)' \
  --filter '(^|/)CVS($|/)' \
  --filter '(^|/)\._' \
  --identifier "$IDENTIFIER" \
  --version "$VERSION" \
  --install-location "/" \
  "$DIST_DIR/HBCSD-Classroom-Display-Tool-$VERSION.pkg"

clean_package_metadata "$DIST_DIR/HBCSD-Classroom-Display-Tool-$VERSION.pkg"

printf 'Built:\n'
printf '  %s\n' "$DIST_DIR/HBCSD-Classroom-Display-Tool.zip"
printf '  %s\n' "$DIST_DIR/HBCSD-Classroom-Display-Tool-$VERSION.pkg"
