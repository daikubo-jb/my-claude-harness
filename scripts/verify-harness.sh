#!/usr/bin/env bash
# ハーネス自身の検証。ファイルの体裁だけでなく、隔離した HOME で install.sh を
# 実際に流し、Stop hook を実際に叩いて挙動を確かめる。
#
#   bash scripts/verify-harness.sh
#
# ハーネスを変更したら、コミットの前にこれを通すこと。
set -uo pipefail

HARNESS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HARNESS"

FAIL=0
PASS=0

ok()   { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
ng()   { FAIL=$((FAIL + 1)); printf '  NG   %s\n' "$1"; }
check() { if [[ "$1" == 0 ]]; then ok "$2"; else ng "$2${3:+ — $3}"; fi; }
section() { printf '\n== %s\n' "$1"; }

# frontmatter（先頭の --- から次の --- まで）を取り出す
frontmatter() { awk 'NR==1 && $0!="---" {exit} NR>1 && $0=="---" {exit} NR>1' "$1"; }

has_key() { frontmatter "$1" | grep -qE "^$2:[[:space:]]*[^[:space:]]"; }

section "1. skills の frontmatter"
for f in skills/*/SKILL.md; do
  for key in name description; do
    has_key "$f" "$key"
    check $? "$f: $key"
  done
done

section "2. agents の frontmatter"
for f in agents/*.md; do
  for key in name description tools model; do
    has_key "$f" "$key"
    check $? "$f: $key"
  done
done
# 計画で決めたモデル配置。frontmatter に限定して見る（本文の散文に釣られない）
assert_fm() { [[ "$(frontmatter "$1" | sed -n "s/^$2:[[:space:]]*//p" | head -1)" == "$3" ]]; }
assert_fm agents/advisor.md      model  opus;   check $? "advisor は opus"
assert_fm agents/plan-reviewer.md model fable;  check $? "plan-reviewer は fable"
assert_fm agents/test-runner.md  effort medium; check $? "test-runner は effort: medium"
assert_fm agents/doc-writer.md   model  haiku;  check $? "doc-writer は haiku"

section "3. settings-fragment.json"
jq empty settings-fragment.json 2>/dev/null; check $? "有効な JSON"
jq -e '.permissions.deny | type == "array" and length > 0' settings-fragment.json >/dev/null 2>&1
check $? "permissions.deny がある"
jq -e '.hooks.Stop | type == "array" and length > 0' settings-fragment.json >/dev/null 2>&1
check $? "hooks.Stop がある"
jq -e '.permissions.deny | length <= 6' settings-fragment.json >/dev/null 2>&1
check $? "deny は6件以内"
for form in 'Bash(git push*--force*)' 'Bash(git push -f *)' 'Bash(git push * -f)' \
            'Bash(rm -rf /*)' 'Bash(rm -rf ~*)'; do
  jq -e --arg f "$form" '.permissions.deny | index($f)' settings-fragment.json >/dev/null 2>&1
  check $? "deny に $form がある"
done
jq -r '.permissions.deny[]' settings-fragment.json | grep -q '<DOC_STORAGE_ROOT>'
check $? "DOC_STORAGE_ROOT がプレースホルダで入っている"
jq -r '.hooks.Stop[].hooks[].command' settings-fragment.json | grep -q 'verify-gate.sh'
check $? "Stop hook が verify-gate.sh を指す"

