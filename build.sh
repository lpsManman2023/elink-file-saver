#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DYLIBSRC_DIR="$SCRIPT_DIR/dylib"
OUTPUT_DIR="$SCRIPT_DIR/output"

# ── 读取版本号 ──
VER=$(cat "$SCRIPT_DIR/VERSION" 2>/dev/null | tr -d '[:space:]')
if [ -z "$VER" ]; then VER="0"; fi

DYLIB_NAME="ELKFileSaver_v${VER}.dylib"

echo "╔══════════════════════════════════════════╗"
echo "║  ELKFileSaver v${VER} - 喵喵插件        ║"
echo "╚══════════════════════════════════════════╝"

echo ""
echo "🔨 编译 ${DYLIB_NAME}..."
cd "$DYLIBSRC_DIR"
make clean >/dev/null 2>&1 || true
make VER="$VER"
DYLIB_PATH="$DYLIBSRC_DIR/ELKFileSaver.dylib"
if [ ! -f "$DYLIB_PATH" ]; then
    echo "❌ dylib 编译失败！"
    exit 1
fi

mkdir -p "$OUTPUT_DIR"
cp "$DYLIB_PATH" "$OUTPUT_DIR/${DYLIB_NAME}"
cd "$SCRIPT_DIR"

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║  ✅ 编译完成                            ║"
echo "║  output/${DYLIB_NAME}                   ║"
echo "╚══════════════════════════════════════════╝"
ls -lh "$OUTPUT_DIR/${DYLIB_NAME}"
