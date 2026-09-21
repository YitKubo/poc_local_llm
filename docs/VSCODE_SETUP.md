# VS Code Copilot Chat 接続の設定記録

この環境（WSL2 + Windows の VS Code）で、Copilot Chat から `local-qwen` を使えるようにするために**実際に行った設定・変更・失敗と原因**の記録。手順書は [../client/vscode/README.md](../client/vscode/README.md)、計測値は [RESULTS.md](RESULTS.md) §8。

- 作業日: 2026-09-21〜22
- 状態: **登録・認証・サーバへの到達までは確認済み。返答が最後まで返るところ（所要時間）は未確認**（下の「未確認」を参照）

## 1. 環境

| 項目 | 内容 |
|---|---|
| サーバ | このリポジトリの `server/`（LiteLLM `:4000` → llama.cpp、Qwen2.5-1.5B、ctx 16384 を 4 スロット共有）。**設定は一切変更していない** |
| VS Code（Windows） | 1.135.0 → **1.138.0** に更新（再起動で適用） |
| Copilot Chat | VS Code **組み込み**（追加の拡張は不要）。0.63.0 → **0.66.0** |
| 作業フォルダ | WSL の `/home/kubo/poc_local_llm`（Remote-WSL で開く） |
| Copilot 拡張の実行場所 | WSL 側の拡張ホスト（`~/.vscode-server/`）。サーバへは `localhost:4000` で届く |
| GitHub | サインイン済み・Copilot のサブスクリプションあり（BYOK 自体はサブスク無しでも使える） |

## 2. 行った設定

### 2.1 サーバ側: 専用の仮想キー

`server/scripts/create_keys.sh vscode` で、VS Code 専用のキーを 1 本発行した（別名 `vscode`）。`llm` CLI とキーを分けたのは、キーごとの同時実行が 2 本までで、Copilot が本文の生成と並行して別の呼び出しも投げるため。

| 上限（`.env` の既定） | 値 |
|---|---|
| 同時実行 | 2 |
| RPM / TPM | 30 / 40000 |
| 日次予算 | 0.4（名目単価での額） |

キーの値はこの記録には書かない。プロファイルの `chatLanguageModels.json`（2.3）に入っている。無効にするなら `./scripts/create_keys.sh --rotate vscode`。

### 2.2 VS Code のプロファイル `local-llm`

自動承認の設定（下の「触っていないもの」）が、1.5B のローカルモデルの Agent にも効いてしまうのを避けるため、**空のプロファイル**を作って、そこにだけモデルを登録した。

