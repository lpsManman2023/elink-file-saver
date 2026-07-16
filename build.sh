#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DYLIBSRC_DIR="$SCRIPT_DIR/dylib"
OUTPUT_DIR="$SCRIPT_DIR/output"

echo "╔══════════════════════════════════════════╗"
echo "║  ELKFileSaver - 仅编译 dylib            ║"
echo "╚══════════════════════════════════════════╝"

echo ""
echo "🔨 编译 ELKFileSaver.dylib..."
cd "$DYLIBSRC_DIR"
make clean >/dev/null 2>&1 || true
make
DYLIB_PATH="$DYLIBSRC_DIR/ELKFileSaver.dylib"
if [ ! -f "$DYLIB_PATH" ]; then
    echo "❌ dylib 编译失败！"
    exit 1
fi

mkdir -p "$OUTPUT_DIR"
cp "$DYLIB_PATH" "$OUTPUT_DIR/"
cd "$SCRIPT_DIR"

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║  ✅ 编译完成                            ║"
echo "║  output/ELKFileSaver.dylib             ║"
echo "╚══════════════════════════════════════════╝"
ls -lh "$OUTPUT_DIR/ELKFileSaver.dylib"
