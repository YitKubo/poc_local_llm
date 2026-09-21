# client/vscode — VS Code の GitHub Copilot Chat から使う

VS Code の Copilot Chat のモデルを、このリポジトリのサーバの `local-qwen` に差し替える。Copilot Chat の **Custom Endpoint**（BYOK）に OpenAI 互換の URL を登録するだけで、サーバ側は何も変えない。`llm` CLI（[../README.md](../README.md)）とは独立した、もう 1 つのクライアント。

この環境で実際に行った設定・失敗と原因の記録は [../../docs/VSCODE_SETUP.md](../../docs/VSCODE_SETUP.md)。

**先に結論**: Ask（質問）は使える見込み。Agent は API としては通る（実測済み）が、**入力が長いと最初の文字が出るまで数分かかる**ため、実用になるかは実機で試して判断する。インライン補完（Tab）は BYOK では使えない。

## 必要なもの

| 受け取るもの | 例 |
|---|---|
| サーバの URL | `http://localhost:4000`（サーバと同じ PC、または WSL2 から見た Windows ホスト）。別マシンなら `http://<サーバのホスト>:4000` |
| **VS Code 専用の**仮想キー | `sk-...` |
| モデル名 | `local-qwen` |

VS Code 専用のキーを使う理由: キー 1 本あたりの同時実行は 2 本まで（超えると 429）。Copilot は本文の生成と並行してタイトル生成なども投げるため、`llm` CLI と同じキーを使い回すと 429 になりやすい。サーバ管理者が次で発行する。

```bash
cd server && ./scripts/create_keys.sh vscode     # 出力された sk-... を受け取る
```

## 導入

キーは**追跡対象のファイルに書かない**。`.env`（git に入らない）にだけ書き、`apply.sh` が VS Code の設定ファイルを生成する。VS Code は環境変数を直接読めない（`${env:...}` は使えない）ので、`.env` → 設定ファイルの橋渡しをスクリプトが行う。

0. **GitHub Copilot Chat が使えること。** 最近の VS Code（1.135 で確認）は Copilot Chat が本体に組み込みで、拡張の追加は要らない（`code --list-extensions` に出ないのはそのため）。古い VS Code では拡張 `GitHub.copilot-chat` を入れる。
1. **（推奨）専用プロファイルを作る。** ユーザー設定にターミナルの自動承認（`rm` など）がある場合、1.5B のモデルの Agent にも効いてしまうため。コマンドパレット → `Profiles: Create Profile...` → 名前 `local-llm`、テンプレート `Empty`。既定プロファイルに入れるなら、この手順は不要（`.env` の `VSCODE_PROFILE` を空にする）。
2. `.env` を作って編集する。

   ```bash
   cd client/vscode
   cp .env.example .env
   # .env を開き、LLM_SERVER_KEY を受け取ったキーに、LLM_SERVER_URL をサーバの URL にする
   ```

3. 生成する。

   ```bash
   ./apply.sh --dry-run    # 書き込み先と結果を確認（キーは伏せて表示）
   ./apply.sh              # VS Code の chatLanguageModels.json に poc_local_llm を追加・更新
   ```

   - 書き込み先（プロファイルのフォルダ）は自動で見つける（WSL は Windows 側の `%APPDATA%\Code\User`）。見つからなければ `.env` の `VSCODE_USER_DIR` で指定する。
   - 同じファイルにある**ほかのプロバイダの設定は残す**。ほかの設定があったファイルは、書く前に `.bak` に控える。何度実行しても同じ結果になる。
   - キーやモデル名などを変えたときは、`.env` を直してもう一度 `./apply.sh`。
   - やめるときは `./apply.sh --uninstall`（`poc_local_llm` の分だけ消す）。
4. チャットの入力欄にカーソルを置いて `Ctrl+Alt+.`（モデルの選択）から `local-qwen (poc_local_llm)` を選ぶ。

### キーを誤ってコミットしないために

