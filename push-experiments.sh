#!/bin/bash
# Insulation 性能实验版本推送脚本

set -e

# 检查是否提供了远程仓库地址
if [ -z "$1" ]; then
    echo "用法: $0 <远程仓库地址>"
    echo "例如: $0 https://github.com/username/insulation.git"
    exit 1
fi

REMOTE_URL="$1"

echo "=== 添加远程仓库 ==="
git remote remove experiment 2>/dev/null || true
git remote add experiment "$REMOTE_URL"

echo ""
echo "=== 推送实验分支 ==="
for branch in exp-a-no-boot-guard exp-b-reduce-calls exp-c-aggressive-pressure; do
    echo ""
    echo "推送 $branch ..."
    git push -f experiment $branch
done

echo ""
echo "=== 推送完成 ==="
echo ""
echo "请在 GitHub 仓库设置 Actions 工作流："
echo "1. 访问: ${REMOTE_URL%.git}/settings/actions"
echo "2. 启用 GitHub Actions"
echo "3. 添加 Secrets（如果需要）"
echo ""
echo "然后访问 Actions 页面触发构建："
echo "${REMOTE_URL%.git}/actions"
echo ""
echo "实验版本："
echo "  - exp-a-no-boot-guard  → 0.1.36-expA (禁用 boot guard)"
echo "  - exp-b-reduce-calls   → 0.1.36-expB (减少后台调用)"
echo "  - exp-c-aggressive-pressure → 0.1.36-expC (激进 pressure)"
