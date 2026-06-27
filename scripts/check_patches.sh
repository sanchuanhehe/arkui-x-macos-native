#!/usr/bin/env bash
# 补丁集自检:不需要 arkui-x 源码,纯校验补丁集自身的完整/一致/可解析。
# CI 与本地都用这个;通过即说明补丁集结构正确、可被 apply_patches.sh 幂等应用。
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

echo "== 2. 解析 MAP(仓:补丁名)=="
mapfile -t MAP < <(sed -n '/^MAP=(/,/^)/p' scripts/apply_patches.sh | grep -oE '"[^"]+:[^"]+"' | tr -d '"')
[ "${#MAP[@]}" -ge 1 ] && ok "MAP 共 ${#MAP[@]} 个仓" || bad "MAP 解析为空"

echo "== 3. 每个 patch 可解析且非空 =="
shopt -s nullglob
for p in "$PATCHES"/*.patch; do
  if [ -s "$p" ] && git apply --stat "$p" >/dev/null 2>&1; then :; else bad "patch 解析失败/空: $p"; fi
done
ok "$(ls "$PATCHES"/*.patch 2>/dev/null | wc -l | tr -d ' ') 个 patch 全部可解析"

echo "== 4. 每仓有补丁 + BASE_COMMITS 覆盖 =="
declare -A NAMES
for e in "${MAP[@]}"; do
  rel="${e%%:*}"; name="${e##*:}"; NAMES["$name"]=1
  cnt=$(ls "$PATCHES/${name}.patch" "$PATCHES/${name}-"*.patch 2>/dev/null | wc -l | tr -d ' ')
  [ "$cnt" -ge 1 ] || bad "$rel 没有任何 ${name}*.patch"
  grep -qE "^${rel}([[:space:]]|$)" "$PATCHES/BASE_COMMITS.txt" 2>/dev/null \
    && note "$rel ← ${cnt} 补丁,基线已记录" || bad "$rel 缺 BASE_COMMITS 基线"
done
ok "每仓均有补丁且基线齐备"

echo "== 5. 无孤儿 patch(每个 patch 都属于某 MAP 仓)=="
for p in "$PATCHES"/*.patch; do
  base="$(basename "$p" .patch)"; matched=0
  for name in "${!NAMES[@]}"; do
    if [ "$base" = "$name" ] || [[ "$base" == "$name-"* ]]; then matched=1; break; fi
  done
  [ "$matched" = 1 ] || bad "孤儿 patch(无 MAP 映射): $p"
done
ok "无孤儿 patch"

echo
if [ "$fail" = 0 ]; then printf '\033[32m✅ 补丁集校验全部通过\033[0m\n'; else printf '\033[31m❌ 补丁集校验失败\033[0m\n'; exit 1; fi
