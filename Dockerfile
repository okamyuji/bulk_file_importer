# syntax=docker/dockerfile:1
# check=error=true
#
# Docker Hardened Images (DHI) ベースの multi-stage 本番 Dockerfile。
# - builder ステージ: dhi.io/ruby:3.4-debian12-dev / dhi.io/node:22-debian12-dev
#   （apt / shell / bundler / pnpm が利用可能）
# - runtime: dhi.io/ruby:3.4-debian12（distroless：`ruby` バイナリと依存ライブラリ
#   のみで shell も `bundle` バイナリも含まない）
# - 非 root（USER nonroot）、非特権ポート 8080 で listen
# - HEALTHCHECK は orchestrator 側で実装する（runtime に curl/pgrep が無いため）
#
# 注意点（記事「Docker Hardened Images で Dockerfile を移行する」より反映済）：
#   1. CMD は `ruby bin/start.rb` 形式。`bundle exec puma` は distroless で動かない。
#   2. tzinfo-data を Gemfile 無条件で require（システム tzdata が無い）。
#   3. config/puma.rb は `bind` のみ。`port` と併記すると 2 重 bind で死ぬ。
#   4. Gemfile.lock に aarch64-linux と x86_64-linux 両プラットフォーム追加済。
#   5. Gemfile の `ruby` は `~> 3.4` で、-dev と非 -dev のパッチ差を吸収する。
#
# Build:
#   docker login dhi.io
#   docker build -t bulk-file-importer:web .
#   docker build -t bulk-file-importer:worker --target worker .
#
# Run:
#   docker run -p 8080:8080 -e RAILS_MASTER_KEY=<key> bulk-file-importer:web
#   docker run -e RAILS_MASTER_KEY=<key> bulk-file-importer:worker

ARG RUBY_TAG=3.4-debian12
ARG NODE_TAG=22-debian12

# ---------------------------------------------------------------------------
# Stage 1: gems — builder（-dev に apt / bundler / shell が含まれる）
# ---------------------------------------------------------------------------
FROM dhi.io/ruby:${RUBY_TAG}-dev AS gems

USER root
WORKDIR /rails

ENV BUNDLE_DEPLOYMENT=1 \
    BUNDLE_PATH=/rails/vendor/bundle \
    BUNDLE_WITHOUT="development:test"

# native gem ビルドに必要なパッケージ。最終ステージにはもち込まない。
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      build-essential \
      default-libmysqlclient-dev \
      git \
      libyaml-dev \
      pkg-config && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

COPY Gemfile Gemfile.lock ./

# Gemfile.lock の `BUNDLED WITH` 行を読んで、distroless runtime にも同じ bundler を
# 同梱しないと、Bundler の self-manager が auto-switch しようとして失敗する
# (`Kernel.exec: No such file or directory - bin/start.rb`)。
# DHI runtime には gem コマンドは無いが、BUNDLE_PATH 配下にあれば require で解決できる。
RUN BUNDLED_WITH=$(awk '/BUNDLED WITH/{getline; print $1}' Gemfile.lock) && \
    gem install --no-document --install-dir "${BUNDLE_PATH}/ruby/3.4.0" \
      bundler:"${BUNDLED_WITH}"

ENV PATH="${BUNDLE_PATH}/ruby/3.4.0/bin:${PATH}" \
    GEM_PATH="${BUNDLE_PATH}/ruby/3.4.0" \
    GEM_HOME="${BUNDLE_PATH}/ruby/3.4.0"

