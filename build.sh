#!/bin/bash
#
# ELKFileSaver 完整构建脚本
# 在 GitHub Actions (macos-15) 上运行
#
# 流程:
#   1. 编译 insert_dylib 工具
#   2. 编译 ELKFileSaver.dylib
#   3. 解压原始 IPA
#   4. 注入 dylib 到 wework 二进制
#   5. 重签所有文件
#   6. 打包新 IPA
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORK_DIR="$SCRIPT_DIR/build_workspace"
IPA_IN_DIR="$SCRIPT_DIR/ipa"
DYLIBSRC_DIR="$SCRIPT_DIR/dylib"
OUTPUT_IPA="$SCRIPT_DIR/eLink_FileSaver.ipa"

echo "╔══════════════════════════════════════════╗"
echo "║  ELKFileSaver Builder v1.0              ║"
echo "╚══════════════════════════════════════════╝"

# ── 0. 检查原始 IPA ──
echo ""
echo "📦 Step 0: 查找原始 IPA..."
ORIG_IPA=$(ls "$IPA_IN_DIR"/*.ipa 2>/dev/null | head -1)
if [ -z "$ORIG_IPA" ]; then
    echo "❌ 未找到 IPA 文件！请将 .ipa 放入 ipa/ 目录。"
    ls -la "$IPA_IN_DIR/" 2>/dev/null || echo "(ipa/ 目录为空)"
    exit 1
fi
echo "   原始 IPA: $ORIG_IPA"

# ── 1. 编译 insert_dylib ──
echo ""
echo "🔧 Step 1: 编译 insert_dylib..."
INSERT_DYLIB="$SCRIPT_DIR/insert_dylib"
if [ -f "$INSERT_DYLIB" ]; then
    echo "   insert_dylib 已存在，跳过编译。"
else
    INS_SRC="$SCRIPT_DIR/tools/insert_dylib"
    if [ ! -d "$INS_SRC" ]; then
        echo "   克隆 insert_dylib 源码..."
        git clone --depth 1 https://github.com/Tyilo/insert_dylib.git "$INS_SRC"
    fi
    cd "$INS_SRC"
    xcodebuild -project insert_dylib.xcodeproj \
               -target insert_dylib \
               -configuration Release \
               SYMROOT=build \
               -quiet 2>&1 | tail -5
    cp build/Release/insert_dylib "$INSERT_DYLIB"
    cd "$SCRIPT_DIR"
    echo "   ✅ insert_dylib 编译完成"
fi

# ── 2. 编译 dylib ──
echo ""
echo "🔨 Step 2: 编译 ELKFileSaver.dylib..."
cd "$DYLIBSRC_DIR"
make clean >/dev/null 2>&1 || true
make
DYLIB_PATH="$DYLIBSRC_DIR/ELKFileSaver.dylib"
if [ ! -f "$DYLIB_PATH" ]; then
    echo "❌ dylib 编译失败！"
    exit 1
fi
cd "$SCRIPT_DIR"
cp "$DYLIB_PATH" "$SCRIPT_DIR/"

# ── 3. 解压 IPA ──
echo ""
echo "📂 Step 3: 解压 IPA..."
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
unzip -oqq "$ORIG_IPA" -d "$WORK_DIR"

APP_DIR=$(find "$WORK_DIR/Payload" -name "*.app" -type d | head -1)
if [ -z "$APP_DIR" ]; then
    echo "❌ 未找到 .app 目录！"
    exit 1
fi
APP_NAME=$(basename "$APP_DIR")
BIN_NAME=$(basename "$APP_DIR" .app)
echo "   App: $APP_NAME"
echo "   主二进制: $BIN_NAME"

# ── 4. 复制 dylib 到 app bundle ──
echo ""
echo "📋 Step 4: 复制 dylib..."
cp "$DYLIB_PATH" "$APP_DIR/"
echo "   ✅ 已复制到 $APP_NAME/"

# ── 5. 注入 dylib ──
echo ""
echo "💉 Step 5: 注入 load command..."
BIN_PATH="$APP_DIR/$BIN_NAME"
chmod +w "$BIN_PATH"

echo "   正在注入..."
"$INSERT_DYLIB" "@executable_path/ELKFileSaver.dylib" "$BIN_PATH" --all-yes --inplace --weak
echo "   ✅ 已注入 LC_LOAD_DYLIB"

# ── 6. 重签 ──
echo ""
echo "✍️ Step 6: 重签 (ad-hoc)..."
SIGN="codesign -f -s -"

# 6a. 签 dylib
$SIGN "$APP_DIR/ELKFileSaver.dylib" 2>&1 || echo "   (dylib 签名警告，可忽略)"

# 6b. 签 Frameworks
if [ -d "$APP_DIR/Frameworks" ]; then
    for FW in "$APP_DIR/Frameworks"/*.framework; do
        FW_NAME=$(basename "$FW" .framework)
        FW_BIN="$FW/$FW_NAME"
        if [ -f "$FW_BIN" ]; then
            $SIGN "$FW_BIN" 2>&1 || true
        fi
    done
    echo "   ✅ Frameworks"
fi

# 6c. 签 PlugIns (Extensions)
if [ -d "$APP_DIR/PlugIns" ]; then
    for PLUGIN in "$APP_DIR/PlugIns"/*.appex; do
        PLUGIN_NAME=$(basename "$PLUGIN" .appex)
        PLUGIN_BIN="$PLUGIN/$PLUGIN_NAME"
        if [ -f "$PLUGIN_BIN" ]; then
            $SIGN "$PLUGIN_BIN" 2>&1 || true
        fi
    done
    echo "   ✅ PlugIns"
fi

# 6d. 签主二进制（最后签）
$SIGN "$BIN_PATH" 2>&1
echo "   ✅ 主二进制"

# ── 7. 打包 IPA ──
echo ""
echo "📦 Step 7: 打包..."
rm -f "$OUTPUT_IPA"
cd "$WORK_DIR"
zip -qr "$OUTPUT_IPA" Payload/
cd "$SCRIPT_DIR"
echo "   ✅ 打包完成"

# ── 8. 清理 ──
echo ""
echo "🧹 Step 8: 清理临时文件..."
rm -rf "$WORK_DIR"

# ── 完成 ──
echo ""
echo "╔══════════════════════════════════════════╗"
echo "║  ✅ 构建完成！                          ║"
echo "║  输出: eLink_FileSaver.ipa             ║"
echo "╚══════════════════════════════════════════╝"
ls -lh "$OUTPUT_IPA"