| 項目 | 内容 |
|---|---|
| 名前 / フォルダ名 | `local-llm` / `-22feefef` |
| 場所 | `%APPDATA%\Code\User\profiles\-22feefef\`（WSL からは `/mnt/c/Users/<user>/AppData/Roaming/Code/User/profiles/-22feefef/`） |
| 作り方 | コマンドパレット `Profiles: Create Profile...` → 名前 `local-llm`、テンプレート `Empty`（UI で実施。WSL 側の `code` に `--profile` は無く、CLI では作れない） |
| 紐づけ | `poc_local_llm` のフォルダをこのプロファイルに紐づけた（`storage.json` の `profileAssociations` で確認） |
| `settings.json` | **無い**（= 自動承認などの設定は入っていない） |

### 2.3 モデルの登録（プロファイル内の `chatLanguageModels.json`）

最終的に動いている形（キーは伏せ字）:

```json
[
  {
    "name": "poc_local_llm",
    "vendor": "customendpoint",
    "apiKey": "unused",
    "apiType": "chat-completions",
    "models": [
      {
        "id": "local-qwen",
        "name": "local-qwen (poc_local_llm)",
        "url": "http://localhost:4000/v1/chat/completions",
        "toolCalling": true,
        "vision": false,
        "maxInputTokens": 8000,
        "maxOutputTokens": 2048,
        "requestHeaders": {
          "Authorization": "Bearer sk-…（vscode キー）"
        }
      }
    ]
  }
]
```

| 項目 | 値と理由 |
|---|---|
| `id` | `local-qwen`。サーバの `litellm_config.yaml` の `model_name` と一致させる（不一致は 403） |
| `url` | `/v1/chat/completions` まで書く |
| `toolCalling` | `true`。Agent に必須。サーバが `tool_calls` を返すことは API 直叩きで確認済み |
| `maxInputTokens` | 8000。当初の案 12000 から下げた（入力が長いほど待ちが線形に伸びるため） |
| `apiKey` | `"unused"`。**この欄は使われない**（3.1） |
| `requestHeaders.Authorization` | **実際にサーバへ送られるキー。** `Bearer ` は残す。平文でファイルに残る |

これと同じ形のテンプレートが [../client/vscode/chatLanguageModels.sample.json](../client/vscode/chatLanguageModels.sample.json)（キーは `sk-REPLACE_WITH_YOUR_VSCODE_KEY` のまま）。**このファイルは編集しない。** 実際のファイルは、次の 2.5 のとおり `.env` から生成している。

### 2.4 触っていないもの

- 既定のユーザー設定 `settings.json`。ここには `chat.tools.terminal.autoApprove` があり、`rm`、`sudo`、`git add`、`git commit` などが `true`。**既定プロファイルで Agent を使うと、確認なしで実行されうる**。このため専用プロファイルを作った
- 既定プロファイルの `chatLanguageModels.json`（`[]` のまま）
- サーバの `docker-compose.yml` / `litellm_config.yaml` / `.env`

### 2.5 キーの取り扱い（コミット事故の対策）

サンプルにキーを書いて編集する運用だと、キーが毎回コミットされる危険があった（`chatLanguageModels.sample.json` は追跡対象で、実際に何度もコミットされている）。そこで、キーを**追跡対象のファイルに一切書かない**運用に変えた。

| 場所 | 内容 |
|---|---|
| `client/vscode/.env` | **キーを書く唯一の場所。** `.gitignore` 済み（`git check-ignore` で確認） |
| `client/vscode/.env.example` | `.env` の雛形（プレースホルダのみ。追跡対象） |
| `client/vscode/apply.sh` | `.env` とテンプレート（`chatLanguageModels.sample.json`）から、VS Code のプロファイルの `chatLanguageModels.json` を生成する。既存の他プロバイダは残し、ある場合は `.bak` に控える。`--dry-run` / `--uninstall` あり |
| `.githooks/pre-commit` | `sk-...` の形の文字列を追加するコミットを止める（`REPLACE` を含むプレースホルダは通す）。`git config core.hooksPath .githooks` で有効化（このクローンでは有効にした） |

- VS Code は `chatLanguageModels.json` の中で環境変数を読めない（Copilot 拡張に `${env:...}` の処理は無い）。そのため `.env` から生成するスクリプトを挟んだ。
- 試験: 偽のユーザーフォルダで、生成・他プロバイダの保持・バックアップ・再実行・`--uninstall` を確認。フックは、キー形の文字列を含む変更を止め（終了コード 1）、プレースホルダだけなら通す（0）ことを確認。実際のプロファイルへの適用は、実行前と同じ内容になった。
- これまでの git 履歴と作業ツリーに、本物のキーが入っていないことを確認した（`sk-` 形の文字列の検索。プレースホルダを除く）。
- 残る平文: `.env` と、生成された `chatLanguageModels.json`（どちらもリポジトリの外か `.gitignore` 済み）。他プロバイダの設定があったときの `.bak` も同じ場所に残る。

## 3. 失敗と原因（時系列）

### 3.1 401 が続いた（キーが空で送られていた）

| 試したこと | 結果 |
|---|---|
| `apiKey` に `${input:pocLocalLlmKey}` | キーの入力を求められず 401 |
| `apiKey` に平文のキー | 401 `Malformed API Key passed in. Ensure Key has Bearer prefix` |
| `requestHeaders` に `Bearer ${apiKey}` | 同じ 401 |
| **`requestHeaders` に `Bearer sk-…` を直接** | **200 OK。これが現行の形** |

**原因**（VS Code 1.138.0 の workbench と Copilot 拡張のコードで確認）:
- `apiKey` は「秘密の値」で、`${input:chat.lm.secret.<ハッシュ>}` の参照から、暗号化された保管場所（secret storage）を引いて取り出す作り。参照でない文字列（平文や任意名）は**空になる**
- 空のキーだと、拡張は `Authorization: Bearer ` だけを送る。`Bearer ${apiKey}` も、その空の値が入るだけ
- LiteLLM に `Authorization: Bearer ` を送ると、VS Code に出たものと同じエラーが再現する
- 暗号化された保管場所には WSL 側から書き込めないので、`apiKey` を通らない `requestHeaders` にキーを直接書いた

### 3.2 モデルの選び方

- `Chat: Change Model` はコマンドパレットに**出ない**（内部コマンドで `f1: false`）
- モデル選択は、チャット入力欄にカーソルを置いて **`Ctrl+Alt+.`**（`Open Model Picker`）
- 登録の確認は、コマンドパレットの `Chat: Manage Language Models`（`poc_local_llm` のグループが出る）
- 1.138.0 では、チャットのセッションの種類が `Local` 以外だと、モデル選択のボタンが隠れる条件がある（コードで確認。実機では今回この理由では止まらなかった）

### 3.3 `No lowest priority node found`（最初の試行で 1 回）

Copilot 拡張が、サーバへ送る前にプロンプトを組み立てられずに失敗したエラー。サーバには届いていない。**原因は未確認**。プロンプトの固定部分が `maxInputTokens: 8000` に収まらなかった可能性がある、というのは推測。認証を直した後の Ask モードでは、このエラーは出ずに送信できた。

### 3.4 「こんにちは」が数分かかる（遅い）

同じ「こんにちは」が、端末の `llm` では数秒、Copilot では約 4 分（252 秒）かかった。原因は 3 つ重なっている（LiteLLM の記録と Copilot のログで確認）。

1. **入力が大きい。** 本体のリクエストの入力が 8,743 トークン（端末は十数トークン）。CPU のみで約 45 tok/s なので、読み込みだけで約 190 秒
2. **同じモデルに、要約のリクエストが並行して届く。** Copilot の `ConversationHistorySummarizer` が、会話履歴の要約を `local-qwen` に依頼する（入力 1,326〜1,342、出力 407〜539 トークン）。CPU を取り合い、要約の生成は 1.5〜7 tok/s まで落ち、本体も約 60 秒延びた
3. **待っている間の再送・キャンセルが積み重なる。** ログに `cancelled` が多数

なお、タイトル生成（`[title]`）は Copilot 側のクラウドの `gpt-4o-mini` に行くので、ローカルの負荷にならない。

対策の候補（いずれも**効果は未検証**）:
- **新しいチャットで送る。** 履歴が無いと `no prior content to summarize, skipping` となり、要約が走らない
- **待っている間は再送・キャンセルしない。** 本体は約 4 分で返る
- **ツールを減らして入力を小さくする**（チャット入力欄のツール設定）。Agent より Ask のほうが小さいはず
- 根本的には、GPU か、より小さな入力でも動く構成が必要

### 3.5 Copilot の CLI（`copilot`）で、私が自分で検証した

VS Code のチャットを人が操作せずに、Copilot 自身のプロンプトがサーバにどう届くかを測るため、Copilot の CLI（`copilot` 1.0.86。VS Code の Copilot 拡張が `~/.vscode-server/data/User/globalStorage/github.copilot-chat/copilotCli/` に置いたもの）を、自前サーバに向けて実行した。CLI は環境変数だけで OpenAI 互換のサーバに向けられる（`COPILOT_PROVIDER_BASE_URL` など。GitHub 認証は不要）。

条件: 空の作業フォルダ、ツールの実行は許可しない、キーは `client/vscode/.env` から環境変数に渡す（画面・ログには出さない）。

```bash
export COPILOT_OFFLINE=true
export COPILOT_PROVIDER_BASE_URL=http://localhost:4000/v1
export COPILOT_PROVIDER_TYPE=openai
export COPILOT_PROVIDER_API_KEY=<.env の LLM_SERVER_KEY>
export COPILOT_MODEL=local-qwen COPILOT_PROVIDER_WIRE_MODEL=local-qwen COPILOT_PROVIDER_MODEL_ID=local-qwen
export COPILOT_PROVIDER_MAX_PROMPT_TOKENS=14000 COPILOT_PROVIDER_MAX_OUTPUT_TOKENS=2048
copilot --model local-qwen -p "こんにちは" --no-ask-user --no-auto-update --no-remote --no-color --no-custom-instructions --log-dir <dir> --log-level debug
```

| 回 | 設定 | 結果 |
|---|---|---|
| 1 | 上限 8000、`--model` なし | 送信せずに終了: `Static system messages and tool definitions exceed the model's usable context budget`（この回は `claude-sonnet-4.6` 用の設定で組まれていた） |
| 2 | 上限 14000、`--model` なし | 同じエラー |
| 3 | 上限 100000、`--model` なし | 検査を通って送信されたが **403**。CLI が環境変数 `COPILOT_MODEL` を無視し、既定のモデル名 `claude-sonnet-4.6` を送っていた（キーは `local-qwen` だけ許可） |
| 4 | 上限 14000、**`--model local-qwen`** | **成功**（下記） |
| 5 | 上限 **8000**、`--model local-qwen` | **送信せずに拒否**（回 1 と同じエラー。サーバへの POST は 0 件） |

