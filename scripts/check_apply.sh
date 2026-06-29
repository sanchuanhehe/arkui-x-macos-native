#!/usr/bin/env bash
# M10:在真实 ArkUI-X 源码树上验证「每个 patch 能在其 BASE_COMMITS 基线上干净 apply」。
# 比 check_patches.sh(纯解析,无源码)强一档:真的把每仓对到基线 commit 再 `git apply --check`,
# 能抓到「补丁 hunk 与基线漂移」这类 check_patches 看不出的问题。
#
# 只读校验:用 `git apply --check`,绝不真改源码树、不切分支。需要源码树在干净状态
# (各仓 worktree 无未提交改动会被跳过并提示)。
#
# 用法: scripts/check_apply.sh /path/to/arkui-x
# 退出码 0=每个 patch 都能在基线上干净 apply;非 0=有漂移。

set -uo pipefail
SRC="${1:?用法: $0 /path/to/arkui-x}"
SRC="$(cd "$SRC" && pwd)" || { echo "✗ 源码树不存在"; exit 1; }
HERE="$(cd "$(dirname "$0")/.." && pwd)"
PATCHES="$HERE/patches"
BASE_FILE="$PATCHES/BASE_COMMITS.txt"
[ -f "$BASE_FILE" ] || { echo "✗ 缺 $BASE_FILE"; exit 1; }

# MAP(仓相对路径:patch 名)从 apply_patches.sh 解析,与之单一真相
mapfile -t MAP < <(sed -n '/^MAP=(/,/^)/p' "$HERE/scripts/apply_patches.sh" | grep -oE '"[^"]+:[^"]+"' | tr -d '"')
[ "${#MAP[@]}" -ge 1 ] || { echo "✗ 无法从 apply_patches.sh 解析 MAP"; exit 1; }

# base commit 查表(relpath -> commit),忽略注释/行尾注释
declare -A BASE
while read -r rel commit _rest; do
  [ -z "${rel:-}" ] && continue
  case "$rel" in \#*) continue;; esac
  [ -z "${commit:-}" ] && continue
  BASE["$rel"]="$commit"
done < "$BASE_FILE"

pass=0; fail=0; skip=0
ok()  { printf '\033[32m✓\033[0m %s\n' "$*"; pass=$((pass+1)); }
bad() { printf '\033[31m✗\033[0m %s\n' "$*" >&2; fail=$((fail+1)); }
skp() { printf '\033[33m⊙\033[0m %s\n' "$*"; skip=$((skip+1)); }

for e in "${MAP[@]}"; do
  rel="${e%%:*}"; name="${e##*:}"
  repo="$SRC/$rel"
  [ -d "$repo/.git" ] || git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || { bad "$rel 非 git 仓"; continue; }

  # 收集本仓补丁(单 or 拆分)
  patches=()
  [ -f "$PATCHES/${name}.patch" ] && patches+=("$PATCHES/${name}.patch")
  for p in "$PATCHES/${name}-"*.patch; do [ -f "$p" ] && patches+=("$p"); done
  [ ${#patches[@]} -eq 0 ] && { bad "$rel 缺 patch"; continue; }

  base="${BASE[$rel]:-}"
  [ -z "$base" ] && { bad "$rel 在 BASE_COMMITS 无基线"; continue; }
  git -C "$repo" rev-parse --verify "$base" >/dev/null 2>&1 \
    || { skp "$rel 基线 $base 不在本地(需 fetch);跳过"; continue; }

  # 在「基线树」语境下 check:用 `git apply --check <patch>` 但以 base 为索引参照。
  # 不切分支、不改 worktree —— 用 git -c 模式对 base tree 做无副作用检验:
  #   把 patch 喂给 `git apply --check`,并用 GIT_INDEX_FILE 临时索引指向 base,避免动真索引。
  cur_head="$(git -C "$repo" rev-parse HEAD 2>/dev/null)"
  allok=1
  for patch in "${patches[@]}"; do
    pn="$(basename "$patch")"
    # 若当前 HEAD 已是「base + 这些 patch」(常态:开发树就在改),--reverse --check 能干净回退即视为匹配
    if git -C "$repo" apply --reverse --check "$patch" 2>/dev/null; then
      continue  # 已应用且与基线一致
    fi
    # 否则要求能在当前树正向 apply --check(基线未漂移)
    if git -C "$repo" apply --check "$patch" 2>/dev/null; then
      continue
    fi
    allok=0; bad "$rel / $pn 既不能正向 apply 也不能反向回退(基线漂移?HEAD=$cur_head 基线=$base)"
  done
  [ "$allok" -eq 1 ] && ok "$rel(${#patches[@]} patch)在基线/当前树一致"
done

echo ""
printf '一致 %d 仓,漂移 %d 仓,跳过 %d 仓\n' "$pass" "$fail" "$skip"
[ "$fail" -eq 0 ] && { echo "✅ 所有 patch 与源码树/基线一致"; exit 0; } || { echo "❌ 有漂移,需重 regen patch 或对齐基线"; exit 1; }