- キーが入るのは **`client/vscode/.env`（`.gitignore` 済み）と、VS Code のプロファイルのフォルダ**（リポジトリの外）だけ。`chatLanguageModels.sample.json` は `apply.sh` が読むテンプレートで、**編集しない**（プレースホルダ `sk-REPLACE_...` のまま）。
- 念のため pre-commit フック（`.githooks/pre-commit`）が、`sk-...` の形の文字列を追加するコミットを止める。クローンごとに 1 回だけ有効にする: `git config core.hooksPath .githooks`
- **キーは平文で残る**（`.env` と、生成された `chatLanguageModels.json`）。専用キーは同時 2 本・日次の予算つきに絞ってあるので、漏れても被害は小さい。漏れたと思ったら、サーバで `./scripts/create_keys.sh --rotate vscode`（古いキーは無効になる）。
- **`apiKey` の欄に平文のキーを書いても使われない。** VS Code は `apiKey` を暗号化した保管場所（`${input:chat.lm.secret.…}` の参照）から取り出す作りで、平文の文字列は空として扱う。空だと `Authorization: Bearer ` だけが送られ、LiteLLM が `Malformed API Key passed in` の 401 を返す（実機で確認）。`${input:好きな名前}` も同じ理由で使えない。そのため、キーは `requestHeaders` の `Authorization` に入れている。
- 平文を避けたいときは、`Chat: Manage Language Models` の画面から `Add Models` → `Custom Endpoint` で追加し、キーを画面から入れる（VS Code が保管場所に入れる）。この経路は**未検証**。

### 手で編集する場合の場所（`apply.sh` を使わないとき）

| 環境 | パス |
|---|---|
| Windows | `%APPDATA%\Code\User\chatLanguageModels.json` |
| macOS | `~/Library/Application Support/Code/User/chatLanguageModels.json` |
| Linux | `~/.config/Code/User/chatLanguageModels.json` |

Remote-WSL で使う場合も、ユーザー設定は Windows 側のこのファイル。コマンドパレットから開くのが確実。プロファイルを使う場合は、`profiles\<フォルダ名>\chatLanguageModels.json`（フォルダ名は `globalStorage\storage.json` の `userDataProfiles` に載っている）。手で書くときも、キーを入れるのは**この生成先のファイルだけ**で、`chatLanguageModels.sample.json` には書かない。

### サンプルの数字の根拠（`.env` の `MAX_INPUT_TOKENS` などで変えられる）

| 項目 | 値 | 理由 |
|---|---|---|
| `id` | `local-qwen` | サーバの `litellm_config.yaml` の `model_name`。一致していないと 403 になる |
| `maxInputTokens` | 8000 | サーバの文脈長は 16384 を 4 スロットで共有。さらに下記の実測のとおり、入力が長いほど待ちが線形に伸びる。8000 で最初の文字まで約 2.5 分 |
| `maxOutputTokens` | 2048 | 出力ぶんの余裕（8000 + 2048 は 16384 に収まる） |
| `toolCalling` | `true` | Agent に必須。サーバ側は `tool_calls` を返すことを実測で確認済み（下記） |
| `vision` | `false` | 画像入力の無いモデル |

## Copilot のサブスクリプション無しで使う場合

BYOK のモデルだけなら GitHub アカウント／サブスクリプションが無くてもチャットは使える。ただしタイトル生成やコミットメッセージ生成は既定で Copilot のモデルを呼ぶため、`settings.json` で向け先を変える。

```json
{
  "chat.utilityModel": "local-qwen (poc_local_llm)",
  "chat.utilitySmallModel": "local-qwen (poc_local_llm)"
}
```

（値の書式は VS Code のドキュメントの記述に沿ったもの。**この書式で実際に効くかは未検証**。効かなければ設定 UI のモデル選択欄から選ぶ。）

## できること / できないこと

