#
# ELKFileSaver Makefile
# 使用 xcrun clang (Xcode Command Line Tools) 编译 dylib
#
# 用法: make            → 编译 dylib
#       make clean      → 清理产物
#

TARGET     = ELKFileSaver.dylib
SOURCES    = entry.m ELKMenuHook.m ELKFileExporter.m ELKRuntimeHelper.m
ARCH       = arm64
IOS_MIN    = 13.0

SDK        = $(shell xcrun --sdk iphoneos --show-sdk-path)
CC         = $(shell xcrun --sdk iphoneos -f clang)

CFLAGS     = -arch $(ARCH) \
             -isysroot $(SDK) \
             -miphoneos-version-min=$(IOS_MIN) \
             -dynamiclib \
             -fobjc-arc \
             -O2 \
             -Wall \
             -Wextra \
             -Wno-unused-parameter \
             -DMY_VERSION=\"$(VER)\"

LDFLAGS    = -framework Foundation \
             -framework UIKit \
             -framework UniformTypeIdentifiers \
             -framework QuickLook \
             -lobjc

.PHONY: all clean

all: $(TARGET)

$(TARGET): $(SOURCES)
	@echo "🔨 编译 $(TARGET)..."
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^
	@echo "✅ 编译完成: $(TARGET)"
	@xcrun lipo -info $@
	@ls -lh $@

clean:
	rm -f $(TARGET)
	@echo "🧹 已清理"