RUN --mount=type=cache,target=/root/.bundle/cache \
    bundle install --jobs 4 --retry 3 && \
    rm -rf "${BUNDLE_PATH}"/ruby/*/cache \
           "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git \
           "${BUNDLE_PATH}"/ruby/*/gems/*/spec \
           "${BUNDLE_PATH}"/ruby/*/gems/*/test

# ---------------------------------------------------------------------------
# Stage 2: frontend — Vite SPA を node の -dev ビルダーで作る
# ---------------------------------------------------------------------------
FROM dhi.io/node:${NODE_TAG}-dev AS frontend

USER root
WORKDIR /app/frontend

COPY frontend/package.json frontend/pnpm-lock.yaml ./

RUN corepack enable pnpm && \
    pnpm install --frozen-lockfile --ignore-scripts --prod=false

COPY frontend/ ./

RUN pnpm run build && rm -rf node_modules

# ---------------------------------------------------------------------------
# Stage 2.5: native-libs — distroless runtime に持ち込む共有ライブラリだけ集約
# ---------------------------------------------------------------------------
# distroless ベースには `/usr/lib/<arch>-linux-gnu/libmariadb.so.3` が入っていない。
# ビルドターゲットのアーキテクチャ（aarch64-linux-gnu / x86_64-linux-gnu）が
# 異なっても COPY のパスを 1 行で固定できるよう、シェルが使える builder で
# `/opt/native-libs/<arch>-linux-gnu/` 配下に必要な .so だけ集約する。
FROM gems AS native-libs

RUN set -eux; \
    arch_dir=$(ls -d /usr/lib/*-linux-gnu | head -n1); \
    arch_name=$(basename "$arch_dir"); \
    target="/opt/native-libs/${arch_name}"; \
    mkdir -p "$target"; \
    cp -av "$arch_dir/libmariadb.so."* "$target/"

# ---------------------------------------------------------------------------
# Stage 3: build — gems + アプリコード + フロント dist を組み立てて precompile
# ---------------------------------------------------------------------------
FROM gems AS build

ENV RAILS_ENV=production \
    BUNDLE_PATH=/rails/vendor/bundle

COPY . .
COPY --from=frontend /app/frontend/dist /rails/public/

# precompile はダミーの SECRET_KEY_BASE で起動できるように Rails 側で許容済み。
RUN bundle exec bootsnap precompile --gemfile app/ lib/ && \
    SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile && \
    rm -rf tmp/cache tmp/pids log/*.log

# ---------------------------------------------------------------------------
# Stage 4: web — distroless ランタイム。shell も bundle バイナリも無い前提。
# ---------------------------------------------------------------------------
FROM dhi.io/ruby:${RUBY_TAG} AS web

WORKDIR /rails

ENV RAILS_ENV=production \
    RAILS_LOG_TO_STDOUT=1 \
    RAILS_SERVE_STATIC_FILES=1 \
    PORT=8080 \
    BUNDLE_DEPLOYMENT=1 \
    BUNDLE_PATH=/rails/vendor/bundle \
    BUNDLE_WITHOUT="development:test" \
    MALLOC_ARENA_MAX=2 \
    PATH="/rails/vendor/bundle/ruby/3.4.0/bin:${PATH}" \
    GEM_PATH="/rails/vendor/bundle/ruby/3.4.0" \
    GEM_HOME="/rails/vendor/bundle/ruby/3.4.0"

# mysql2 gem は libmariadb.so.3 に動的リンクするが、distroless runtime には
# 含まれない。gems builder で apt インストール済みのものを最終ステージへ持ち込む。
# /usr/lib/<arch>-linux-gnu/ のままだとビルド先のアーキ名が固定されないため、
# 中間ステージで /opt/native-libs/ という固定パスに集約してから distroless
# runtime にコピーする。
COPY --from=native-libs /opt/native-libs/ /usr/lib/

# distroless ベースは標準で nonroot ユーザーが入っている。COPY 時に所有権を合わせ
# ないと書き込み系の処理で `Permission denied` になる。
COPY --from=build --chown=nonroot:nonroot /rails /rails

USER nonroot
EXPOSE 8080

# `ruby bin/start.rb` で Puma を直接ブートする。
# distroless のため、orchestrator 側で `--health-cmd` 等を設定するか、
# Kubernetes liveness probe / ECS health check で /up エンドポイントを叩く。
CMD ["ruby", "bin/start.rb"]

# ---------------------------------------------------------------------------
# Stage 5: worker — Solid Queue。同じ runtime に CMD だけ差し替え。
# ---------------------------------------------------------------------------
FROM web AS worker

EXPOSE 0

CMD ["ruby", "bin/jobs"]
