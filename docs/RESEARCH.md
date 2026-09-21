# 調査ログと出典

調査日: 2026-09-21。「どこの世の中の仕組みを使って実装したか」の出典一覧。
**確認の深さを区別して記載する。** 「実機で確認」は本リポジトリの環境で実際に動かして確認したもの、「文書を取得」はページを取得して内容を要約させたもの（一次資料の全文精読ではない）、「検索結果のみ」は検索結果の題名・要約を見ただけで本文は読んでいないもの。

## 採用した仕組み

| 何に使ったか | 出典 | 確認の深さ |
|---|---|---|
| llama.cpp server（推論、`--parallel`、`--cont-batching`、`--kv-unified`、`--metrics`、`--alias`、バッチサイズ） | https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md | 文書を取得 + **実機で確認**（`docker run ... --help` の出力、起動ログ、`/metrics`） |
| 連続バッチングの解説 | https://github.com/ggml-org/llama.cpp/discussions/4130 | 検索結果のみ |
| LiteLLM Proxy（ゲートウェイ、MIT） | https://github.com/BerriAI/litellm / https://docs.litellm.ai/docs/simple_proxy | 文書を取得 + **実機で確認**（キー発行、上限、予算、UI、メトリクス） |
| 仮想キーごとの `rpm_limit` / `tpm_limit` / `max_parallel_requests` / `max_budget` | https://docs.litellm.ai/docs/proxy/users | 文書を取得 + **実機で確認**（RESULTS §3〜4） |
| config.yaml（`openai/` 接頭辞、`api_base`、`master_key`、`database_url`） | https://docs.litellm.ai/docs/proxy/configs | 文書を取得 + **実機で確認** |
| 仮想キーに PostgreSQL が必要 | https://docs.litellm.ai/docs/proxy/virtual_keys / https://docs.litellm.ai/docs/proxy/db_info | 検索結果のみ（Postgres で動作することは実機で確認） |
| Prometheus メトリクスは無償 OSS 機能 | https://docs.litellm.ai/docs/proxy/prometheus | 文書を取得 + **実機で確認**（`/metrics` が取得できた） |
| `llm` CLI で自前エンドポイントを使う設定 | https://llm.datasette.io/en/stable/other-models.html | 文書を取得 + **実機で確認**（one-shot / パイプ / chat） |
| モデル Qwen2.5-1.5B-Instruct GGUF | https://huggingface.co/bartowski/Qwen2.5-1.5B-Instruct-GGUF | **実機で確認**（ダウンロードして推論。941MB） |
| Docker イメージ | `ghcr.io/ggml-org/llama.cpp:server`、`ghcr.io/berriai/litellm:main-stable`、`postgres:16-alpine` | **実機で確認**（pull して起動） |

## 検討したが採用しなかったもの

| 何か | 出典 | 確認の深さと注意 |
|---|---|---|
| llm-d flow control（優先度バンド + テナント間ラウンドロビン + テナント内FCFS。将来の移行先候補） | https://developers.redhat.com/articles/2026/08/27/llm-d-flow-control-priority-queuing-for-shared-gpu-inference | 文書を取得。**記事は Kubernetes 必須かを明記しておらず、単機での利用可否にも触れていない**。「k8s + GPU 前提で規模が合わない」は私の推測 |
| Envoy AI Gateway（usage-based rate limiting） | https://aigateway.envoyproxy.io/docs/0.1/capabilities/usage-based-ratelimiting/ | 検索結果のみ。詳細ページの取得は別ドメインへのリダイレクトで実施していない |
| Kong AI Gateway（AI Rate Limiting Advanced） | https://developer.konghq.com/plugins/ai-rate-limiting-advanced/ | 検索結果のみ |
| 「公平キューは LiteLLM に無い」 | https://docs.litellm.ai/docs/proxy/users | 文書を取得。**「ドキュメントに記載が無い」ことの確認であり、機能が無いことの確認ではない**。ただし本リポジトリの実測でも、上限超過は待機ではなく 429 になった |
| Redis によるキュー（LiteLLM） | 検索結果内の記述 | 検索結果のみ |

## 既知の不具合（回避策の根拠）

- LiteLLM `max_parallel_requests` × Redis の不具合報告: https://github.com/BerriAI/litellm/issues/17323 — **検索結果の題名のみ、本文は未読**（ADR-005）

## 調査時点の記述で、実測により訂正したもの

| 当初の記述 | 実際 | 根拠 |
|---|---|---|
| 連続バッチングにより同時数を増やすと合計スループットが伸びる | 伸びなかった（約 21〜28 tok/s で一定） | RESULTS §1 |
| ゲートウェイの上限は異常時のバックストップ | 占有防止に必須 | RESULTS §2 |
| 統合 KV キャッシュが既定 | スロット数が auto のときのみ。明示指定した | `--help`、起動ログ |
| モデルは約 1.1GB | 941MB | 実ファイル |
| `llm` は 429 を自動リトライしない | 少なくとも 1 条件では自動的に待って成功した | RESULTS §6 |
| 429 が稀になる想定 | 上限を超えた重いユーザーは 18/20 が 429 になる | RESULTS §2 |

## 実装中に見つかった落とし穴

- llama.cpp の引数は `--flag=value` 形式を受け付けず、さらに引数中の `_` を `-` に書き換える（`Q4_K_M` が壊れて起動失敗）。`--flag value` の別要素で渡す。
- LiteLLM の `os.environ/` 記法は値全体にのみ効き、`openai/os.environ/X` のような文字列の一部には効かない。
- `pkill -f` はパターン文字列を含む自分自身のシェルにも一致して自爆しうる。
