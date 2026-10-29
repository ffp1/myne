# Myne セットアップ手順

Windows だけで完結します（ビルドは GitHub Actions の macOS 上で行います）。

---

## 1. Firebase プロジェクトを作る

1. https://console.firebase.google.com/ を開き「プロジェクトを追加」
   - プロジェクト名: 任意（例 `myne`）
   - Google アナリティクス: **オフ**で OK
2. プラン: **Spark（無料）のまま**で動きます（画像は Firestore に圧縮保存するため Storage 不要）

## 2. iOS アプリを登録する

1. プロジェクトの概要 → 「アプリを追加」→ **iOS**
2. Apple バンドル ID: **`com.myne.app`**（必ずこの値）
3. `GoogleService-Info.plist` をダウンロード
   - 以降の「SDK を追加」「初期化コード」の手順は**スキップ**（コード側で対応済み）

## 3. Authentication（ログイン）

1. 構築 → Authentication → 始める
2. 「Sign-in method」タブで次の2つを**有効化**
   - **メール / パスワード**
   - **Google**（サポートメールを選んで保存）
3. **Google を有効にした後に** `GoogleService-Info.plist` を**もう一度ダウンロード**してください
   （`CLIENT_ID` / `REVERSED_CLIENT_ID` が含まれた版が必要です）

## 4. Firestore（データベース）

1. 構築 → Firestore Database → 「データベースを作成」
   - ロケーション: `asia-northeast1`（東京）推奨
   - **本番環境モード**で開始
2. 「ルール」タブを開き、このリポジトリの [`firebase/firestore.rules`](../firebase/firestore.rules) の中身を全部貼り付けて「公開」

インデックスの追加作成は不要です。

## 5. GitHub に置いてビルドする

1. GitHub で**新しいリポジトリ**を作成（SideStore からダウンロードできるよう **Public** 推奨）
2. このフォルダを push

   ```bash
   git init -b main
   ```
   ```bash
   git add .
   ```
   ```bash
   git commit -m "Initial commit"
   ```
   ```bash
   git remote add origin https://github.com/<あなたのユーザー名>/<リポジトリ名>.git
   ```
   ```bash
   git push -u origin main
   ```

   `GoogleService-Info.plist` は `.gitignore` 済みなので push されません。

3. `GoogleService-Info.plist` を Base64 にしてクリップボードへ（PowerShell）

   ```powershell
   [Convert]::ToBase64String([IO.File]::ReadAllBytes("$HOME\Downloads\GoogleService-Info.plist")) | Set-Clipboard
   ```

4. GitHub のリポジトリ → Settings → Secrets and variables → Actions → **New repository secret**
   - Name: `GOOGLE_SERVICE_INFO_PLIST`
   - Secret: 貼り付け
5. Actions タブ → 「Build IPA」→ **Run workflow**
   - 完了後、実行結果ページ下部の Artifacts に `Myne-ipa`（`Myne.ipa` 入り）が出ます
6. 配布用リリースを作るときはタグを push

   ```bash
   git tag v1.0.0
   ```
   ```bash
   git push origin v1.0.0
   ```

   Releases に `Myne.ipa` と `source.json` が添付されます。

## 6. SideStore でインストール

- **ソースとして追加（推奨）**: SideStore → Sources → ＋ に次の URL を入力
  `https://github.com/<ユーザー名>/<リポジトリ名>/releases/latest/download/source.json`
  以降はタグを切るたびに SideStore 上で更新できます。
- **直接**: `Myne.ipa` を iPhone に保存 → SideStore の My Apps → ＋ で選択

対応 OS: **iOS 26 以上**

---

## 制約・注意

| 項目 | 内容 |
|---|---|
| プッシュ通知 | 無料 Apple ID の署名では APNs が使えないため、**ローカル通知**で代替しています。アプリ起動中は即時、バックグラウンドでは iOS の判断で 15 分以上の間隔で未読を確認します。完全に終了していると届きません。 |
| 画像 | 1 枚ずつ約 0.9MB 以下に圧縮して Firestore に保存。無料枠（1GiB）で数千枚程度が目安です。 |
| 署名期限 | 無料 Apple ID は 7 日ごとに SideStore での再署名が必要です。 |
| バンドル ID | SideStore はバンドル ID の末尾にチーム ID を付け足します。Firebase / Google ログインは通常そのまま動きますが、Google ログインで「invalid client」等が出た場合はメールログインを使ってください。 |
| スタンプ・壁紙ストア | 画面のみ（中身は今後） |

## データ構造（参考）

```
users/{uid}                 プロフィール（name, myneId, bio, birthday, iconId, backgroundId…）
  ├ friends/{uid}           友だち（isClose = 親しい友だち）
  ├ roomPrefs/{roomId}      ピン留め・通知オフ・非表示・削除時刻（自分だけの設定）
  └ notifications/{id}      「友だちに追加されました」等
myneIds/{id}                ユーザーID の重複防止
rooms/{roomId}              トークルーム（1対1は uid を並べた固定ID、グループはランダムID）
  └ messages/{id}           メッセージ（テキスト・画像・投票・あみだくじ・バースデーカード）
images/{id}                 画像データ（bytes）
```
