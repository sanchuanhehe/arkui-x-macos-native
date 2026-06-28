#!/bin/bash
# 把 patches/ 下的补丁应用到 ArkUI-X 源码树(18 仓的 mac-port 改动)。
# 每个仓应用 <name>.patch(单补丁)或 <name>-*.patch(拆分补丁集,按名排序应用)。
# ace_engine 拆为 ace_engine-2-framework / -3-build 两个子补丁;
# adapter/macos(原 -1-adapter-macos)已独立成子仓,改为克隆引入(见文件尾部)。
# 用法: scripts/apply_patches.sh /path/to/arkui-x
set -e
SRC="${1:?用法: $0 /path/to/arkui-x}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
PATCHES="$HERE/patches"
BRANCH="mac-port"

# adapter/macos 不随补丁分发,改为独立子仓克隆(对齐 adapter/android、adapter/ios)
MACOS_ADAPTER_URL="https://github.com/sanchuanhehe/arkui_for_macos.git"
MACOS_ADAPTER_REL="foundation/arkui/ace_engine/adapter/macos"

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
  "plugins:plugins"
  "developtools/ace_ets2bundle:ace_ets2bundle"
  "samples:samples"
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
  # 切到/建 mac-port(已在则不动,使重复运行安全)
  cur="$(git -C "$repo" rev-parse --abbrev-ref HEAD 2>/dev/null)"
  if [ "$cur" != "$BRANCH" ]; then
    if [ -n "$(git -C "$repo" status --porcelain)" ]; then
      echo "  ⚠ 工作区不干净且不在 $BRANCH,跳过(请先清理工作区)"; continue
    fi
    git -C "$repo" rev-parse --verify "$BRANCH" >/dev/null 2>&1 \
      && git -C "$repo" checkout -q "$BRANCH" \
      || git -C "$repo" checkout -q -b "$BRANCH"
  fi
  for patch in "${patches[@]}"; do
    pn="$(basename "$patch")"
    # 幂等:已应用(反向可干净回退)则跳过 —— 重复运行不会重复打或报错
    if git -C "$repo" apply --reverse --check "$patch" 2>/dev/null; then
      echo "  ⊙ $pn 已应用,跳过"; continue
    fi
    if git -C "$repo" apply --check "$patch" 2>/dev/null; then
      git -C "$repo" apply "$patch"; echo "  ✓ 已应用 $pn"
    else
      echo "  ⚠ $pn 直接 apply 冲突,改 3-way:"; git -C "$repo" apply --3way "$patch" \
        || echo "  ✗ $pn 仍冲突,请按 patches/BASE_COMMITS.txt 对齐基线后手动并入"
    fi
  done
done

# === adapter/macos 子仓克隆(对齐 adapter/android、adapter/ios 的独立仓结构)===
echo "=== ${MACOS_ADAPTER_REL} (子仓) ==="
macos_dir="$SRC/$MACOS_ADAPTER_REL"
if [ -d "$macos_dir/.git" ]; then
  echo "  ⊙ 已是子仓,git pull --ff-only 更新"
  git -C "$macos_dir" pull --ff-only --quiet || echo "  ⚠ 更新失败,请手动处理"
elif [ -e "$macos_dir" ] && [ -n "$(ls -A "$macos_dir" 2>/dev/null)" ]; then
  echo "  ⚠ 目录已存在且非子仓,跳过(请先清理 $macos_dir 后重试)"
else
  if git clone --quiet "$MACOS_ADAPTER_URL" "$macos_dir"; then
    echo "  ✓ 已克隆 adapter/macos ← $MACOS_ADAPTER_URL"
  else
    echo "  ✗ 克隆失败: $MACOS_ADAPTER_URL"
  fi
fi

echo ""
echo "完成。构建见 README『构建』节(target_os=mac + use_xcode_clang=true)。"
