#!/usr/bin/env bash
# 编译 OpenHarmony 系统资源(systemres)的 resources.index 并装入 ace_macos 运行时目录。
#
# 为什么需要:ArkUI 的默认样式组件(Button、Checkbox… 的主题色/尺寸)从 systemres 的
# resources.index 解析颜色。缺它时主题色解析失败,组件渲染成黑框(M1 期只摆了 systemres
# 的 .abc,没有 resources.index)。restool 把 base/global/system_resources/systemres 的原始
# 资源(含 base / dark 暗色 / wearable)编成 resources.index + resources/,装到运行时即修复。
#
# 用法: scripts/build_systemres.sh /path/to/arkui-x [sdk_version]
set -euo pipefail
SRC="${1:?用法: $0 /path/to/arkui-x [sdk_version]}"
SDK_VER="${2:-23}"

RESTOOL="$HOME/Library/OpenHarmony/Sdk/${SDK_VER}/toolchains/restool"
[ -x "$RESTOOL" ] || RESTOOL="/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/restool"
[ -x "$RESTOOL" ] || { echo "✗ 找不到 restool(查过 ~/Library/OpenHarmony/Sdk/${SDK_VER} 与 DevEco)"; exit 1; }

SR="$SRC/base/global/system_resources/systemres"
[ -f "$SR/main/module.json" ] || { echo "✗ 找不到 systemres 源: $SR/main/module.json"; exit 1; }

OUT="$(mktemp -d)"
echo "== restool 编译 systemres =="
"$RESTOOL" -i "$SR/main" -i "$SR/AppScope" -j "$SR/main/module.json" \
  -o "$OUT" -p ohos.global.systemres -r "$OUT/ResourceTable.h" -f
[ -f "$OUT/resources.index" ] || { echo "✗ 未产出 resources.index"; exit 1; }

# 装入运行时 systemres 目录(与 .abc 同级)。resource_adapter 找 packagePath/systemres/resources.index。
DST="$SRC/out/arkui-x/arkui/ace_engine/arkui-x/systemres"
mkdir -p "$DST"
cp "$OUT/resources.index" "$DST/"
rm -rf "$DST/resources"
cp -R "$OUT/resources" "$DST/"
rm -rf "$OUT"
echo "✅ 已装入 $DST/{resources.index,resources/}(含 base/dark/wearable)"
echo "   现在默认样式组件(Button 等)与暗色模式资源均可解析。"
