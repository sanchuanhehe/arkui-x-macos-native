#!/usr/bin/env bash
# 补丁集自检:不需要 arkui-x 源码,纯校验补丁集自身的完整/一致/可解析。
# CI 与本地都用这个;通过即说明 mac + linux 两套补丁结构正确、可被 apply_patches.sh
# 幂等应用。
#   用法: scripts/check_patches.sh
set -uo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$HERE" || { echo "无法进入仓根 $HERE"; exit 1; }
PATCHES="patches"
fail=0
note() { printf '  %s\n' "$*"; }
ok()   { printf '\033[32m✓\033[0m %s\n' "$*"; }
bad()  { printf '\033[31m✗\033[0m %s\n' "$*"; fail=1; }

echo "== 1. 脚本语法 =="
bash -n scripts/apply_patches.sh && ok "apply_patches.sh 语法 OK" || bad "apply_patches.sh 语法错"
bash -n scripts/check_patches.sh && ok "check_patches.sh 语法 OK" || bad "check_patches.sh 语法错"

# 解析 apply_patches.sh 里 mac) 与 linux) case 块各自的 MAP(仓相对路径:补丁名)。
parse_map() { # $1 = case label (mac|linux)
  sed -n "/^  ${1})\$/,/^    ;;/p" scripts/apply_patches.sh \
    | sed -n '/MAP=(/,/^    )/p' | grep -oE '"[^"]+:[^"]+"' | tr -d '"'
}
mapfile -t MAC_MAP   < <(parse_map mac)
mapfile -t LINUX_MAP < <(parse_map linux)

echo "== 2. 解析 MAP =="
[ "${#MAC_MAP[@]}" -ge 1 ]   && ok "mac MAP 共 ${#MAC_MAP[@]} 个仓"     || bad "mac MAP 解析为空"
[ "${#LINUX_MAP[@]}" -ge 1 ] && ok "linux MAP 共 ${#LINUX_MAP[@]} 个仓" || bad "linux MAP 解析为空"

echo "== 3. 每个 patch 可解析且非空 =="
shopt -s nullglob
for p in "$PATCHES"/*.patch; do
  if [ -s "$p" ] && git apply --stat "$p" >/dev/null 2>&1; then :; else bad "patch 解析失败/空: $p"; fi
done
ok "$(ls "$PATCHES"/*.patch 2>/dev/null | wc -l | tr -d ' ') 个 patch 全部可解析"

echo "== 4. 每仓有补丁 + BASE_COMMITS 覆盖 =="
declare -A NAMES        # mac 补丁名(单/拆分)
declare -A LINUX_NAMES  # linux 补丁名(linux-<name>)
for e in "${MAC_MAP[@]}"; do
  rel="${e%%:*}"; name="${e##*:}"; NAMES["$name"]=1
  cnt=$(ls "$PATCHES/${name}.patch" "$PATCHES/${name}-"*.patch 2>/dev/null | wc -l | tr -d ' ')
  [ "$cnt" -ge 1 ] || bad "[mac] $rel 没有任何 ${name}*.patch"
  grep -qE "^${rel}([[:space:]]|$)" "$PATCHES/BASE_COMMITS.txt" 2>/dev/null \
    || bad "[mac] $rel 缺 BASE_COMMITS 基线"
done
ok "mac: 每仓均有补丁且基线齐备"
for e in "${LINUX_MAP[@]}"; do
  rel="${e%%:*}"; name="${e##*:}"; LINUX_NAMES["$name"]=1
  [ -f "$PATCHES/linux-${name}.patch" ] || bad "[linux] $rel 缺 linux-${name}.patch"
  grep -qE "^${rel}([[:space:]]|$)" "$PATCHES/BASE_COMMITS.txt" 2>/dev/null \
    || bad "[linux] $rel 缺 BASE_COMMITS 基线"
done
ok "linux: 每仓均有 linux-*.patch 且基线齐备"

echo "== 5. 无孤儿 patch(每个 patch 都属于某 MAP 仓)=="
for p in "$PATCHES"/*.patch; do
  base="$(basename "$p" .patch)"; matched=0
  # linux-<name>
  if [[ "$base" == linux-* ]]; then
    lname="${base#linux-}"
    [ -n "${LINUX_NAMES[$lname]:-}" ] && matched=1
  else
    for name in "${!NAMES[@]}"; do
      if [ "$base" = "$name" ] || [[ "$base" == "$name-"* ]]; then matched=1; break; fi
    done
  fi
  [ "$matched" = 1 ] || bad "孤儿 patch(无 MAP 映射): $p"
done
ok "无孤儿 patch"

echo
if [ "$fail" = 0 ]; then printf '\033[32m✅ 补丁集校验全部通过\033[0m\n'; else printf '\033[31m❌ 补丁集校验失败\033[0m\n'; exit 1; fi