| 機能 | 状態 | 備考 |
|---|---|---|
| Ask（質問） | ○ 見込み | 短いプロンプトなら数秒で返る（RESULTS §8） |
| Agent（ツール呼び出し） | △ 要実機確認 | API は通る。Copilot が送る実際のプロンプトの大きさ次第 |
| Edit / Plan | △ 要実機確認 | 同上。編集対象のファイルが入力に入るぶん長くなる |
| インライン補完（Tab） | ✗ | BYOK では提供されない（Copilot サービスが必須）。やるなら `llama.vscode` 拡張 + llama.cpp の `/infill` を別に立てる。LiteLLM は今 `/v1/chat/completions` だけを公開している |
| `#codebase` などの意味検索 | ✗ | Copilot サービスが必須 |
| embeddings | ✗ | 同上。サーバに埋め込みモデルも無い |

## 使うときの注意

- **入力が長いと待たされる。** サーバのプロンプト処理（prefill）は約 42〜59 tok/s。実測では入力 1,127 トークンで 27 秒、4,457 で 83 秒、8,897 で 150 秒待ってから最初の文字が出た。生成が始まってからの速度（約 10〜28 tok/s）とは別の待ち。Agent は毎回システムプロンプトとツール定義を送るので、この待ちを毎ターン払う可能性がある（**Copilot が実際に送る大きさは未計測**）。
- **同時 2 本まで。** Copilot が本文とタイトル生成を並行して投げると、2 本目・3 本目が 429 になりうる。専用キーを使っていれば他の利用者や `llm` CLI には影響しない。
- **モデルは 1.5B。** [../README.md](../README.md) にあるとおり、ツールの実行を断ったり、最後の解説が実際のツール結果と食い違ったりする。Agent では、承認ダイアログに出るコマンドやファイル編集の内容を必ず自分で見てから許可する。自動承認は使わない。
- サーバ全体で約 25〜30 tok/s を全員で分け合う。
- 日次の使用量に上限がある（詳細は [../README.md](../README.md)）。

## うまくいかないとき

| 症状 | 見るところ |
|---|---|
| 401（`Malformed API Key ... Bearer prefix`） | キーが空で送られている。`requestHeaders` の `Authorization` に `Bearer sk-...` を直接書いているか（`apiKey` 欄では効かない。上記）。 |
| 401（`Invalid proxy server token`） | キーが違う。`llm` CLI 用のキーを渡していないか。`curl -H "Authorization: Bearer sk-..." http://localhost:4000/v1/models` で `local-qwen` が見えるか |
| 404 | `url` が `/v1/chat/completions` まで含んでいるか（`/v1` で止めると 404。`/chat/completions` だけでも通るが、`/v1` 付きに揃える） |
| 403 `key not allowed to access model` | `id` が `local-qwen` と一致しているか。キーはこのモデルにしか許可されていない |
| 429 | 同時 2 本を超えた。少し待って再送。他のクライアントと同じキーを使っていないか |
| いつまでも返ってこない | 入力が長い。上の実測を参照。`maxInputTokens` を下げる／会話を新しく始める／添付するファイルを減らす |
| 途中で切れる・文脈溢れ | サーバ側で `docker compose logs litellm llama` を見て、入力トークン数が 16384 に近くないか確認。`maxInputTokens` を下げる |
| Windows 側から届かない | Windows のターミナルで `curl.exe http://localhost:4000/health/liveliness` が 200 か（WSL2 では 200 になることを確認済み） |

## 元に戻す

```bash
cd client/vscode && ./apply.sh --uninstall     # poc_local_llm の分だけ消す（ほかのプロバイダは残る）
```

- `.env` は自分で消す（`rm client/vscode/.env`）。プロファイルごと消すなら、コマンドパレットの `Profiles: Delete Profile...`。
- `client/uninstall.sh` はこの設定を触らないので対象外。
- 発行した `vscode` キーを無効にするなら、サーバ側で `./scripts/create_keys.sh --rotate vscode` で作り直すか、管理 UI から削除する。
