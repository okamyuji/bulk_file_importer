# bulk_file_importer

## 概要

このアプリケーションは、ECS FargateとAurora MySQLの環境において、複数のユーザーが大規模なCSVファイル（数千から数万行）と画像・動画などのバイナリファイルを同時にアップロードし、OOMを起こさずに並行処理で取り込むためのRails 8アプリケーションです。

CSVは行単位でチャンク分割してDBへupsertし、バイナリは8MB単位でS3に分割アップロードしたうえでS3マルチパートCopyによってサーバーローカルへ書き戻すことなく1オブジェクトに再構成します。チャンクごとに失敗・リトライが可能で、部分的な障害からの復旧にも対応します。

サポートするバイナリのMIMEタイプは `image/jpeg`、`image/png`、`image/webp`、`video/mp4`、`video/quicktime` です。CSVのMIMEタイプは `text/csv`、`application/csv`、`application/vnd.ms-excel` を許容します。

## 技術スタック

| レイヤ | 採用技術 |
|---|---|
| バックエンド | Ruby 3.4.11 / Rails 8.1.3 / Puma |
| データベース | MySQL 8.0（開発環境はDockerコンテナ、本番はAurora MySQL） |
| ジョブキュー | Solid Queue（Rails 8の標準機能） |
| リアルタイム通信 | Solid Cable（ActionCable） |
| ファイルストレージ | ActiveStorageとaws-sdk-s3を併用してS3へ保存します（開発環境ではS3互換のMinIOを使用します。バイナリはS3 Multipart Upload Copyで再結合します） |
| ファイル分類 | Marcel + 拡張子チェックでCSVとバイナリを判別し、CSVはヘッダ整合性も検証します |
| フロントエンド | Vite 7 + React 19 + TypeScript + Tailwind CSS v4 + react-dropzone |
| 認証 | DeviseとDevise-JWTを組み合わせたBearerトークン認証です（トランザクションでJWT発行失敗時のorphan accountを防止しています） |
| 型検査 | Sorbetを`typed: true`で適用し、Tapiocaで型定義を生成しています |
| リント・フォーマット | RuboCop（omakase）、Syntax Tree、ESLint、Prettier、Stylelint、erb_lintを使用しています |
| シークレット検査 | gitleaksをpre-commitとGitHub Actions CIで実行しています |
| テスト | RSpec（71件のテスト）とPlaywright E2E（5シナリオ）で検証しています |
| ローカルCI | lefthookによるpre-commitフックとpre-pushフックを設定しています |
| インフラ | Terraformを8モジュールに分割し、ECS FargateとDockerマルチステージビルドで構成しています |

## 前提条件

以下のツールが事前にインストールされている必要があります。

- macOS（Apple Silicon）またはLinux
- miseによるRuby 3.4.11の管理（ https://mise.jdx.dev/ ）
- Docker Desktop（MySQL 8.0のコンテナを`mysql8-mysql-1`という名前で起動し、`mysql8_default`ネットワークに接続しておきます）
- Node.js 22以降とpnpm 10以降
- lefthook（`brew install lefthook`でインストールできます）
- Terraform 1.11以降（インフラの検証に使用します）

## セットアップ手順

以下のコマンドで初回セットアップをすべて実行できます。

```bash
make setup
```

手動でセットアップする場合は、以下の順序で実行してください。

```bash
# Rubyの依存パッケージをインストールします
bundle install

# MinIOコンテナを起動します（S3互換のストレージとして使用します）
docker compose up -d

# データベースを作成し、マイグレーションを実行します
bin/rails db:prepare

# フロントエンドの依存パッケージをインストールします
pnpm --dir frontend install --frozen-lockfile

# Gitフックを登録します
lefthook install
```

## 開発サーバーの起動方法

以下のコマンドで、Railsサーバー（ポート3000）、Solid Queueワーカー、Vite開発サーバー（ポート5173）が同時に起動します。

```bash
make dev
```

起動後は、ブラウザで http://localhost:5173 を開いてください。

## makeターゲットの一覧

