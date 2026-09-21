# client/vscode — VS Code の GitHub Copilot Chat から使う

VS Code の Copilot Chat のモデルを、このリポジトリのサーバの `local-qwen` に差し替える。Copilot Chat の **Custom Endpoint**（BYOK）に OpenAI 互換の URL を登録するだけで、サーバ側は何も変えない。`llm` CLI（[../README.md](../README.md)）とは独立した、もう 1 つのクライアント。

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

0. **GitHub Copilot Chat が使えること。** 最近の VS Code（1.135 で確認）は Copilot Chat が本体に組み込みで、拡張の追加は要らない（`code --list-extensions` に出ないのはそのため）。古い VS Code では拡張 `GitHub.copilot-chat` を入れる。
1. コマンドパレット → `Chat: Manage Language Models` → `Add Models` → `Custom Endpoint`。`chatLanguageModels.json` が開く。
2. [chatLanguageModels.sample.json](chatLanguageModels.sample.json) の内容を貼る（すでに他のプロバイダがあれば、配列の要素として 1 つ足す）。
3. `apiKey` の `sk-REPLACE_WITH_YOUR_VSCODE_KEY` を、受け取った VS Code 専用のキーに置き換える。**キーはこのファイルに平文で残る**（VS Code のプロファイルのフォルダ内で、リポジトリには入らない）。専用キーは同時 2 本・日次の予算つきに絞ってあるので、漏れても被害は小さい。
   - 平文を避けたいときは、`Chat: Manage Language Models` の画面から `Add Models` → `Custom Endpoint` の流れで追加する。VS Code がキーを安全な保管場所に入れ、ファイルには `${input:chat.lm.secret.…}` という参照だけを書く。
   - **`${input:好きな名前}` は使えない。** VS Code が解決するのは `chat.lm.secret.` で始まる名前だけで、任意の名前を書くとキーが送られず 401 になる（実機で確認）。
4. チャットのモデルピッカーから `local-qwen (poc_local_llm)` を選ぶ。

サーバが別マシンなら、サンプルの `url` の `localhost` をそのホスト名に変える。URL は `/v1/chat/completions` まで書く。

### 手で編集する場合の場所

| 環境 | パス |
|---|---|
| Windows | `%APPDATA%\Code\User\chatLanguageModels.json` |
| macOS | `~/Library/Application Support/Code/User/chatLanguageModels.json` |
| Linux | `~/.config/Code/User/chatLanguageModels.json` |

Remote-WSL で使う場合も、ユーザー設定は Windows 側のこのファイル。コマンドパレットから開くのが確実。

### サンプルの数字の根拠

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
| 401 | キーが違う。`apiKey` に `${input:…}` の任意名を書いていないか（上記）、または `llm` CLI 用のキーを渡していないか。`curl -H "Authorization: Bearer sk-..." http://localhost:4000/v1/models` で `local-qwen` が見えるか |
| 404 | `url` が `/v1/chat/completions` まで含んでいるか（`/v1` で止めると 404。`/chat/completions` だけでも通るが、`/v1` 付きに揃える） |
| 403 `key not allowed to access model` | `id` が `local-qwen` と一致しているか。キーはこのモデルにしか許可されていない |
| 429 | 同時 2 本を超えた。少し待って再送。他のクライアントと同じキーを使っていないか |
| いつまでも返ってこない | 入力が長い。上の実測を参照。`maxInputTokens` を下げる／会話を新しく始める／添付するファイルを減らす |
| 途中で切れる・文脈溢れ | サーバ側で `docker compose logs litellm llama` を見て、入力トークン数が 16384 に近くないか確認。`maxInputTokens` を下げる |
| Windows 側から届かない | Windows のターミナルで `curl.exe http://localhost:4000/health/liveliness` が 200 か（WSL2 では 200 になることを確認済み） |

## 元に戻す

`chatLanguageModels.json` から `poc_local_llm` の要素を消す（ほかに何も無ければ `[]` に戻す）。`client/uninstall.sh` はこのファイルを触らないので対象外。発行した `vscode` キーを無効にするなら、サーバ側で `./scripts/create_keys.sh --rotate vscode` で作り直すか、管理 UI から削除する。
