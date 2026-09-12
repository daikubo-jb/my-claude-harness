#!/usr/bin/env bash
# このリポジトリを ~/.claude にリンクし、settings.json へ最小限の設定をマージする。
# マスターはこのリポジトリ。~/.claude 側は1ファイルずつのシンボリックリンクなので、
# ここを編集すれば即座に全プロジェクトへ反映される。
#
# リンクは絶対パスで張る。リポジトリを別の場所へ移動したら再実行すること。
# 移動しただけでリンクは全部切れ、ハーネスは無効になる。
#
# 2回流しても結果は変わらない（冪等）。
set -euo pipefail

HARNESS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${HOME}/.claude"
SETTINGS="$TARGET/settings.json"
FRAGMENT="$HARNESS/settings-fragment.json"

# 旧構成では ~/.claude/agents 等がディレクトリごとのリンクだった。
# 1ファイルずつリンクする方式に変わったので、古いリンクは外す。
for kind in agents commands skills hooks; do
  if [[ -L "$TARGET/$kind" ]]; then
    echo "旧構成のリンクを外します: $TARGET/$kind"
    rm "$TARGET/$kind"
  fi
done

backup_or_unlink() {
  local dst="$1" backup
  if [[ -L "$dst" ]]; then
    rm "$dst"
  elif [[ -e "$dst" ]]; then
    backup="${dst}.bak.$(date +%Y%m%d%H%M%S)"
    echo "既存の $dst を $backup に退避します"
    mv "$dst" "$backup"
  fi
}

