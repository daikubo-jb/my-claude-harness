---
name: doc-storage
description: dev配下プロジェクトのドキュメント配置規約。ドキュメントを作成・更新・検索するとき、doc-writer を使うとき、過去の設計判断や調査結果を探すときに読む。
---

# doc-storage 配置規約

すべてのプロジェクトドキュメントは `~/dev/doc-storage/` 以下に置く。
プロジェクトのリポジトリ内には置かない（README や API ドキュメントなど、
リポジトリに同梱すべきものは除く）。

## 構成

```
~/dev/doc-storage/<プロジェクト名>/
├── index.md          ハブ。全ドキュメントへの wikilink を並べる
├── claude-doc/       Claude が書く
│   ├── plans/        実装プランと plan-reviewer の指摘
│   ├── reviews/      レビュー記録
│   ├── research/     調査メモ
│   ├── worklog/      日付ごとの作業記録・進捗
│   └── decisions/    設計判断の記録
└── human-doc/        人間が書く
```

`<プロジェクト名>` は作業ディレクトリの basename（例: `~/dev/my-project` → `my-project`）。

## 対象外のプロジェクト

リポジトリ内でドキュメントを管理する慣習のプロジェクト（OSS への貢献など）は
doc-storage に枠を作らない。作業記録もリポジトリ側の慣習に従う。
判断はそのプロジェクトの `CLAUDE.md` / `AGENTS.md` の記述に従う。

## 書き込みのルール

- `claude-doc/` 以下は自由に作成・更新してよい
- `human-doc/` は読むだけ。明示的に指示された時だけ書き込む
- 同じ話題のドキュメントが既にあれば、新規作成せず更新する

## ファイル名

- `plans/`, `reviews/`, `research/`: `YYYY-MM-DD-<slug>.md`
- `decisions/`: `NNNN-<slug>.md`（連番）

## 書式

doc-storage は Obsidian の vault なので、内部リンクは `[[ファイル名]]` を使う。

各ファイルの先頭に frontmatter を置く:

```markdown
---
date: 2026-07-27
tags: [実装, 認証]
---

# タイトル

（1〜2文の要約。ここだけ読めば何の話か分かるように）
```

新規ファイルを作ったら `index.md` にリンクを追加する。

## 読むとき

過去の経緯・設計判断・調査結果を探すときは、まず該当プロジェクトの
`index.md` を読み、そこから辿る。ディレクトリを総なめしない。