| ターゲット | 説明 |
|---|---|
| `make setup` | 初回セットアップを実行します（bundle、pnpm、DB作成、Docker起動、フック登録） |
| `make dev` | 開発サーバーを起動します（Rails + Vite + ワーカー） |
| `make test` | RSpecテストを実行します |
| `make e2e` | Playwright E2Eテストを実行します |
| `make quality` | 8種類の品質チェックを一括で実行します |
| `make lint` | RuboCopとESLintのみを実行します |
| `make typecheck` | SorbetとTypeScriptの型検査を実行します |
| `make format` | RubyファイルをSyntax Treeで、JS/TSファイルをPrettierで自動整形します |
| `make up` | MinIO（S3互換）のDockerコンテナを起動します |
| `make down` | MinIO（S3互換）のDockerコンテナを停止します |
| `make migrate` | データベースマイグレーションを実行します |
| `make console` | Railsコンソールを開きます |
| `make build` | 本番用のDockerイメージ（webとworker）をビルドします |
| `make tf.init` | Terraformの初期化を実行します（dev環境） |
| `make tf.plan` | Terraformのプランを実行します（dev環境） |
| `make clean` | 一時ファイルやログ、カバレッジレポートを削除します |

## 処理の流れ

### 共通フロー

1. フロントエンドのSPAからmultipartのPOSTリクエストで`/api/v1/file_imports`にファイルを送信します
2. UploadFileClassifierがMarcelとファイル拡張子からCSV/バイナリを判別し、CSVの場合はヘッダ行が`target_kind`と整合するかも検証します（不整合時は`CsvHeaderMismatch`で422を返します）
3. RailsのコントローラがFileImportレコードを作成し、ActiveStorageを通じてS3に原本を保存します。`input_kind`（`csv`または`binary`）と`target_kind`（`sales_record`、`ledger_entry`、`binary_asset`）はDBバリデーションで整合性が担保されます
4. FileImportJob（親ジョブ）がImportSourceOpener経由で原本を開き、ImportSplitterに委譲してチャンク分割します
5. 各チャンクに対して`ImportChunkJobFactory`がCSV用`CsvChunkJob`またはバイナリ用`BinaryChunkJob`を選んで起動します
6. FileImportFinalizerJobが全チャンクの結果を集約し、最終ステータスを確定します
7. 各フェーズでActionCableを通じてリアルタイムの進捗イベントをブロードキャストします

### CSVインポート

- CsvChunkSplitterがファイルを2000行単位でS3へ分割アップロードします
- CsvChunkJobがS3からチャンクを取得し、CsvRowMapperが各行の型変換とバリデーションを実施、ActiveRecordモデルの`valid?`で整合性を検証します
- 有効な行のみを100件ずつ`upsert_all`でデータベースに投入します
- ファイルあたりの`idempotency_key`（SHA256）と各行の冪等キーで、ジョブ再実行時のレコード重複を防止します

### バイナリインポート

- BinaryChunkSplitterがファイルを8MB単位（DEFAULT_CHUNK_BYTES）に分割し、各チャンクをS3へputしながらSHA-256ダイジェストを更新して`source_checksum`を記録します
- BinaryChunkJobがチャンクごとにS3からストリーミングでSHA-256を再計算し、`file_import_chunks.checksum`に記録します
- 全チャンクが`completed`になったらFileImportFinalizerJobがBinaryFileReassemblerを呼び出し、S3 `UploadPartCopy` ベースのマルチパート再構成（チャンクごとのCopySource指定で、ローカル一時ファイルに書き戻さない）で1オブジェクトに統合します
- 再構成オブジェクトのキーは決定的（`reassembled-<file_import_id>.bin`）で、元のファイル名はS3オブジェクトメタデータ`original_filename`に格納します
- チャンクの連続性（`chunk_index`の通番、`start_byte`/`end_byte`の隙間なし）と`source_checksum`の一致を検証し、不整合時は`ChecksumMismatch`/`MissingSourceChecksum`/`ArgumentError`で失敗させます
- 結果は`BinaryAsset`レコードに保存します。`idempotency_key`のDB unique制約で同時finalizer実行時の冪等性を保証します

## OOM対策について

このアプリケーションでは、以下の方法でメモリ消費を抑制しています。

