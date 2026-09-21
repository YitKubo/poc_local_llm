# server — ローカル LLM サーバ

llama.cpp（推論）+ LiteLLM Proxy（認証・上限・使用量）+ PostgreSQL を docker compose で動かす。**このディレクトリだけで完結**し、`client/` には依存しない。以降のコマンドはすべて `server/` で実行する。

```
[クライアント] --Bearer 仮想キー--> [LiteLLM Proxy :4000] --内部ネットワーク--> [llama.cpp server]
                                      キー別の上限 / 使用量 / UI / metrics        連続バッチング --parallel 4
                                            └ [PostgreSQL]                        ホストへ非公開
```

llama.cpp は「誰が投げたか」を区別できないため、**LiteLLM を唯一の入口**にしている（llama.cpp はホストに公開しない）。設計判断と根拠は [../docs/DECISIONS.md](../docs/DECISIONS.md)、実測値は [../docs/RESULTS.md](../docs/RESULTS.md)、出典は [../docs/RESEARCH.md](../docs/RESEARCH.md)。

## 起動

```bash
cd server
cp .env.example .env         # CHANGE_ME を置換する（例: openssl rand -hex 24。LITELLM_MASTER_KEY は sk- で始める）
./scripts/fetch_model.sh     # GGUF を models/ に取得（約 0.94GB）
docker compose up -d
curl http://127.0.0.1:4000/health/liveliness   # 200 なら OK（初回は 30 秒ほどかかる）
```

## ユーザーへ渡すもの

ユーザーごとの仮想キーを発行する（キーは一度だけ表示されるので控える）:

```bash
./scripts/create_keys.sh alice bob carol
```

各ユーザーには次の 3 つを渡す。**これがサーバとクライアントの間の取り決めのすべて**で、クライアント側の手順は [../client/README.md](../client/README.md)。

| 渡すもの | 値 | 決めている場所 |
|---|---|---|
| サーバの URL | `http://<このマシンのホスト>:4000` | `docker-compose.yml` の `litellm.ports` |
| 仮想キー | `create_keys.sh` の出力（`sk-...`） | LiteLLM が発行 |
| モデル名 | `local-qwen` | `litellm_config.yaml` の `model_name` |

- 他のマシンから届くかは**未検証**（試験はすべてこの PC の内側から。WSL2 ではポート転送やファイアウォールの設定が要ることがある）。
- キー別の上限は `.env` の `MAX_PARALLEL_REQUESTS` / `RPM_LIMIT` / `TPM_LIMIT` / `DAILY_BUDGET` が使われる。
- 管理 UI は `http://<host>:4000/ui/`（ログインは公式ドキュメント上「ユーザー名 `admin`、パスワードは `LITELLM_MASTER_KEY`」。本リポジトリでは `/ui/` が 200 で応答することまでしか確認していない）。
- メトリクスは `curl -L -H "Authorization: Bearer $LITELLM_MASTER_KEY" http://127.0.0.1:4000/metrics`。

## 挙動として知っておくこと

