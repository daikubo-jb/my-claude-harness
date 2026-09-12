---
name: doc
description: 直近の作業を doc-storage に記録する
argument-hint: "[記録する話題]"
disable-model-invocation: true
---

$ARGUMENTS

`doc-writer` を使って直近の作業を doc-storage に記録する。

渡すもの:

- 何を・なぜ・どう変えたか（2〜5行の要約）
- 関連するプランやレビュー結果のパス
- 記録先の種別（plans / reviews / research / worklog / decisions のどれか）
- **ハーネスへの示唆** — 次の3点。無ければ「なし」と書く
  - 効かなかった指示（CLAUDE.md やスキルに書いてあるのに守られなかったもの）
  - hook が止めた回数と内容
  - `advisor` / `plan-reviewer` の指摘を採用したか、しなかったならなぜか

事故が起きたセッションでは「ハーネスへの示唆」を必ず書く。
ここに溜めたものが `skill: harness-review` の唯一の入力になる。

要約は自分で書いて渡す。`doc-writer` に差分から読み解かせない。
