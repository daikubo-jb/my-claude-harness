#!/usr/bin/env bash
# Stop hook（完了ゲート）。
#
# 作業中のリポジトリに .claude/verify-fast.sh が実行可能な形であれば実行する。
# 無ければ何もしない。落ちたら exit 2 で1回だけ差し戻す。
# 差し戻しは1回まで。2回目（stop_hook_active）は止めずに人へ返す。
#
# verify-fast.sh には数分で終わる検証だけを置くこと。
# 重い検証はここではなく feature の手順の中で明示的に回す。
set -uo pipefail

payload="$(cat 2>/dev/null || true)"

# すでにこの hook が一度差し戻している。同じ失敗で回り続けさせない。
if printf '%s' "$payload" | grep -q '"stop_hook_active"[[:space:]]*:[[:space:]]*true'; then
  exit 0
fi

root="${CLAUDE_PROJECT_DIR:-}"
if [[ -z "$root" ]]; then
  root="$(printf '%s' "$payload" \
    | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
fi
[[ -n "$root" ]] || root="$PWD"

script="$root/.claude/verify-fast.sh"
[[ -x "$script" ]] || exit 0

# stdin は payload を読み切っている。verify-fast.sh が誤って読みに行って
# ハングしないよう /dev/null を渡す。
out="$(cd "$root" && "$script" </dev/null 2>&1)"
status=$?
[[ $status -eq 0 ]] && exit 0

{
  echo "完了ゲートが落ちました: $script (exit $status)"
  echo "--- 出力（末尾200行） ---"
  printf '%s\n' "$out" | tail -200
  echo "--- ここまで ---"
  echo "直してから完了にすること。直せないなら、どこまで進んだかを報告して止まること。"
} >&2
exit 2
