#!/usr/bin/env bash
# このリポジトリを ~/.claude にリンクする。
# マスターはこのリポジトリ。~/.claude 側は1ファイルずつのシンボリックリンクなので、
# ここを編集すれば即座に全プロジェクトへ反映される。
set -euo pipefail

HARNESS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${HOME}/.claude"

# 旧構成では ~/.claude/agents 等がディレクトリごとのリンクだった。
# 1ファイルずつリンクする方式に変わったので、古いリンクは外す。
for kind in agents commands skills; do
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
  for kind in agents skills; do
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
  for kind in agents commands skills; do
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

cat <<MSG

settings.json は自動で書き換えません。以下が入っているか確認してください:

  "permissions": { "additionalDirectories": ["$HOME/dev/doc-storage"] },
  "env": {
    "CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS": "4",
    "CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH": "2",
    "CLAUDE_CODE_GOAL_CHECKIN_MINUTES": "0"
  }
MSG
