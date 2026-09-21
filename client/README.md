# client — CLI クライアント

[`llm`](https://llm.datasette.io)（Simon Willison 製の既製 CLI）を導入し、サーバに接続する設定を書くだけ。**このディレクトリだけで完結**し、`server/` のファイルは何も使わない。サーバ側の手順は [../server/README.md](../server/README.md)。

## 必要なもの

サーバの管理者から次の 3 つを受け取る。

| 受け取るもの | 例 |
|---|---|
| サーバの URL | `http://<サーバのホスト>:4000` |
| 自分用の仮想キー | `sk-...` |
| モデル名 | `local-qwen`（既定。変わっていたら管理者に確認） |

必要な環境: Python 3、`pipx`（無くてもよい）、サーバへ HTTP で到達できること。

## 導入

```bash
./install.sh http://<サーバのホスト>:4000 sk-<自分の仮想キー>
```

環境変数でも渡せる: `LLM_SERVER_URL=... LLM_SERVER_KEY=... ./install.sh`。モデル名が既定と違うときは `CLIENT_MODEL=<名前> ./install.sh ...`。

やること:
1. `llm` が無ければ導入する。`pipx` があればそれを使い、無ければ `~/.local/share/llm-venv` に専用 venv を作って `~/.local/bin/llm` にリンクする（`~/.local/bin` を PATH に通すこと）。
2. 接続先を `~/.config/io.datasette.llm/extra-openai-models.yaml` に書く。
3. 仮想キーを `llm keys` に保存し、`llm models default local` で既定モデルにする。

## 使い方

```bash
llm "こんにちは"                     # 一発実行
llm chat                             # 対話（ストリーミング表示）
cat file.txt | llm -s "要約して"     # パイプ
llm -o max_tokens 100 "短く答えて"   # 出力の長さを制限
llm logs                             # 過去のやり取り（ローカルの SQLite）
```

## スクリプトを使わずに設定する

`install.sh` がやっているのは次の 3 つだけ。手で行ってもよい。

### 1. `llm` を入れる

```bash
pipx install llm        # または pip install llm
```

`llm` は、コマンドラインから LLM に話しかける既製の CLI（PyPI のパッケージ名も `llm`）。どちらのコマンドも、これを入れているだけ。

- **`pipx install llm`**: Python 製のコマンド（アプリ）を、他と混ざらない専用の仮想環境に入れ、`llm` コマンドを PATH に通す。`pipx` 自体が無ければ、別途入れる必要がある。
- **`pip install llm`**: いま使っている Python 環境にそのまま入れる。Debian / Ubuntu では `error: externally-managed-environment` で拒否されることがある。その場合は `pipx` を使うか、`python3 -m venv` で専用の環境を作ってから入れる。

`install.sh` は `pipx` があればそれを使い、無ければ専用 venv（`~/.local/share/llm-venv`）を自動で作る。手で入れるなら、迷ったら `pipx` がよい。

### 2. 接続先を書く

`extra-openai-models.yaml`（置き場は `dirname "$(llm logs path)"`）:

```yaml
- model_id: local
  model_name: local-qwen
  api_base: "http://<サーバのホスト>:4000/v1"
  api_key_name: local-llm
```

### 3. キーと既定モデルを設定する

```bash
llm keys set local-llm       # 仮想キーを貼り付ける
llm models default local
```

`llm` を使わず、OpenAI 互換 API なら他のクライアントからも使える:

```bash
curl http://<サーバのホスト>:4000/v1/chat/completions \
  -H "Authorization: Bearer sk-<自分の仮想キー>" -H "Content-Type: application/json" \
  -d '{"model":"local-qwen","messages":[{"role":"user","content":"こんにちは"}],"max_tokens":50}'
```

## 使うときの注意

- **同時に投げられるのは 2 本まで**（サーバ側の上限）。超えると 429 が返る。`llm` は 1 回の検証では 429 を自動で待ち直して成功した（63 秒後）が、再現性や長時間占有時の最終挙動は未検証。
- 速度は他の利用者の人数に応じて落ちる（サーバ全体で約 25〜30 tok/s を分け合う）。1 人だけなら 17〜28 tok/s 程度で、測るたびに揺れる。
- 日次の使用量に上限がある。超えると拒否されるが、検知は 1 回遅れることがある。
- 上限や速度の実測値は [../docs/RESULTS.md](../docs/RESULTS.md)。

## 削除

```bash
./uninstall.sh           # 接続先の登録・保存した仮想キー・既定モデルの設定だけを消す
./uninstall.sh --purge   # さらに llm 本体とやり取りの履歴 (logs.db) も消す
```

`install.sh` が書いたものだけを消す。`llm` に別のキーや別の既定モデルを設定していれば、それらは残る。`--purge` は、`install.sh` より前から入れていた `llm` も消す（区別できないため）。

なお `install.sh` は、同じ名前で保存済みのキー `local-llm` と既定モデルを上書きする。