- **1 人あたりの同時実行は 2 本まで**（`MAX_PARALLEL_REQUESTS`）。超えた分は待機ではなく 429 で拒否される。
- **この CPU では合計スループットは 25〜30 tok/s で頭打ち**（同時数を増やしても増えない）。人数が増えると 1 人あたりの速度がほぼ 1/N で落ちる。4 スロット満員（4 人同時）で 1 人あたり約 7.6 tok/s。スロット（4）を超える同時数では超過分が待つ（3 人以上が 2 本ずつ投げたときに起きる。[RESULTS §1b](../docs/RESULTS.md)）。
- 1 本だけ流したときの速度は測るたびに 17〜28 tok/s と揺れる（WSL2 上の単発計測）。
- 日次予算（`DAILY_BUDGET`）は超過の検知が遅延するため、厳密な上限ではない。
- 公平な順番待ち行列は無い（LiteLLM を含む既存ゲートウェイの仕様）。必要になれば [llm-d flow control](https://developers.redhat.com/articles/2026/08/27/llm-d-flow-control-priority-queuing-for-shared-gpu-inference) が候補（Kubernetes + GPU 前提かは未確認）。

## 負荷試験

```bash
# 同時数を振る（llama.cpp を直接測る。ループバックだけに公開するオーバーレイを使う）
docker compose -f docker-compose.yml -f docker-compose.debug.yml up -d llama
set -a; . ./.env; set +a
scripts/loadtest.py sweep --url http://127.0.0.1:8081 --key "$LLAMA_API_KEY" \
    --model Qwen2.5-1.5B-Instruct --levels 1,2,4,8,12
docker compose up -d llama     # 元の非公開構成へ戻す

# 占有の検証（重いユーザー 20 本 + 別ユーザー 1 本）
scripts/loadtest.py fairness --url http://127.0.0.1:4000 --model local-qwen \
    --heavy-key sk-<alice> --light-key sk-<bob>
```

`scripts/loadtest.py` は標準ライブラリのみの単一ファイルで、リポジトリの他の部分に依存しない。別マシンにコピーして、そのマシンから `fairness` を打つこともできる。

## ファイル

| ファイル | 内容 |
|---|---|
| `docker-compose.yml` | llama.cpp / LiteLLM / PostgreSQL の 3 サービス（プロジェクト名 `local-llm` 固定。DB のボリュームはこの名前に紐づく） |
| `docker-compose.debug.yml` | 計測用。llama.cpp をホストのループバックのみに公開（通常運用では使わない） |
| `litellm_config.yaml` | モデル定義、名目単価、Prometheus 有効化 |
| `.env.example` | スロット数・スレッド数・上限・秘密情報（`.env` は gitignore 済み） |
| `models/` | GGUF の置き場（gitignore 済み） |
| `scripts/fetch_model.sh` | モデルの取得（再開可能） |
| `scripts/create_keys.sh` | 仮想キーの発行（`.env` の上限を付与） |
| `scripts/loadtest.py` | 負荷試験 |

## 設定を変えるとき

- `LLAMA_PARALLEL`（スロット数）は容量を増やさず、**容量の分け方**を決める。`MAX_PARALLEL_REQUESTS` は必ずこれより小さくする。
- モデルを変えるなら `.env` の `MODEL_FILE` / `MODEL_URL` / `MODEL_ALIAS` と、`litellm_config.yaml` の `openai/<MODEL_ALIAS>` を一致させる（LiteLLM の設定は環境変数を文字列の一部に展開できないため固定値）。
- クライアントに見せるモデル名（`litellm_config.yaml` の `model_name`）を変えたら、`create_keys.sh` の `GATEWAY_MODEL`（既定 `local-qwen`）と、各クライアントの `CLIENT_MODEL` も変える。
- llama.cpp のフラグは `--flag value` の別要素で渡す（`--flag=value` は不可）。`--threads` は物理コア数程度に。全スレッド（12）にすると大幅に遅くなる。
- **`docker-compose.yml` を別の場所へ移すときは `name: local-llm` を残すこと。** プロジェクト名が変わると DB のボリュームが別物になり、発行済みのキーと使用量が見えなくなる。

## 設定時に参照するドキュメント

何を設定するときにどの公式ドキュメントを見ればよいか。調査の経緯と確認の深さは [../docs/RESEARCH.md](../docs/RESEARCH.md)、採用理由は [../docs/DECISIONS.md](../docs/DECISIONS.md) にある。

| 設定したいこと | 設定する場所 | 参照先 |
|---|---|---|
| llama.cpp のフラグ（`--parallel` / `--ctx-size` / `--threads` / `--kv-unified` / `--metrics` / `--alias`） | `docker-compose.yml` の `llama.command`、`.env` | [llama.cpp server README](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md)。使っているビルドの実際のフラグは `docker run --rm ghcr.io/ggml-org/llama.cpp:server --help` で確認する |
| 連続バッチングの仕組み | — | [llama.cpp Discussion #4130](https://github.com/ggml-org/llama.cpp/discussions/4130) |
| LiteLLM の設定ファイル（`model_list` / `api_base` / `master_key` / `database_url` / `os.environ/`） | `litellm_config.yaml` | [LiteLLM config.yaml](https://docs.litellm.ai/docs/proxy/configs)、[Proxy 概要](https://docs.litellm.ai/docs/simple_proxy) |
| 仮想キーの発行と管理 | `scripts/create_keys.sh`（`/key/generate`） | [Virtual Keys](https://docs.litellm.ai/docs/proxy/virtual_keys) |
| キー別の上限（`max_parallel_requests` / `rpm_limit` / `tpm_limit` / `max_budget` / `budget_duration`） | `.env`、`scripts/create_keys.sh` | [Budgets, Rate Limits](https://docs.litellm.ai/docs/proxy/users) |
| PostgreSQL に保存される内容 | `docker-compose.yml` の `postgres` | [DB に保存される情報](https://docs.litellm.ai/docs/proxy/db_info) |
| Prometheus メトリクス（`/metrics`） | `litellm_config.yaml` の `callbacks` | [LiteLLM Prometheus](https://docs.litellm.ai/docs/proxy/prometheus) |
| モデルの入手・差し替え | `.env` の `MODEL_FILE` / `MODEL_URL` / `MODEL_ALIAS` | [bartowski/Qwen2.5-1.5B-Instruct-GGUF](https://huggingface.co/bartowski/Qwen2.5-1.5B-Instruct-GGUF) |
| 将来、公平キューが必要になったとき | — | [llm-d flow control](https://developers.redhat.com/articles/2026/08/27/llm-d-flow-control-priority-queuing-for-shared-gpu-inference)（未採用。詳細は RESEARCH.md） |

使用イメージ: `ghcr.io/ggml-org/llama.cpp:server`、`ghcr.io/berriai/litellm:main-stable`、`postgres:16-alpine`。`main-stable` は更新されうるので、フラグや設定項目が変わっていたら上記ドキュメントと `--help` を優先する。
