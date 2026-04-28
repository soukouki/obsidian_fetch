# ObsidianFetch

> Languages: [English version](README.md)

ObsidianのVaultから必要な情報をサクッと取得するためのMCPサーバーです。

## 概要

既存のMCPサーバーを使っていると、こんな悩みはありませんでしたか？

- コマンドが多すぎて、ローカルLLMだと読み込みに時間がかかる
- 特定のノートを探してほしいのに、LLMがうまくパスを辿ってくれない
- ツール設定が複雑で、LLMが正しく呼び出せない

特にローカルGPUでLLMを動かしている場合、これらの問題がボトルネックになります。

そこで、「ノートのリスト取得」と「中身の読み込み」というシンプルな機能に特化したサーバーを開発しました。

さらに、使い勝手を良くするために以下の機能を追加しています：

- **リンクの自動修正**: `[[リンク名]]` のように括弧付きで検索したとき、不要な文字を自動で消して正しくリンクを解決します。
- **バックリンク対応**: ノートの中身だけでなく、「どのノートから参照されているか」というバックリンクも一緒に取得します。これでLLMが知識のつながりをより正確に把握できます。

## インストール

```bash
gem install obsidian_fetch
```

## 使用方法

### Stdio Transport（デフォルト）

```bash
obsidian_fetch /path/to/your/vault
```

### Streamable HTTP Transport

HTTPサーバーとして実行する場合は、以下のコマンドを使用します。

```bash
obsidian_fetch /path/to/your/vault --transport streamable-http
```

デフォルトでは `http://localhost:9292` で接続できます。ポート番号は以下のようにカスタマイズ可能です。

```bash
obsidian_fetch /path/to/your/vault --transport streamable-http --port 3000
```

## ツール

- **read**: Obsidian Vaultからノートを取得します。同名のノートが複数存在する場合、すべて取得します。
- **list**: ファイル名で検索します。部分一致での検索が可能です。

## 貢献

バグ報告やプルリクエストは、GitHubリポジトリ（https://github.com/soukouki/obsidian_fetch）にてお待ちしております。

## ライセンス

このジェムは [MITライセンス](https://opensource.org/licenses/MIT) の下で公開されています。
