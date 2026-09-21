# poc_local_llm

GPU なしの端末で動かす、検証用のローカル LLM サーバ + CLI クライアント。
**複数人が同時に使っても、1 人が占有しない**ことを実測で確かめるための構成。独自のアプリケーションコードは無く、既製の OSS を設定で組み合わせている。

**サーバとクライアントは完全に分離してあり、互いのファイルを参照しない。** 別々のマシンに置いて使える。

```
 client/ （各ユーザーの端末）                         server/ （このリポジトリを動かす 1 台）
┌──────────────────────────┐                   ┌─────────────────────────────────────────────┐
│ llm CLI                  │  HTTP :4000       │ LiteLLM Proxy ──内部ネットワーク──> llama.cpp │
│  ・接続先 URL            │ ───────────────>  │  キー別の上限 / 使用量   連続バッチング       │
│  ・仮想キー              │  Bearer 仮想キー   │  管理 UI / metrics       --parallel 4        │
│  ・モデル名 local-qwen   │                   │      └ PostgreSQL        ホストへ非公開       │
└──────────────────────────┘                   └─────────────────────────────────────────────┘
```

## ディレクトリ

| ディレクトリ | 役割 | 読むもの |
|---|---|---|
| [`server/`](server/) | サーバ一式（docker compose、設定、モデル、キー発行・負荷試験スクリプト） | [server/README.md](server/README.md) |
| [`client/`](client/) | クライアント導入スクリプトと使い方（`llm` CLI。VS Code Copilot Chat 用の手順は [`client/vscode/`](client/vscode/)） | [client/README.md](client/README.md) |
| [`docs/`](docs/) | 設計判断・実測結果・調査ログ（サーバ/クライアント共通の記録） | 下記 |

## 両者の接点（これ以外に共有するものは無い）

| 項目 | 内容 |
|---|---|
| API | OpenAI 互換 `http://<サーバ>:4000/v1`（HTTP） |
| 認証 | `Authorization: Bearer <仮想キー>`（サーバ管理者が発行） |
| モデル名 | `local-qwen`（サーバの `litellm_config.yaml` の `model_name` と、クライアントの `CLIENT_MODEL` が一致していること） |
| 上限超過 | HTTP 429 が返る |

## 最短手順

```bash
# サーバ側（管理者）
cd server && cp .env.example .env     # CHANGE_ME を置換
./scripts/fetch_model.sh && docker compose up -d
./scripts/create_keys.sh alice        # 出力された sk-... をユーザーへ渡す

# クライアント側（各ユーザー。server/ は不要で、client/ だけあればよい）
cd client && ./install.sh http://<サーバのホスト>:4000 sk-<渡されたキー>
llm "こんにちは"
```

## 記録（docs/）

- [docs/DECISIONS.md](docs/DECISIONS.md) — どの既存の仕組みを採用し、何を却下し、なぜそう判断したか（ADR）。実測で想定が覆った箇所は「訂正」として残している
- [docs/RESULTS.md](docs/RESULTS.md) — 実測値と、未検証のものの一覧
- [docs/VSCODE_SETUP.md](docs/VSCODE_SETUP.md) — VS Code の Copilot Chat に接続したときの設定記録（実際に行った設定、失敗と原因、未確認の一覧、元に戻し方）
- [docs/RESEARCH.md](docs/RESEARCH.md) — 出典 URL と、確認の深さ（実機で確認 / 文書を取得 / 検索結果のみ）
