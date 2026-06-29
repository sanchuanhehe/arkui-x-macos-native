#!/usr/bin/env bash
# M10 真构建回归:在一棵已 apply 过补丁集的 ArkUI-X 源码树上,端到端验证
# macOS 原生 app(ace_macos)能从零编出 + 关键产物齐备 + demo bundle 可生成。
#
# 这是补丁集自检(check_patches.sh,纯结构校验,CI 跑)之外的「真编译」一层:
# 需要完整源码树 + Xcode + prebuilts,只能在 macOS 开发机本地跑,不进 CI
# (全量编译 10GB+ 源码、数十分钟)。用它在每次改动后防回退。
#
# 用法: scripts/verify_build.sh /path/to/arkui-x [--with-bundle]
#   --with-bundle  额外用 ace build bundle 编 HelloWorld demo 并校验 modules.abc
#
# 退出码:0=全绿;非 0=某步失败(stderr 给出是哪步)。

set -uo pipefail
SRC="${1:?用法: $0 /path/to/arkui-x [--with-bundle]}"
WITH_BUNDLE=0
[ "${2:-}" = "--with-bundle" ] && WITH_BUNDLE=1

SRC="$(cd "$SRC" && pwd)" || { echo "✗ 源码树不存在: $SRC"; exit 1; }

# --- 环境(与 README『构建』节一致)---
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
GN="$SRC/prebuilts/build-tools/darwin-x86/bin/gn"
NINJA="$SRC/prebuilts/build-tools/darwin-x86/bin/ninja"
PYBIN="$SRC/prebuilts/python/darwin-arm64/3.12.10/bin"   # 带 distutils 垫片
OUT="out/arkui-x"
TARGET="arkui/ace_engine/ace_macos"

pass=0; fail=0
ok()  { printf '\033[32m✓\033[0m %s\n' "$*"; pass=$((pass+1)); }
bad() { printf '\033[31m✗\033[0m %s\n' "$*" >&2; fail=$((fail+1)); }
step(){ printf '\n== %s ==\n' "$*"; }

step "0. 前置检查"
[ -x "$DEVELOPER_DIR/usr/bin/xcodebuild" ] && ok "Xcode: $DEVELOPER_DIR" || bad "缺 Xcode: $DEVELOPER_DIR"
[ -x "$GN" ]    && ok "gn 存在"    || bad "缺 gn: $GN"
[ -x "$NINJA" ] && ok "ninja 存在" || bad "缺 ninja: $NINJA"
[ -d "$PYBIN" ] && ok "prebuilts python(distutils 垫片)" || bad "缺 prebuilts python: $PYBIN"
# adapter/macos 子仓必须已克隆(apply_patches.sh 负责)
[ -f "$SRC/foundation/arkui/ace_engine/adapter/macos/build/BUILD.gn" ] \
  && ok "adapter/macos 子仓就位" || bad "缺 adapter/macos(先跑 apply_patches.sh)"
[ "$fail" -ne 0 ] && { echo "前置不满足,中止"; exit 1; }

export PATH="$PYBIN:$PATH"
cd "$SRC" || exit 1

step "1. gn gen"
if "$GN" gen "$OUT" >/tmp/m10_gn.log 2>&1; then ok "gn gen 成功"
else bad "gn gen 失败(见 /tmp/m10_gn.log)"; tail -5 /tmp/m10_gn.log >&2; exit 1; fi

step "2. ninja 编 ace_macos(可能数分钟)"
if "$NINJA" -C "$OUT" "$TARGET" >/tmp/m10_ninja.log 2>&1; then ok "ninja 构建成功"
else
  bad "ninja 构建失败"
  grep -E "duplicate symbol|error:|Undefined symbols|symbol\(s\) not found" /tmp/m10_ninja.log | head -15 >&2
  exit 1
fi

step "3. 产物校验"
BIN="$OUT/$TARGET"
if [ -x "$BIN" ]; then
  ok "ace_macos 可执行: $(du -h "$BIN" | cut -f1)"
  # arm64 架构核对
  if file "$BIN" | grep -q arm64; then ok "arm64 架构"; else bad "非 arm64"; fi
else bad "缺 ace_macos 二进制"; fi
# bundle abc(M1 摆放的运行时入口)
ABC="$OUT/arkui/ace_engine/arkui-x/entry/ets/modules.abc"
[ -f "$ABC" ] && ok "运行时 modules.abc 就位" || echo "  (modules.abc 缺,首次需 ace build bundle)"
# systemres resources.index(主题色,缺则组件黑框)
RESIDX="$OUT/arkui/ace_engine/arkui-x/systemres/resources.index"
[ -f "$RESIDX" ] && ok "systemres resources.index 就位" \
  || echo "  (resources.index 缺,跑 scripts/build_systemres.sh 修复主题色)"

if [ "$WITH_BUNDLE" -eq 1 ]; then
  step "4. demo bundle(ace build bundle)"
  DEMO="$SRC/samples/BasicFeature/HelloWorld"
  if [ -d "$DEMO" ]; then
    ( cd "$DEMO" && "$SRC/developtools/ace_tools/bin/ace" build bundle >/tmp/m10_bundle.log 2>&1 )
    # ace build bundle 末尾常因 systemres copy 报 ENOENT,但 abc 已先产出 —— 校验 abc 而非退出码
    DEMO_ABC="$DEMO/.arkui-x/ios/arkui-x/entry/ets/modules.abc"
    if [ -f "$DEMO_ABC" ]; then ok "demo modules.abc 生成($(du -h "$DEMO_ABC" | cut -f1))"
    else bad "demo bundle 未产出 abc(见 /tmp/m10_bundle.log)"; fi
  else bad "缺 demo: $DEMO"; fi
fi

step "结果"
printf '通过 %d 项,失败 %d 项\n' "$pass" "$fail"
[ "$fail" -eq 0 ] && { echo "✅ 真构建回归全绿"; exit 0; } || { echo "❌ 有失败项"; exit 1; }
