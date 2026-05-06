.DEFAULT_GOAL := help
SHELL := /bin/bash

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------
.PHONY: setup
setup: ## Initial setup (bundle, pnpm, db, docker, hooks)
	bundle install
	bundle exec tapioca gems
	docker compose up -d
	@echo "Waiting for LocalStack…" && sleep 5
	bin/rails db:prepare
	pnpm --dir frontend install --frozen-lockfile
	lefthook install
	@echo "✓ Setup complete. Run 'make dev' to start."

.PHONY: rbi
rbi: ## Regenerate gem RBI files via Tapioca
	bundle exec tapioca gems

# ---------------------------------------------------------------------------
# Development
# ---------------------------------------------------------------------------
.PHONY: dev
dev: ## Start Rails + Solid Queue + Vite (foreman)
	@command -v foreman >/dev/null || bundle exec gem install foreman
	foreman start -f Procfile.dev

.PHONY: console
console: ## Rails console
	bin/rails console

.PHONY: migrate
migrate: ## Run db:migrate
	bin/rails db:migrate

.PHONY: seed
seed: ## Run db:seed
	bin/rails db:seed

# ---------------------------------------------------------------------------
# Docker Compose (LocalStack)
# ---------------------------------------------------------------------------
.PHONY: up
up: ## docker compose up -d
	docker compose up -d

.PHONY: down
down: ## docker compose down
	docker compose down

.PHONY: logs
logs: ## docker compose logs -f
	docker compose logs -f

# ---------------------------------------------------------------------------
# Quality
# ---------------------------------------------------------------------------
.PHONY: quality
quality: ## Run full quality suite (8 tools)
	bin/quality

.PHONY: lint
lint: ## RuboCop + ESLint only
	bundle exec rubocop --parallel
	pnpm --dir frontend run lint

.PHONY: typecheck
typecheck: ## Sorbet + TypeScript
	bundle exec srb tc
	pnpm --dir frontend run typecheck

.PHONY: format
format: ## Auto-format Ruby (stree) + JS/TS (prettier)
	bash -c 'bundle exec stree write $$(git ls-files "*.rb" | grep -v "^sorbet/" | grep -v "^db/migrate/")'
	pnpm --dir frontend run format

.PHONY: format.check
format.check: ## Check formatting without writing
	bash -c 'bundle exec stree check $$(git ls-files "*.rb" | grep -v "^sorbet/" | grep -v "^db/migrate/")'
	pnpm --dir frontend run format:check

# ---------------------------------------------------------------------------
# Test
# ---------------------------------------------------------------------------
.PHONY: test
test: ## Run RSpec
	bundle exec rspec

.PHONY: test.fast
test.fast: ## Run RSpec (fail-fast)
	bundle exec rspec --fail-fast

.PHONY: e2e
e2e: ## Run Playwright E2E tests
	pnpm --dir frontend exec playwright test --config=e2e/playwright.config.ts

.PHONY: e2e.ui
e2e.ui: ## Open Playwright UI mode
	pnpm --dir frontend exec playwright test --config=e2e/playwright.config.ts --ui

# ---------------------------------------------------------------------------
# Build (Docker production images)
# ---------------------------------------------------------------------------
.PHONY: build
build: build.web build.worker ## Build both web and worker images

.PHONY: build.web
build.web: ## Build web Docker image
	docker build --target web -t bulk-file-importer:web .

.PHONY: build.worker
build.worker: ## Build worker Docker image
	docker build --target worker -t bulk-file-importer:worker .

# ---------------------------------------------------------------------------
# Terraform
# ---------------------------------------------------------------------------
TF_DIR ?= infra/terraform/envs/dev

.PHONY: tf.init
tf.init: ## Terraform init
	terraform -chdir=$(TF_DIR) init -backend=false

.PHONY: tf.validate
tf.validate: ## Terraform validate
	terraform -chdir=$(TF_DIR) validate

.PHONY: tf.plan
tf.plan: ## Terraform plan
	terraform -chdir=$(TF_DIR) plan

.PHONY: tf.fmt
tf.fmt: ## Terraform fmt check
	terraform fmt -check -recursive infra/

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------
.PHONY: clean
clean: ## Remove tmp, log, coverage
	rm -rf tmp/cache tmp/pids log/*.log coverage frontend/test-results
	@echo "✓ Cleaned"

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------
.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_.]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'
