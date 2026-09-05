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
- 記録先の種別（plans / reviews / research / decisions のどれか）

要約は自分で書いて渡す。`doc-writer` に差分から読み解かせない。
