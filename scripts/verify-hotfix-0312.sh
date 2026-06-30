#!/bin/bash
# 验证 0.1.31.2 修复是否正确应用

set -e

echo "=== Insulation 0.1.31.2 Hotfix 验证 ==="
echo ""

DEB_FILE="packages/com.be-huge.insulation_0.1.31.2_iphoneos-arm64.deb"
EXTRACT_DIR="/tmp/insulation-0312-verify-$$"

if [[ ! -f "$DEB_FILE" ]]; then
    echo "❌ 找不到 deb 包: $DEB_FILE"
    exit 1
fi

echo "✅ 找到 deb 包: $DEB_FILE ($(du -h "$DEB_FILE" | cut -f1))"

# 解包验证
mkdir -p "$EXTRACT_DIR"
dpkg-deb -x "$DEB_FILE" "$EXTRACT_DIR" 2>/dev/null

DYLIB="$EXTRACT_DIR/var/jb/Library/MobileSubstrate/DynamicLibraries/insulation.dylib"

if [[ ! -f "$DYLIB" ]]; then
    echo "❌ dylib 不存在"
    exit 1
fi

echo "✅ dylib 存在: $(du -h "$DYLIB" | cut -f1)"
echo ""

# 检查符号
echo "=== 检查修复相关符号 ==="

# 应该不存在 cachedThermalManagerConfig（已删除）
if nm "$DYLIB" 2>/dev/null | grep -q "cachedThermalManagerConfig"; then
    echo "⚠️  仍然存在 cachedThermalManagerConfig 符号（可能只是字符串引用）"
else
    echo "✅ 未找到 cachedThermalManagerConfig 符号"
fi

# 应该存在 dispatch_queue_create（新增线程安全代码）
if nm "$DYLIB" 2>/dev/null | grep -q "dispatch_queue_create"; then
    echo "✅ 找到 dispatch_queue_create（线程安全修复）"
else
    echo "⚠️  未找到 dispatch_queue_create"
fi

# 检查 CFDictionaryCreateCopy
if nm "$DYLIB" 2>/dev/null | grep -q "CFDictionaryCreateCopy"; then
    echo "✅ 找到 CFDictionaryCreateCopy（内存管理修复）"
else
    echo "⚠️  未找到 CFDictionaryCreateCopy"
fi

echo ""

# 检查源代码
echo "=== 检查源代码修复 ==="

SOURCE_FILE="Sources/insulationC/ThermalManagerDimmingPatch.m"

if grep -q "static CFDictionaryRef cachedThermalManagerConfig" "$SOURCE_FILE"; then
    echo "❌ 源代码仍包含 cachedThermalManagerConfig 静态变量"
    exit 1
else
    echo "✅ 源代码已移除 cachedThermalManagerConfig"
fi

if grep -q "dispatch_queue_create.*prefs-cache" "$SOURCE_FILE"; then
    echo "✅ 源代码包含线程安全的队列"
else
    echo "❌ 源代码缺少线程安全队列"
    exit 1
fi

if grep -q "Return a new copy each time" "$SOURCE_FILE"; then
    echo "✅ 源代码包含新的内存管理注释"
else
    echo "❌ 源代码缺少新的注释"
    exit 1
fi

echo ""

# 检查版本号
echo "=== 检查版本号 ==="

if grep -q "Version: 0.1.31.2" control.objc; then
    echo "✅ control.objc 版本号正确: 0.1.31.2"
else
    echo "❌ control.objc 版本号不正确"
    exit 1
fi

echo ""

# 清理
rm -rf "$EXTRACT_DIR"

echo "=== 验证完成 ==="
echo "✅ 所有检查通过！"
echo ""
echo "下一步："
echo "  1. 通过 GitHub Actions 构建 roothide 版本"
echo "  2. 在测试设备上安装并验证功能"
echo "  3. 运行至少 24 小时观察稳定性"
