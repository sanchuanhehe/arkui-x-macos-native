#!/usr/bin/env bash
# Linux/Wayland 渲染回归(CI 与本地)。真编真跑:用 arkui_for_linux 里验证过的
# Wayland+EGL smoketest,在 headless weston(Mesa llvmpipe 软渲染即可)下开窗、
# EGLSurface 渲染、glReadPixels 落帧,并校验帧里确实出现了期望的彩色条带——即
# 证明 ArkUI-X Linux 移植的核心出图链路没有回归(对应 DoD §0.1 第 1/6 项)。
#
# 用法: scripts/ci_linux_render_smoketest.sh [arkui_for_linux 路径]
#   不给路径则临时 clone github.com/sanchuanhehe/arkui_for_linux。
set -euo pipefail

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"; [ -n "${WPID:-}" ] && kill "$WPID" 2>/dev/null || true' EXIT

ADAPTER="${1:-}"
if [ -z "$ADAPTER" ]; then
  echo "== clone arkui_for_linux =="
  git clone --quiet --depth 1 https://github.com/sanchuanhehe/arkui_for_linux.git "$WORK/afl"
  ADAPTER="$WORK/afl"
fi
SEED="$ADAPTER/entrance/wayland/smoketest"
[ -f "$SEED/wlegl_smoke.c" ] || { echo "✗ 找不到 smoketest: $SEED/wlegl_smoke.c"; exit 1; }

echo "== 生成 xdg-shell 协议 + 编译 smoketest =="
WLP="$(pkg-config --variable=pkgdatadir wayland-protocols)"
cd "$WORK"
cp "$SEED/wlegl_smoke.c" .
wayland-scanner client-header "$WLP/stable/xdg-shell/xdg-shell.xml" xdg-shell-client-protocol.h
wayland-scanner private-code  "$WLP/stable/xdg-shell/xdg-shell.xml" xdg-shell-protocol.c
# smoketest 把帧写到固定 scratch 路径;改成写当前目录
sed -i 's#/tmp/[^"]*/frame.ppm#frame.ppm#' wlegl_smoke.c
read -ra PKGFLAGS <<< "$(pkg-config --cflags --libs wayland-client wayland-egl egl glesv2)"
cc -o wlegl_smoke wlegl_smoke.c xdg-shell-protocol.c "${PKGFLAGS[@]}"
echo "  ✓ 编译完成"

echo "== 启 headless weston + 运行 =="
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/xdg-$$}"
mkdir -p "$XDG_RUNTIME_DIR"; chmod 700 "$XDG_RUNTIME_DIR"
weston --backend=headless --socket=wl-ci --width=480 --height=800 >"$WORK/weston.log" 2>&1 &
WPID=$!
for _ in $(seq 1 25); do [ -S "$XDG_RUNTIME_DIR/wl-ci" ] && break; sleep 0.2; done
[ -S "$XDG_RUNTIME_DIR/wl-ci" ] || { echo "✗ weston 未起来"; cat "$WORK/weston.log"; exit 1; }
WAYLAND_DISPLAY=wl-ci ./wlegl_smoke
[ -f frame.ppm ] || { echo "✗ 未生成 frame.ppm"; exit 1; }

echo "== 校验渲染输出(期望深色底 + 青/品红/黄三条带)=="
python3 - <<'PYEOF'
import sys
f = open('frame.ppm', 'rb')
assert f.readline().strip() == b'P6'
w, h = map(int, f.readline().split()); f.readline()
data = f.read()
def near(px, rgb, tol=40):
    return all(abs(px[i] - rgb[i]) <= tol for i in range(3))
want = {'cyan': (0, 204, 229), 'magenta': (229, 51, 153), 'yellow': (242, 217, 25), 'bg': (31, 31, 36)}
hit = {k: 0 for k in want}
for i in range(0, len(data) - 2, 3):
    px = data[i:i+3]
    for k, rgb in want.items():
        if near(px, rgb):
            hit[k] += 1
missing = [k for k, v in hit.items() if v < 500]
print("  像素命中:", {k: v for k, v in hit.items()})
if missing:
    print("✗ 渲染回归:缺少颜色", missing); sys.exit(1)
print("  ✓ 三条带 + 背景均渲染正确")
PYEOF

echo ""
echo "✅ Linux/Wayland 渲染回归通过(headless weston + EGL 出图链路正常)"