- CSVはファイル全体をメモリに読み込まず、`IO#each_line`でストリーミング処理します
- バイナリは8MB単位で`IO#read`しながらS3 `put_object`し、`Digest::SHA256`をストリーム更新します
- バイナリのチェックサム再計算もS3レスポンスを1MBずつ`read`して`Digest`に流すことで、巨大ファイルでもメモリピークが固定です
- 再構成はS3の`UploadPartCopy`を使い、ワーカープロセスにファイル本体をダウンロードしません
- データベースへの投入は100行ずつ`upsert_all`でバッチ処理します
- Solid Queueのconcurrency設定でワーカーの同時実行数を制御します
- ECSのエフェメラルストレージには依存せず、すべてS3を経由します

## 冪等性の保証について

- CSVの各行にはSHA-256ハッシュによる`idempotency_key`を付与しています。MySQLのUNIQUEインデックスと`upsert_all`（ON DUPLICATE KEY UPDATE）の組み合わせにより、ジョブが再実行された場合でもレコードが重複することはありません
- BinaryChunkJobは行ロック（`SELECT ... FOR UPDATE`）を`ActiveRecord::Base.transaction`で囲み、TOCTOUを排除した上で`status: "processing"`に遷移させます
- BinaryAssetは`idempotency_key`のunique indexに依存して`find_by` → `create!`/`update!`に分岐し、`ActiveRecord::RecordNotUnique`は1度だけリトライして既存行を更新するため、FileImportFinalizerJobが冪等に再実行できます
- BinaryFileReassemblerはチャンクの`chunk_index`の通番性、`start_byte`/`end_byte`の隙間がないこと、`source_checksum`の一致を毎回検証してから再構成するため、途中で再実行されても整合性を破壊しません
- 完了済みのチャンクおよびすでに`completed`になったFileImport+BinaryAssetは処理をスキップするため、Solid Queueのat-least-once配送に対しても安全です

## 監査ログについて

`AUDIT`プレフィックス付きのJSON形式で以下のイベントを記録しています。

- 認証に関するイベント（サインイン成功と失敗、サインアップ成功と失敗、サインアウト）
- CSV/バイナリインポートの操作イベント（作成、リトライ、認可拒否）
- チャンク処理の結果イベント（完了、エラー付き完了、失敗）
- バイナリ再構成イベント（成功、失敗）
- インポートの最終集約イベント

パスワード、JWTトークンの本体、CSVの行データ、ファイル内容は一切ログに出力されません。

認証失敗時の`reasons`にはバリデーション属性名（例: `[:email, :password]`）のみを記録しており、`errors.full_messages`に含まれ得るユーザー入力（例: 入力されたメールアドレス）はログに残しません。

## サプライチェーン攻撃への対策について

- `frontend/pnpm-workspace.yaml`で`minimumReleaseAge: 10080`（7日間）を設定しています。依存を解決するとき（`pnpm add`や`pnpm update`）、npm registryに公開されてから7日未満の版は選ばれません。lockfileにすでに載っている版は、`pnpm install --frozen-lockfile`でそのまま入ります
- gitleaksをlefthookのpre-commitフックとGitHub ActionsのCI（`gitleaks`ジョブ）で実行し、シークレットの混入を二重に防止しています。`pull-requests: write`権限はgitleaksジョブのみに限定し、他のジョブには付与していません
- Brakemanとbundler-auditをCIで毎回走らせ、Rails脆弱性とgemのCVEを検出します
- Dependabotがbundler/npm/GitHub Actionsの依存パッケージを継続的に更新します

## テストの実行方法

```bash
# RSpecテスト（71件のテストケース：CSV分割、バイナリ分割、再構成、Finalizer、認証、ファイル分類など）を実行します
make test

# Playwright E2Eテスト（5シナリオ：認証、CSVアップロード、エラー行、複数ユーザー分離など）を実行します
make e2e

# 8種類の品質チェックを一括で実行します
make quality
```

## ベンチマークの実行方法

実際のサーバとSolid Queueワーカーを動かし、アップロードからインポート完了までの時間と、プロセスのRSSを計測します。`script/bench/` 配下のスクリプトは、次の4つをまとめて実行します。

- 合成したCSVと画像の生成
- APIを通したアップロード
- ステータスのポーリング
- WorkerとPumaのメモリのピークの取得

### 前提

- `make setup` が終わっていること（MinIOとMySQLのコンテナを起動し、`bin/rails db:prepare` を完了した状態）
- `make dev` で、Rails、Solid Queue、Viteが起動していること

### 一括実行

```bash
script/bench/run.sh all
```

