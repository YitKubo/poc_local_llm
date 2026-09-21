# poc_local_llm

GPU なしの端末で動かす、検証用のローカル LLM サーバ + CLI クライアント。
**複数人が同時に使っても、1 人が占有しない**ことを実測で確かめるための構成。独自のアプリケーションコードは無く、既製の OSS を設定で組み合わせている。

```
[llm CLI]  --Bearer 仮想キー-->  [LiteLLM Proxy :4000]  --内部ネットワーク-->  [llama.cpp server]
 各ユーザーの端末                 キー別の上限 / 使用量 / UI / metrics          連続バッチング --parallel 4
                                         └ [PostgreSQL]                         ホストへ非公開
```

- llama.cpp は「誰が投げたか」を区別できないため、**LiteLLM を唯一の入口**にしている（llama.cpp はホストに公開しない）。
- 設計判断と根拠: [docs/DECISIONS.md](docs/DECISIONS.md) ／ 実測値: [docs/RESULTS.md](docs/RESULTS.md) ／ 出典: [docs/RESEARCH.md](docs/RESEARCH.md)

## サーバの起動

```bash
cp .env.example .env         # CHANGE_ME を置換する（例: openssl rand -hex 24。LITELLM_MASTER_KEY は sk- で始める）
./scripts/fetch_model.sh     # GGUF を models/ に取得（約 0.94GB）
docker compose up -d
curl http://127.0.0.1:4000/health/liveliness   # 200 なら OK（初回は 30 秒ほどかかる）
```

ユーザーごとの仮想キーを発行（キーは一度だけ表示されるので控える）:

```bash
./scripts/create_keys.sh alice bob carol
```

キー別の上限は `.env` の `MAX_PARALLEL_REQUESTS` / `RPM_LIMIT` / `TPM_LIMIT` / `DAILY_BUDGET` が使われる。管理 UI は `http://<host>:4000/ui/`（ログインは公式ドキュメント上「ユーザー名 `admin`、パスワードは `LITELLM_MASTER_KEY`」。本リポジトリでは `/ui/` が 200 で応答することまでしか確認していない）。

## クライアントの導入（各ユーザーの端末）

```bash
./scripts/setup_client.sh http://<サーバのホスト>:4000 sk-<自分の仮想キー>
llm "こんにちは"       # 一発実行
llm chat               # 対話（ストリーミング表示）
cat file.txt | llm -s "要約して"
```

[`llm`](https://llm.datasette.io) を導入して接続先を登録するだけ。`pipx` があればそれを使い、無ければ `~/.local/share/llm-venv` にフォールバックする（`~/.local/bin` を PATH に通すこと）。

## 挙動として知っておくこと

- **1 人あたりの同時実行は 2 本まで**（`MAX_PARALLEL_REQUESTS`）。超えた分は待機ではなく 429 で拒否される。`llm` は、1 回の検証ではこの 429 を自動で待ち直して吸収した（63 秒後に成功）。再現性や、長く占有され続けた場合の最終挙動は未検証。
- **この CPU では合計スループットは 25〜30 tok/s で頭打ち**（同時数を増やしても増えない）。人数が増えると 1 人あたりの速度がほぼ 1/N で落ちる。4 スロット満員（4 人同時）で 1 人あたり約 7.6 tok/s。スロット（4）を超える同時数では超過分が待つ（3 人以上が 2 本ずつ投げたときに起きる。[RESULTS §1b](docs/RESULTS.md)）。
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

## 構成ファイル

| ファイル | 内容 |
|---|---|
| `docker-compose.yml` | llama.cpp / LiteLLM / PostgreSQL の 3 サービス |
| `docker-compose.debug.yml` | 計測用。llama.cpp をホストのループバックのみに公開（通常運用では使わない） |
| `litellm_config.yaml` | モデル定義、名目単価、Prometheus 有効化 |
| `.env.example` | スロット数・スレッド数・上限・秘密情報（`.env` は gitignore 済み） |
| `scripts/` | `fetch_model.sh` / `create_keys.sh` / `setup_client.sh` / `loadtest.py` |

## 設定を変えるとき

- `LLAMA_PARALLEL`（スロット数）は容量を増やさず、**容量の分け方**を決める。`MAX_PARALLEL_REQUESTS` は必ずこれより小さくする。
- モデルを変えるなら `.env` の `MODEL_FILE` / `MODEL_URL` / `MODEL_ALIAS` と、`litellm_config.yaml` の `openai/<MODEL_ALIAS>` を一致させる（LiteLLM の設定は環境変数を文字列の一部に展開できないため固定値）。
- llama.cpp のフラグは `--flag value` の別要素で渡す（`--flag=value` は不可）。`--threads` は物理コア数程度に。全スレッド（12）にすると大幅に遅くなる。