link_tree() {
  local kind entry dst
  for kind in agents skills hooks; do
    [[ -d "$HARNESS/$kind" ]] || continue
    mkdir -p "$TARGET/$kind"
    for entry in "$HARNESS/$kind"/*; do
      [[ -e "$entry" ]] || continue
      dst="$TARGET/$kind/$(basename "$entry")"
      backup_or_unlink "$dst"
      ln -s "$entry" "$dst"
      echo "linked: $dst -> $entry"
    done
  done
}

# このリポジトリを指しているのに実体が無くなったリンクを外す。
# （ファイルの移動・削除、commands/ の skills/ への統合で発生する）
prune_stale() {
  local kind entry target
  for kind in agents commands skills hooks; do
    [[ -d "$TARGET/$kind" ]] || continue
    for entry in "$TARGET/$kind"/*; do
      [[ -L "$entry" ]] || continue
      target="$(readlink "$entry")"
      [[ "$target" == "$HARNESS"/* ]] || continue
      [[ -e "$target" ]] && continue
      rm "$entry"
      echo "removed stale: $entry"
    done
    rmdir "$TARGET/$kind" 2>/dev/null || true
  done
}

mkdir -p "$TARGET"
prune_stale
link_tree

backup_or_unlink "$TARGET/CLAUDE.md"
ln -s "$HARNESS/CLAUDE.md" "$TARGET/CLAUDE.md"
echo "linked: $TARGET/CLAUDE.md -> $HARNESS/CLAUDE.md"

# doc-storage の配置ルートは skills/doc-storage/SKILL.md の1行だけが持つ。
DOC_ROOT_RAW="$(sed -n 's/^DOC_STORAGE_ROOT=//p' \
  "$HARNESS/skills/doc-storage/SKILL.md" | head -1)"
DOC_ROOT="${DOC_ROOT_RAW/#\~/$HOME}"

if [[ -z "$DOC_ROOT_RAW" ]]; then
  echo "エラー: skills/doc-storage/SKILL.md から DOC_STORAGE_ROOT を読めませんでした" >&2
  exit 1
fi

# permissions のパス指定は gitignore 記法。絶対パスは「//」始まり、ホーム相対は「~/」。
# 単独の「/」始まりは設定ファイルの場所（~/.claude）を指してしまうので、必ず変換する。
case "$DOC_ROOT_RAW" in
  '~'/*) DENY_ROOT="$DOC_ROOT_RAW" ;;
  /*)    DENY_ROOT="/$DOC_ROOT_RAW" ;;
  *)
    echo "エラー: DOC_STORAGE_ROOT は '~/' か '/' で始めてください: $DOC_ROOT_RAW" >&2
    exit 1
    ;;
esac

if [[ ! -d "$DOC_ROOT" ]]; then
  echo
  echo "doc-storage がまだありません: $DOC_ROOT"
  echo "作るか、skills/doc-storage/SKILL.md の DOC_STORAGE_ROOT を書き換えてください。"
fi

# 完了ゲートの許可リスト。無ければ雛形を置く（中身は空なので、この時点では
# どのリポジトリでも verify-fast.sh は動かない）。既にあれば触らない。
ALLOW="$TARGET/verify-gate-allow"
if [[ ! -e "$ALLOW" ]]; then
  cat > "$ALLOW" <<'ALLOWEOF'
# 完了ゲート（hooks/verify-gate.sh）を効かせるディレクトリ。
# 1行に1つ、絶対パスか ~/ 始まりで書く。書いたディレクトリとその配下が対象。
# ここに無いリポジトリでは .claude/verify-fast.sh があっても実行しない。
ALLOWEOF
  echo "created: ${ALLOW}（空。使うリポジトリを1行ずつ足す）"
fi

# settings.json へのマージ。
# ~/.claude/settings.json は Claude Code 自身と他のツールも書くので、リンクせず
# 必要な2キーだけを足す。既存のキーとエントリは消さない。
if ! command -v jq >/dev/null 2>&1; then
  echo "エラー: jq が必要です（settings.json のマージに使う）。" >&2
  echo "  brew install jq などで入れてから ./install.sh を再実行してください。" >&2
  exit 1
fi

[[ -f "$SETTINGS" ]] || echo '{}' > "$SETTINGS"

if ! jq -e 'type == "object"' "$SETTINGS" >/dev/null 2>&1; then
  echo "エラー: $SETTINGS が JSON オブジェクトではありません。直してから再実行してください。" >&2
  exit 1
fi

# プレースホルダの置換は jq でやる。パスに & や | が入っても壊れない。
# deny: ハーネスが書いた形（Edit(<root>/*/human-doc/**)）だけを外してから和集合を取る。
#       DOC_STORAGE_ROOT を変えたとき、旧パスのルールが残り続けるのを防ぐためで、
#       ユーザーが自分で書いた human-doc 系のルールには触らない。
# Stop: verify-gate.sh を指すコマンドだけを **グループの中の1本単位で** 外してから足す。
#       グループごと落とすと、同じグループに同居する他の hook を巻き込む。
MERGED="$(jq --argjson frag "$(cat "$FRAGMENT")" --arg root "$DENY_ROOT" '
  ($frag.permissions.deny | map(gsub("<DOC_STORAGE_ROOT>"; $root))) as $deny
  | .permissions = (
    (.permissions // {}) as $p
    | $p + { deny: (
        ((($p.deny // [])
          | map(select(test("^Edit\\(.*/\\*/human-doc/\\*\\*\\)$") | not)))
         + $deny) | unique
      ) }
  )
  | .hooks = (
    (.hooks // {}) as $h
    | $h + { Stop: (
        (($h.Stop // [])
          | map(
              if has("hooks")
              then .hooks = ((.hooks // [])
                | map(select(((.command // "") | test("verify-gate\\.sh")) | not)))
              else . end
            )
          | map(select(
              if has("hooks")
              then ((.hooks | length) > 0)
              else (((.command // "") | test("verify-gate\\.sh")) | not) end
            )))
        + $frag.hooks.Stop
      ) }
  )
' "$SETTINGS" || true)"

if [[ -z "$MERGED" ]] || ! printf '%s' "$MERGED" | jq empty >/dev/null 2>&1; then
  echo "エラー: settings.json のマージに失敗しました。$SETTINGS は変更していません。" >&2
  exit 1
fi

# 内容が変わるときだけ退避して書く。2回目以降は何も起きない。
if [[ "$MERGED" == "$(cat "$SETTINGS")" ]]; then
  echo "settings.json は変更なし（すでにマージ済み）"
else
  SETTINGS_BACKUP="${SETTINGS}.bak.$(date +%Y%m%d%H%M%S)"
  cp "$SETTINGS" "$SETTINGS_BACKUP"
  echo "退避しました: $SETTINGS_BACKUP"
  printf '%s\n' "$MERGED" > "$SETTINGS"
  echo "merged: $SETTINGS （permissions.deny / hooks.Stop）"
fi

cat <<MSG

settings.json のうち、以下は自動で書き換えません。入っているか確認してください:

  "permissions": { "additionalDirectories": ["$DOC_ROOT"] },
  "env": {
    "CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS": "4",
    "CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH": "2",
    "CLAUDE_CODE_GOAL_CHECKIN_MINUTES": "0"
  }

メインモデルは固定しません。セッションごとに /model で選んでください
（設計は opus / fable、実装は sonnet）。

完了ゲートを使うリポジトリは $ALLOW に1行ずつ追加してください。
空のままなら、どのリポジトリでも verify-fast.sh は実行されません。
MSG
