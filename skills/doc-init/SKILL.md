---
name: doc-init
description: 現在のプロジェクト用のドキュメント枠を doc-storage に作成する
disable-model-invocation: true
---

現在の作業ディレクトリの basename をプロジェクト名として、
doc-storage の配置ルート直下に規約どおりの構造を作る。
ルートは `skill: doc-storage` を読んで確かめる。

```
index.md
claude-doc/{plans,reviews,research,worklog,decisions}/
human-doc/
```

既にあるディレクトリは作り直さない。
対象外のプロジェクト（`skill: doc-storage` 参照）では作成せず、その旨を報告する。

`index.md` が無ければ作る。プロジェクトの README と CLAUDE.md を読んで、
1〜2文の概要と空のリンク節（実装プラン / レビュー / 調査 / 設計判断）を置く。

作成したパスを報告する。
