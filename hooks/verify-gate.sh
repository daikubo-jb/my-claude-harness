#!/usr/bin/env bash
# Stop hook（完了ゲート）。
#
# 許可したリポジトリでだけ、.claude/verify-fast.sh を実行する。
# 落ちたら exit 2 で1回だけ差し戻す。2回目（stop_hook_active）は止めずに人へ返す。
#
# 許可リストは ~/.claude/verify-gate-allow。1行に1ディレクトリ、絶対パスか ~/ 始まり。
# # 以降はコメント。書いたディレクトリとその配下が対象。
# リストに無いリポジトリでは何もしない。Stop hook は permissions を通らないので、
# これが無いと clone してきただけのリポジトリのスクリプトが動いてしまう。
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
root="$(cd "$root" 2>/dev/null && pwd -P)" || exit 0

# 許可リストに載っているディレクトリ（とその配下）だけを対象にする。
allow="${HOME}/.claude/verify-gate-allow"
[[ -f "$allow" ]] || exit 0

allowed=0
while IFS= read -r line || [[ -n "$line" ]]; do
  line="$(printf '%s' "$line" | sed 's/#.*//; s/^[[:space:]]*//; s/[[:space:]]*$//')"
  [[ -n "$line" ]] || continue
  entry="${line/#\~/$HOME}"
  entry="$(cd "$entry" 2>/dev/null && pwd -P)" || continue
  if [[ "$root" == "$entry" || "$root" == "$entry"/* ]]; then
    allowed=1
    break
  fi
done < "$allow"
[[ "$allowed" == 1 ]] || exit 0

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
