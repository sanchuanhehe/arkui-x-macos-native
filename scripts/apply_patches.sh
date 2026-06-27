#!/bin/bash
# 把 patches/ 下的补丁应用到 ArkUI-X 源码树(15 仓的 mac-port 改动)。
# 每个仓应用 <name>.patch(单补丁)或 <name>-*.patch(拆分补丁集,按名排序应用)。
# ace_engine 体量大,已拆为 ace_engine-1-adapter-macos / -2-framework / -3-build 三个子补丁。
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
  "arkcompiler/ets_runtime:ets_runtime"
  "interface/sdk-js:sdk-js"
  "foundation/arkui/napi:napi"
  "foundation/multimodalinput/input:input"
)

for e in "${MAP[@]}"; do
  rel="${e%%:*}"; name="${e##*:}"
  repo="$SRC/$rel"
  echo "=== $rel ==="
  git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || { echo "  ✗ 非 git 仓: $repo"; exit 1; }
  # 收集本仓补丁:<name>.patch(单)或 <name>-*.patch(拆分,按名排序)
  patches=()
  [ -f "$PATCHES/${name}.patch" ] && patches+=("$PATCHES/${name}.patch")
  for p in "$PATCHES/${name}-"*.patch; do [ -f "$p" ] && patches+=("$p"); done
  [ ${#patches[@]} -eq 0 ] && { echo "  ✗ 缺 patch: ${name}.patch / ${name}-*.patch"; exit 1; }
  if [ -n "$(git -C "$repo" status --porcelain)" ]; then
    echo "  ⚠ 工作区不干净,跳过"; continue
  fi
  git -C "$repo" rev-parse --verify "$BRANCH" >/dev/null 2>&1 \
    && git -C "$repo" checkout "$BRANCH" \
    || git -C "$repo" checkout -b "$BRANCH"
  for patch in "${patches[@]}"; do
    pn="$(basename "$patch")"
    if git -C "$repo" apply --check "$patch" 2>/dev/null; then
      git -C "$repo" apply "$patch"; echo "  ✓ 已应用 $pn"
    else
      echo "  ⚠ $pn 直接 apply 冲突,改 3-way:"; git -C "$repo" apply --3way "$patch" \
        || echo "  ✗ $pn 仍冲突,请按 patches/BASE_COMMITS.txt 对齐基线后手动并入"
    fi
  done
done
echo ""
echo "完成。构建见 README『构建』节(target_os=mac + use_xcode_clang=true)。"
