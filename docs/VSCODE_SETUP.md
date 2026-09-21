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

### 3.4 「Considering」のまま返答が出ない（遅い）

同じ「こんにちは」が、端末の `llm` では数秒、Copilot では数分かかる。

- llama.cpp のログでは、入力の処理が 4,094 トークンで進捗 47%（約 42〜48 tok/s）。入力は合計約 **8,700 トークン**と逆算できる
- 8,700 ÷ 45 ≒ **約 190 秒**。以前の API 直叩きの実測（8,897 トークンで 150 秒）と同じ傾向
- 端末の入力は十数トークン。差は、Copilot が毎回付ける文脈（システムプロンプト・ツール定義・環境情報など）による入力の大きさ。**内訳の比率は未測定**

## 4. 確認できたこと / 未確認

| 項目 | 状態 |
|---|---|
| Windows ホストから `localhost:4000` に届く | 確認済み（200） |
| VS Code でモデルを登録・選択できる | 確認済み |
| 認証が通り、llama.cpp まで届く（`POST /v1/chat/completions` が 200） | 確認済み |
| ツール呼び出し（`tool_calls`、ストリーミング含む） | API 直叩きで確認済み |
| 返答が最後まで返るまでの所要時間 | **未確認** |
| 2 通目以降でプロンプトキャッシュが効き、短くなるか | **未確認** |
| ツールを減らしたときの入力の大きさ | **未確認** |
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