スクリプトは最初に、`registrations` のエンドポイントでベンチ用のユーザー（`bench@example.com / Password1!`）を自動的に作り、取得したJWTを `tmp/bench/token.txt` に保存します。続けて10万行のCSV、100万行のCSV、5MBの画像、300MBの画像の4ケースを順に実行し、各ケースの結果を `tmp/bench/results/result_<label>.txt` に書き出します。レポートを表示するのは、最後に動く `script/bench/summarize.rb` です。

### 個別ケース

```bash
script/bench/run.sh csv_100k
script/bench/run.sh csv_1m
script/bench/run.sh img_small
script/bench/run.sh img_large
```

### 環境変数

| 変数 | 既定値 | 用途 |
|---|---|---|
| `BENCH_BASE` | `http://localhost:3000` | API ベース URL |
| `BENCH_OUT` | `tmp/bench/results` | 結果ファイル出力先 |
| `BENCH_DATA` | `tmp/bench` | 合成データ・トークン保存先 |
| `BENCH_TOKEN` | (未設定) | 既存 JWT を直接渡したいとき |
| `BENCH_USER_EMAIL` / `BENCH_USER_PASSWORD` | `bench@example.com` / `Password1!` | ベンチユーザー |

### 出力フォーマット

`summarize.rb` は各ケースについて次を出します。

- 時間 アップロード、分割、DBへの投入（バイナリは再結合）、全体のそれぞれにかかった時間
- 失敗 CSVは失敗した行、バイナリは失敗したバイト
- 件数 DBに投入した件数とチャンク数
- メモリ WorkerとPumaのRSS（before、peak、after、delta）
- スループット CSVは1秒あたりの行数、バイナリは1秒あたりのMB数

### ベンチデータと合成器

| スクリプト | 役割 |
|---|---|
| `script/bench/gen_csv.rb`   | sales_record 用の妥当な CSV を任意行数で生成 |
| `script/bench/gen_image.rb` | Marcel が JPEG として認識する任意サイズのバイナリを生成 |
| `script/bench/run_one.sh`   | 1 ケース分のアップロード + RSS サンプリング + 結果ファイル書き出し |
| `script/bench/run.sh`       | データ準備 + トークン取得 + 全ケース実行 + 集計 |
| `script/bench/summarize.rb` | DB の FileImport / chunks と結果ファイルを突き合わせて整形 |

## 本番イメージのビルド方法

以下のコマンドで、webとworkerの2つのDockerイメージをビルドできます。

```bash
make build
```

Dockerfileは6ステージのマルチステージビルドで構成されています。最終イメージにはビルドツール、node_modules、テストコードは含まれません。

## Terraformによるインフラ管理

以下のコマンドで、開発環境のインフラ設定を検証できます。

```bash
make tf.init      # Terraformの初期化を実行します
make tf.validate  # 設定ファイルの構文検証を実行します
make tf.plan      # インフラの変更計画を確認します
```

本番環境（prod）のstateはS3に暗号化して置き、S3のロックファイルで排他制御します。バケット名とリージョンはリポジトリに置かず、初期化のときに渡します。バケットはバージョニングを有効にして事前に作成してください。

```bash
terraform -chdir=infra/terraform/envs/prod init \
  -backend-config="bucket=<stateを置くS3バケット名>" \
  -backend-config="region=<バケットのリージョン>"
```

本番環境は専用のcredentials（`config/credentials/production.yml.enc`）を使います。`rails_master_key`には`config/credentials/production.key`の値を渡してください。`config/master.key`の値では本番のcredentialsを復号できません。`production.key`はリポジトリに含めず、パスワードマネージャーで共有してください。

`rails_master_key`はstateにもplanファイルにも保存されません。planとapplyのたびに環境変数で渡してください。

```bash
export TF_VAR_rails_master_key="$(cat config/credentials/production.key)"
terraform -chdir=infra/terraform/envs/prod plan
```

鍵を替えたときは、`main.tf`の`secret_string_wo_version`の数を1つ上げてからapplyします。

8つのモジュール（network、rds_aurora、s3_csv_bucket、iam、ecs_cluster、ecs_service_web、ecs_service_worker、observability）で構成されており、すべてのモジュールはvariables.tfで入力を受け取り、outputs.tfで出力を公開しています。

## ライセンス

MITライセンスで公開しています。