- 回 1・2 は、別のモデル名（`claude-sonnet-4.6`）用の設定で固定部分が組まれ、14000 でも超えた（100000 では通った）。`local-qwen` の設定では、14000 で通り（回 4）、8000 では拒否された（回 5）。つまり **`local-qwen` の固定部分は 8000 を超え、14000 未満**で、回 4 の実測では 10,710 トークン
- 回 4 の結果: 「こんにちは」に対して、返答は日本語で正しく返った（`こんにちは！GitHub Copilot CLI を使用して、…`）。**入力 10,710 トークン、出力 24 トークン、合計 5 分 16 秒**（入力の処理 311 秒 = 34 tok/s、生成 4.2 秒）
- 入力の内訳: システムメッセージが **20,935 文字**。ユーザーの発話は 73 文字（日時 + 「こんにちは」）。サーバが数えたトークン数（10,710）と文字数（約 21,000）が合わないため、残りの約 5,500 トークンは **17 個のツール定義**と見られる（ログの `tool_count: 17`。ただし、リクエストの記録では `tools` が空で、直接は確認できていない）
- **結論**: Copilot は、「こんにちは」の 1 語でも、**約 1 万トークンの固定の入力**を毎回付ける。このサーバ（CPU のみ、約 35〜50 tok/s）では、それだけで 4〜5 分かかる。VS Code の Ask（8,743 トークン、252 秒）と、Copilot CLI（10,710 トークン、316 秒）は、ほぼ同じ規模。
- VS Code で最初に出た `No lowest priority node found`（3.3）は、この固定部分が `maxInputTokens: 8000` に収まらないときの失敗と同じ原因の可能性が高い（Agent は Ask より大きいはず）。CLI では 8000 で拒否されるのを確認（回 5）。ただし、VS Code 側では未確認。
- **上限（`maxInputTokens`）を上げれば動くが、待ちも増える。** サーバの文脈長は 16384 で、入力 + 出力（2048）がそれに収まる必要がある。

