#!/bin/bash
# 把 patches/ 下的 8 个 patch 应用到 ArkUI-X 源码树。
# 用法: scripts/apply_patches.sh /path/to/arkui-x
set -e
SRC="${1:?用法: $0 /path/to/arkui-x}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
PATCHES="$HERE/patches"
BRANCH="mac-port"

# 仓相对路径 : patch 名
MAP=(
  "build:build"
  "build_plugins:build_plugins"
  "foundation/graphic/graphic_2d:graphic_2d"
  "foundation/appframework:appframework"
  "foundation/arkui/ace_engine:ace_engine"
  "foundation/multimedia/image_framework:image_framework"
  "base/hiviewdfx/hilog:hilog"
  "commonlibrary/c_utils:c_utils"
  "third_party/skia:skia"
  "arkcompiler/ets_frontend:ets_frontend"
  "arkcompiler/runtime_core:runtime_core"
  "interface/sdk-js:sdk-js"
  "foundation/arkui/napi:napi"
  "foundation/multimodalinput/input:input"
)

for e in "${MAP[@]}"; do
  rel="${e%%:*}"; name="${e##*:}"
  repo="$SRC/$rel"; patch="$PATCHES/${name}.patch"
  echo "=== $rel ==="
  git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || { echo "  ✗ 非 git 仓: $repo"; exit 1; }
  [ -f "$patch" ] || { echo "  ✗ 缺 patch: $patch"; exit 1; }
  if [ -n "$(git -C "$repo" status --porcelain)" ]; then
    echo "  ⚠ 工作区不干净,跳过"; continue
  fi
  git -C "$repo" rev-parse --verify "$BRANCH" >/dev/null 2>&1 \
    && git -C "$repo" checkout "$BRANCH" \
    || git -C "$repo" checkout -b "$BRANCH"
  if git -C "$repo" apply --check "$patch" 2>/dev/null; then
    git -C "$repo" apply "$patch"; echo "  ✓ 已应用 ${name}.patch"
  else
    echo "  ⚠ 直接 apply 冲突,改 3-way:"; git -C "$repo" apply --3way "$patch" \
      || echo "  ✗ 仍冲突,请按 patches/BASE_COMMITS.txt 对齐基线后手动并入"
  fi
done
echo ""
echo "完成。构建见 README『构建』节(target_os=mac + use_xcode_clang=true)。"
