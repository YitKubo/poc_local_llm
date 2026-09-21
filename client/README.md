# client — CLI クライアント

[`llm`](https://llm.datasette.io)（Simon Willison 製の既製 CLI）を導入し、サーバに接続する設定を書くだけ。**このディレクトリだけで完結**し、`server/` のファイルは何も使わない。サーバ側の手順は [../server/README.md](../server/README.md)。VS Code の GitHub Copilot Chat から使うときは [vscode/README.md](vscode/README.md)。

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
2. 接続先を `~/.config/io.datasette.llm/extra-openai-models.yaml` に書く（ツール呼び出しを使えるよう `supports_tools: true` も入る）。
3. `llm-agent`（次節）と、それが使うシェルツール `agent_tools.py` を入れる。
4. 仮想キーを `llm keys` に保存し、`llm models default local` で既定モデルにする。

## 使い方

```bash
llm "こんにちは"                     # 一発実行
llm chat                             # 対話（ストリーミング表示）
cat file.txt | llm -s "要約して"     # パイプ
llm -o max_tokens 100 "短く答えて"   # 出力の長さを制限
llm logs                             # 過去のやり取り（ローカルの SQLite）
```

## モデルにコマンドを実行させる（llm-agent）

モデルが自分でシェルコマンドを選んで実行し、その結果を見て答える。`install.sh` が入れる `llm-agent` を使う。

```bash
llm-agent                                           # 対話（チャット）。承認モード
llm-agent --auto                                    # 対話。自動モード
llm-agent "uname -r を実行して結果を教えて"          # 一発実行。承認モード（既定）
llm-agent --auto "uname -r を実行して結果を教えて"   # 一発実行。自動モード
```

プロンプトを付けなければ対話になる（`exit` か Ctrl-D で終了）。会話の履歴は保たれるので、前のコマンドの結果を踏まえて続けて頼める。

| モード | 動き | 使いどころ |
|---|---|---|
| 承認モード `--ask`（既定） | モデルが選んだコマンドを表示し、`Approve tool call? [y/N]` と聞く。`y` で実行、`n` で中止 | 普段使い。何が走るか見てから決めたいとき |
| 自動モード `--auto` | 聞かずに全部実行する | 使い捨ての環境や、壊れても困らない作業だけ |

- 対話と、承認モードでの一発実行は、標準入力が端末でないと使えない（聞く相手がいないため）。パイプやスクリプトからは、プロンプトを付けて `--auto` で使う。
- 自動モードは、モデルが出したコマンドがそのまま自分の権限で走る。モデルは小さく（1.5B）、間違ったコマンドや意図しないコマンドを出しうる。**消したくないものがある場所では承認モードを使う。**
- コマンドは 1 回 60 秒で打ち切り、出力は末尾 4000 文字まで。
- 小さいモデルは「コマンドは実行できません」と断ることがある。`llm-agent` は「`run_shell` で実行できる」と伝えるシステムプロンプトを付けて減らしているが、なくなりはしない。断られたら言い直す。
- 実行したツール呼び出しは画面に表示される。モデルの最後の解説には誤りが混ざることがあるので、上のコマンド結果のほうを信用する。
- できるのは `run_shell` の 1 つだけ。増やしたいときは `~/.config/io.datasette.llm/agent_tools.py` に Python 関数を足す（引数の型と 1 行の説明文が要る）。

`llm-agent` は `llm` のツール呼び出し機能（`--functions` / `--tools-approve`）の薄いラッパー。使わずに直接呼ぶなら:

```bash
llm --td --ta --functions ~/.config/io.datasette.llm/agent_tools.py "uname -r を実行して"   # --ta を外すと自動
llm chat --td --ta --functions ~/.config/io.datasette.llm/agent_tools.py                    # 対話
```

## スクリプトを使わずに設定する

`install.sh` がやっているのは次の 3 つ（と `llm-agent` の設置）。手で行ってもよい。`llm-agent` は上の節の直接呼び出しで代用できる。

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
  supports_tools: true       # llm-agent などのツール呼び出しに必要
```

### 3. キーと既定モデルを設定する

```bash
llm keys set local-llm       # 仮想キーを貼り付ける
llm models default local
```

`llm` を使わず、OpenAI 互換 API なら他のクライアントからも使える（VS Code の Copilot Chat への登録は [vscode/README.md](vscode/README.md)）:

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
./uninstall.sh           # 接続先の登録・llm-agent・保存した仮想キー・既定モデルの設定だけを消す
./uninstall.sh --purge   # さらに llm 本体とやり取りの履歴 (logs.db) も消す
```

`install.sh` が書いたものだけを消す。`llm` に別のキーや別の既定モデルを設定していれば、それらは残る。`--purge` は、`install.sh` より前から入れていた `llm` も消す（区別できないため）。

なお `install.sh` は、同じ名前で保存済みのキー `local-llm`、既定モデル、`~/.local/bin/llm-agent` を上書きする。
