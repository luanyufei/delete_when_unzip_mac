#!/bin/bash
set -e

echo "=========================================================="
echo " Building DeleteWhenUnzipMac for macOS (Pure Swift Native)"
echo "=========================================================="

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

SDK_PATH="$(xcrun --show-sdk-path)"
BUILD_DIR="$ROOT_DIR/.build"
MODULES_DIR="$BUILD_DIR/modules"
BIN_DIR="$BUILD_DIR/bin"
APP_DIR="$ROOT_DIR/DeleteWhenUnzipMac.app"

mkdir -p "$MODULES_DIR" "$BIN_DIR"

BREW_PREFIX="$(brew --prefix libarchive 2>/dev/null || echo '/opt/homebrew/opt/libarchive')"

echo "📦 1. Compiling DeleteWhenUnzipCore dynamic library..."
xcrun swiftc -sdk "$SDK_PATH" \
  -emit-module \
  -module-name DeleteWhenUnzipCore \
  -emit-module-path "$MODULES_DIR" \
  -I "$ROOT_DIR/Sources/Clibarchive" \
  -I "$BREW_PREFIX/include" \
  -L "$BREW_PREFIX/lib" \
  -larchive \
  -emit-library \
  -o "$MODULES_DIR/libDeleteWhenUnzipCore.dylib" \
  "$ROOT_DIR"/Sources/DeleteWhenUnzipCore/Models/*.swift \
  "$ROOT_DIR"/Sources/DeleteWhenUnzipCore/IO/*.swift \
  "$ROOT_DIR"/Sources/DeleteWhenUnzipCore/Scanning/*.swift \
  "$ROOT_DIR"/Sources/DeleteWhenUnzipCore/Extractor/*.swift \
  "$ROOT_DIR"/Sources/DeleteWhenUnzipCore/Engine/*.swift

echo "⚡️ 2. Compiling dwum CLI executable..."
xcrun swiftc -sdk "$SDK_PATH" \
  -parse-as-library \
  -I "$MODULES_DIR" \
  -I "$ROOT_DIR/Sources/Clibarchive" \
  -L "$MODULES_DIR" \
  -lDeleteWhenUnzipCore \
  -I "$BREW_PREFIX/include" \
  -L "$BREW_PREFIX/lib" \
  -larchive \
  -Xlinker -rpath -Xlinker "@executable_path/../modules" \
  -Xlinker -rpath -Xlinker "$BREW_PREFIX/lib" \
  -Xlinker -rpath -Xlinker "/usr/local/lib" \
  "$ROOT_DIR/Sources/DeleteWhenUnzipCLI/main.swift" \
  -o "$BIN_DIR/dwum"

echo "🖥️ 3. Compiling DeleteWhenUnzipMac GUI executable..."
xcrun swiftc -sdk "$SDK_PATH" \
  -parse-as-library \
  -I "$MODULES_DIR" \
  -I "$ROOT_DIR/Sources/Clibarchive" \
  -L "$MODULES_DIR" \
  -lDeleteWhenUnzipCore \
  -I "$BREW_PREFIX/include" \
  -L "$BREW_PREFIX/lib" \
  -larchive \
  -Xlinker -rpath -Xlinker "@executable_path/../Frameworks" \
  -Xlinker -rpath -Xlinker "@executable_path/../modules" \
  -Xlinker -rpath -Xlinker "$BREW_PREFIX/lib" \
  "$ROOT_DIR"/Sources/DeleteWhenUnzipApp/*.swift \
  "$ROOT_DIR"/Sources/DeleteWhenUnzipApp/UI/*.swift \
  -o "$BIN_DIR/DeleteWhenUnzipMac"

echo "🎨 4. Packaging DeleteWhenUnzipMac.app bundle into project root..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Frameworks"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BIN_DIR/DeleteWhenUnzipMac" "$APP_DIR/Contents/MacOS/"
cp "$MODULES_DIR/libDeleteWhenUnzipCore.dylib" "$APP_DIR/Contents/Frameworks/"
cp "$ROOT_DIR/Info.plist" "$APP_DIR/Contents/"

if [ -f "$ROOT_DIR/AppIcon.icns" ]; then
    cp "$ROOT_DIR/AppIcon.icns" "$APP_DIR/Contents/Resources/"
fi

echo "APPL????" > "$APP_DIR/Contents/PkgInfo"

# Ad-hoc 代码签名
codesign --force --deep --sign - "$APP_DIR" 2>/dev/null || true

echo "=========================================================="
echo "✅ Build & Package Succeeded!"
echo "📍 macOS App Bundle: $APP_DIR"
echo "📍 CLI Binary:       $BIN_DIR/dwum"
echo "=========================================================="