## 4. 確認できたこと / 未確認

| 項目 | 状態 |
|---|---|
| Windows ホストから `localhost:4000` に届く | 確認済み（200） |
| VS Code でモデルを登録・選択できる | 確認済み |
| 認証が通り、llama.cpp まで届く（`POST /v1/chat/completions` が 200） | 確認済み |
| ツール呼び出し（`tool_calls`、ストリーミング含む） | API 直叩きで確認済み |
| 返答が最後まで返るまでの所要時間 | 確認済み: VS Code の Ask で **252 秒**（入力 8,743 トークン）、Copilot CLI で **316 秒**（入力 10,710 トークン）。いずれも「こんにちは」 |
| 2 通目以降でプロンプトキャッシュが効き、短くなるか | **未確認** |
| ツールを減らしたときの入力の大きさ | **未確認**（CLI の固定部分は 10,710 トークン。うちツール定義は約 5,500 と推測） |
| Agent / Edit / Plan の実機での動作 | **未確認** |
| `chat.utilityModel` / `chat.utilitySmallModel` をローカルモデルに向ける書式 | **未確認** |
| キーを画面から入れる経路（`Add Models` → `Custom Endpoint`。暗号化保管） | **未検証** |
| 同時 2 本制限に Copilot がぶつかる頻度（429） | **未確認** |

## 5. 元に戻す

| 何を | どうする |
|---|---|
| モデルの登録 | プロファイルの `chatLanguageModels.json` を `[]` に戻す |
| プロファイルごと | コマンドパレット `Profiles: Delete Profile...` で `local-llm` を削除（`poc_local_llm` は既定プロファイルに戻る） |
| 登録の生成物 | `client/vscode/` で `./apply.sh --uninstall`（`poc_local_llm` の分だけ消す）。`.env` は自分で削除 |
| キー | サーバで `./scripts/create_keys.sh --rotate vscode` |
| VS Code の更新 | 元に戻さない（1.138.0 のまま） |

## 6. 参考（コードで確認した内部仕様）

- `apiKey` の解決: workbench の `SECRET_KEY_PREFIX = "chat.lm.secret."`。`secret` フラグつきの項目は `decodeSecretKey` で参照名を取り出して secret storage を引く。参照でなければ `undefined`
- 認証ヘッダ: 拡張が `Authorization: Bearer ${apiKey}` を既定で作る。`requestHeaders` に `api-key` / `authorization` / `x-api-key` / `x-goog-api-key` / `apikey` があれば、既定の認証ヘッダは付けず、その値を使う。値の中の `${apiKey}` だけが置換される
- ワークスペース側の `chat.tools.terminal.autoApprove` を Copilot が読まない不具合の報告がある: https://github.com/microsoft/vscode/issues/336715 （このため `.vscode/settings.json` で自動承認を止める方法は使っていない）
- Copilot Chat のログ（WSL 側）: `~/.vscode-server/data/logs/<日時>/exthost1/GitHub.copilot-chat/GitHub Copilot Chat.log`

