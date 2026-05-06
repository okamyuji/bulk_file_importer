#!/usr/bin/env bash
# LocalStack init script: create the CSV bucket on startup.
set -euo pipefail

BUCKET="${S3_BUCKET:-bulk-file-importer-dev}"
awslocal s3 mb "s3://${BUCKET}" || true
awslocal s3api put-bucket-versioning --bucket "${BUCKET}" --versioning-configuration Status=Enabled
echo "[localstack] bucket ready: ${BUCKET}"