section "4. シェルスクリプト"
for f in install.sh hooks/*.sh scripts/*.sh; do
  bash -n "$f" 2>/dev/null; check $? "$f: bash -n"
done
for f in hooks/*.sh; do
  [[ -x "$f" ]]; check $? "$f: 実行ビット"
done

section "5. 参照されているファイルが実在する"
REFLIST="$(mktemp)"
for f in CLAUDE.md README.md LICENSE install.sh settings-fragment.json; do
  [[ -f "$f" ]]; check $? "$f がある"
done
# `skill: <名前>` の参照先
grep -rhoE 'skill: [a-z0-9-]+' CLAUDE.md README.md skills agents 2>/dev/null \
  | sed 's/^skill: //' | sort -u | while read -r s; do
    [[ -f "skills/$s/SKILL.md" ]] && echo "ok   skill: $s" || echo "NG   skill: $s が無い"
  done > "$REFLIST"
while read -r line; do
  case "$line" in ok*) ok "${line#ok   }" ;; *) ng "${line#NG   }" ;; esac
done < "$REFLIST"
[[ "$(wc -l < "$REFLIST" | tr -d " ")" -ge 3 ]]
check $? "skill: 参照を3件以上拾えている（grep の空振りで素通りしていない）"
: > "$REFLIST"
# バッククォートで囲まれたリポジトリ内パス
grep -rhoE '`[A-Za-z0-9_-]+/[A-Za-z0-9_./-]+\.(md|sh|json)`' CLAUDE.md README.md skills agents 2>/dev/null \
  | tr -d '`' | sort -u | while read -r p; do
    [[ -e "$p" ]] && echo "ok   $p" || echo "NG   $p が無い"
  done > "$REFLIST"
while read -r line; do
  case "$line" in ok*) ok "参照: ${line#ok   }" ;; *) ng "参照: ${line#NG   }" ;; esac
done < "$REFLIST"
[[ "$(wc -l < "$REFLIST" | tr -d " ")" -ge 2 ]]
check $? "パス参照を2件以上拾えている（grep の空振りで素通りしていない）"

rm -f "$REFLIST"

section "6. 隔離した HOME で install.sh（2回流す）"
FAKE_HOME="$(mktemp -d)"
trap 'rm -rf "$FAKE_HOME" "${DUMMY_REPO:-}"' EXIT
mkdir -p "$FAKE_HOME/.claude"
cat > "$FAKE_HOME/.claude/settings.json" <<'JSON'
{
  "model": "opus[1m]",
  "permissions": {
    "additionalDirectories": ["/somewhere/doc-storage"],
    "deny": ["Bash(pre-existing *)", "Edit(~/old-place/*/human-doc/**)"]
  },
  "hooks": {
    "SessionStart": [{"hooks": [{"type": "command", "command": "orca-session-start"}]}],
    "Stop": [{"hooks": [
      {"type": "command", "command": "orca-stop"},
      {"type": "command", "command": "$HOME/.claude/hooks/verify-gate.sh"}
    ]}]
  }
}
JSON

HOME="$FAKE_HOME" bash ./install.sh > "$FAKE_HOME/install1.log" 2>&1
check $? "1回目の install.sh が成功" "$(tail -3 "$FAKE_HOME/install1.log")"
HOME="$FAKE_HOME" bash ./install.sh > "$FAKE_HOME/install2.log" 2>&1
check $? "2回目の install.sh が成功" "$(tail -3 "$FAKE_HOME/install2.log")"

S="$FAKE_HOME/.claude/settings.json"
jq empty "$S" 2>/dev/null; check $? "settings.json が有効な JSON のまま"

for l in CLAUDE.md agents/advisor.md agents/plan-reviewer.md agents/test-runner.md \
         agents/doc-writer.md skills/feature skills/spec skills/harness-review \
         skills/doc skills/doc-init skills/doc-storage skills/plan-review \
         hooks/verify-gate.sh; do
  [[ -L "$FAKE_HOME/.claude/$l" && -e "$FAKE_HOME/.claude/$l" ]]
  check $? "リンク: ~/.claude/$l"
done
[[ -x "$FAKE_HOME/.claude/hooks/verify-gate.sh" ]]
check $? "~/.claude/hooks/verify-gate.sh が実行可能"

# 既存の設定を壊していない
[[ "$(jq -r '.model' "$S")" == "opus[1m]" ]]
check $? "model を書き換えていない"
[[ "$(jq -r '.permissions.additionalDirectories[0]' "$S")" == "/somewhere/doc-storage" ]]
check $? "additionalDirectories が残っている"
jq -e '.hooks.SessionStart[0].hooks[0].command == "orca-session-start"' "$S" >/dev/null 2>&1
check $? "既存の SessionStart hook が残っている"
jq -r '.hooks.Stop[].hooks[].command' "$S" | grep -q '^orca-stop$'
check $? "既存の Stop hook が残っている"
jq -r '.permissions.deny[]' "$S" | grep -q 'pre-existing'
check $? "既存の deny が残っている"

# harness 由来の設定が入っている
[[ "$(jq -r '.permissions.deny | length' "$S")" == 7 ]]
check $? "deny が 1(既存) + 6(harness) = 7 件" "実際: $(jq -c '.permissions.deny' "$S")"
jq -r '.permissions.deny[]' "$S" | grep -q 'old-place'
[[ $? != 0 ]]
check $? "ハーネス由来の古い human-doc ルールを外している"
[[ "$(jq -r '.permissions.deny[]' "$S" | grep -c '<DOC_STORAGE_ROOT>')" == 0 ]]
check $? "deny にプレースホルダが残っていない"
jq -r '.permissions.deny[]' "$S" | grep -q 'human-doc'
check $? "human-doc の deny が入っている"
[[ "$(jq -r '.hooks.Stop[].hooks[].command' "$S" | grep -c verify-gate.sh)" == 1 ]]
check $? "verify-gate.sh の Stop hook が1つだけ（冪等）" "実際: $(jq -r '.hooks.Stop[].hooks[].command' "$S" | grep -c verify-gate.sh)"
[[ "$(jq -r '.hooks.Stop | length' "$S")" == 2 ]]
check $? "Stop hook は既存1 + harness1 = 2 件"
# 同じグループに verify-gate と同居していた hook を巻き込んで消していないこと
jq -e '[.hooks.Stop[] | select(.hooks != null) | .hooks[].command] | index("orca-stop")' "$S" >/dev/null 2>&1
check $? "verify-gate と同居していた既存 hook を巻き込んでいない"
ls "$FAKE_HOME/.claude/"settings.json.bak.* >/dev/null 2>&1
check $? "settings.json を退避している"
[[ "$(ls -1 "$FAKE_HOME/.claude/"settings.json.bak.* 2>/dev/null | wc -l | tr -d ' ')" == 1 ]]
check $? "2回流しても退避は1つだけ（変更が無ければ書かない）"
grep -q '変更なし' "$FAKE_HOME/install2.log"
check $? "2回目は settings.json を書き換えない"

# 壊れた settings.json では書き換えずに止まる
BAD_HOME="$(mktemp -d)"
mkdir -p "$BAD_HOME/.claude"
printf '{"permissions": {"deny": 123}}' > "$BAD_HOME/.claude/settings.json"
HOME="$BAD_HOME" bash ./install.sh >/dev/null 2>&1
[[ $? != 0 ]]
check $? "deny が壊れた settings.json では exit 1"
[[ "$(cat "$BAD_HOME/.claude/settings.json")" == '{"permissions": {"deny": 123}}' ]]
check $? "失敗時に settings.json を書き換えていない"
printf '[]' > "$BAD_HOME/.claude/settings.json"
HOME="$BAD_HOME" bash ./install.sh >/dev/null 2>&1
[[ $? != 0 ]]
check $? "settings.json が配列なら exit 1"
rm -rf "$BAD_HOME"

section "7. verify-gate.sh の挙動"
DUMMY_REPO="$(mktemp -d)"
mkdir -p "$DUMMY_REPO/.claude"

run_gate() { # $1=stop_hook_active $2=repo
  printf '{"hook_event_name":"Stop","stop_hook_active":%s,"cwd":"%s"}' "$1" "$2" \
    | CLAUDE_PROJECT_DIR="$2" bash hooks/verify-gate.sh 2>"$DUMMY_REPO/stderr.log"
  echo $?
}

# verify-fast.sh が無いリポジトリ
[[ "$(run_gate false "$DUMMY_REPO")" == 0 ]]
check $? "verify-fast.sh が無ければ exit 0"

# 必ず落ちる verify-fast.sh
cat > "$DUMMY_REPO/.claude/verify-fast.sh" <<'X'
#!/usr/bin/env bash
echo "INTENTIONAL FAILURE MARKER"
exit 1
X
chmod +x "$DUMMY_REPO/.claude/verify-fast.sh"

[[ "$(run_gate false "$DUMMY_REPO")" == 2 ]]
check $? "落ちる verify-fast.sh で exit 2"
grep -q 'INTENTIONAL FAILURE MARKER' "$DUMMY_REPO/stderr.log"
check $? "失敗出力を stderr に出している"
[[ "$(run_gate true "$DUMMY_REPO")" == 0 ]]
check $? "stop_hook_active:true なら差し戻さない（exit 0）"

# CLAUDE_PROJECT_DIR が無くても payload の cwd を見る
printf '{"hook_event_name":"Stop","stop_hook_active":false,"cwd":"%s"}' "$DUMMY_REPO" \
  | env -u CLAUDE_PROJECT_DIR bash hooks/verify-gate.sh >/dev/null 2>&1
[[ $? == 2 ]]
check $? "CLAUDE_PROJECT_DIR が無ければ payload の cwd を使う"

# 通る verify-fast.sh
cat > "$DUMMY_REPO/.claude/verify-fast.sh" <<'X'
#!/usr/bin/env bash
exit 0
X
chmod +x "$DUMMY_REPO/.claude/verify-fast.sh"
[[ "$(run_gate false "$DUMMY_REPO")" == 0 ]]
check $? "通る verify-fast.sh で exit 0"

# 実行ビットが無ければ何もしない
chmod -x "$DUMMY_REPO/.claude/verify-fast.sh"
[[ "$(run_gate false "$DUMMY_REPO")" == 0 ]]
check $? "実行ビットが無ければ exit 0"

printf '\n----\n合格 %d / 失敗 %d\n' "$PASS" "$FAIL"
[[ "$FAIL" == 0 ]] || exit 1