## 7. 経緯（時系列）

作業日: 2026-09-21〜22。「GitHub Copilot とこのローカル LLM サーバをつなぐ方法を検討して」という依頼から始まった。

| # | 何をしたか | 結果・判断 |
|---|---|---|
| 1 | 既存の構成を調べた | LiteLLM（`:4000`）→ llama.cpp、Qwen2.5-1.5B、ctx 16384 を 4 スロット共有。エディタ連携は無し。`llm` CLI だけがクライアント |
| 2 | Copilot 側の仕様を調べた | VS Code の Copilot Chat に **Custom Endpoint（BYOK）** があり、OpenAI 互換の URL を登録できる。インライン補完（Tab）・意味検索・embeddings は BYOK では使えない |
| 3 | 方針を確認した | ①Ask / Agent などを全部試したい ②**サーバは変更しない** ③成果物は `client/` に手順とサンプル |
| 4 | `client/vscode/` と `docs/` を作成 | 手順書・サンプル JSON・計測記録 |
| 5 | VS Code に触る前に、API を直接叩いて検証 | `tool_calls`（ストリーミング含む）は通る。**入力の処理（prefill）が約 42〜59 tok/s**で、8,900 トークンで最初の文字まで 150 秒。`maxInputTokens` を 12000 → 8000 に下げた |
| 6 | 誤り①: Copilot 拡張が「未導入」と書いた | 実際は VS Code 1.135 に**組み込み済み**（拡張の一覧に出ないだけ）。訂正した |
| 7 | 誤り②に気づく前に、ユーザー設定を確認した | `chat.tools.terminal.autoApprove` に `rm`・`sudo`・`git commit` などが `true`。1.5B のモデルの Agent にも効くため、**空の専用プロファイル `local-llm`** で試すことにした |
| 8 | VS Code を更新（1.135 → 1.138） | 1 回目の「再起動」は、アプリが完全に終了しておらず更新されなかった（メインプロセスの起動時刻で判明）。全ウィンドウを閉じて 2 回目で成功 |
| 9 | プロファイルを作成して、モデルを登録 | WSL 側の `code` に `--profile` は無く、画面（`Profiles: Create Profile...`）で作成。登録ファイルは私が書き込んだ |
| 10 | モデルが選べなかった | `Chat: Change Model` はパレットに出ない内部コマンドだった（私の案内の誤り）。`Ctrl+Alt+.` で選べた |
| 11 | `No lowest priority node found` | 最初の試行で 1 回。原因は未確認（3.3） |
| 12 | **401 が続いた** | `apiKey` に `${input:任意名}`・平文・`Bearer ${apiKey}` を試して全部失敗。コードを読んで原因を特定: `apiKey` は暗号化保管庫の参照だけを解決し、平文は空になる。`requestHeaders` にキーを直接書いて解決（3.1）。**途中で私は「平文のキーで動く」と誤って説明し、「古いエラーの貼り直し」とも誤認した** |
| 13 | サンプルが毎回コミットされ、キーが入る危険を指摘された | キーを追跡対象に書かない運用へ。`.env`（`.gitignore` 済み）+ `apply.sh` + pre-commit フック（2.5）。履歴にキーが入っていないことも確認 |
| 14 | 「こんにちは」が数分かかる | 3 本のリクエストが並行して届いていた。本体の入力は 8,743 トークン（252 秒）、要約が 2 本（3.4） |
| 15 | **Copilot の CLI（`copilot`）で、私が自分で検証した** | 3.5。CLI は環境変数 `COPILOT_MODEL` を無視して別のモデル名を送った。指定し直すと、**「こんにちは」だけで入力が約 10,800 トークン**だった |

### 私の誤りの一覧（訂正済み）

| 誤り | 実際 |
|---|---|
| Copilot 拡張が未導入 | 組み込み済み |
| `Chat: Change Model` でモデルを選べる | パレットに出ない。`Ctrl+Alt+.` |
| `apiKey` に平文のキーを書けば動く | 空として扱われる。`requestHeaders` に書く |
| 401 の再発を「古いエラーの貼り直し」と判断 | サーバのログでは新しいリクエストだった |
| 遅いのは入力の大きさだけ | 要約の追加リクエストと CPU を取り合っていた |
