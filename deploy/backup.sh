#!/usr/bin/env bash
# Nightly database backup to a private R2 bucket, run by cron on the VPS:
#
#   15 2 * * * cd /opt/pennywise/deploy && ./backup.sh >> "$HOME/backup.log" 2>&1
#
# Keeps 7 daily, 4 weekly (Sundays) and 6 monthly (1st) copies. Needs
# rclone on the host (apt install rclone). Restore with:
#   rclone cat r2:BUCKET/daily/<file> | docker compose -f docker-compose.prod.yml exec -T postgres pg_restore -U pennywise -d pennywise --clean --if-exists
# Test a restore every month (on another machine or a scratch database).
set -euo pipefail
cd "$(dirname "$0")"
set -a
# shellcheck disable=SC1091
. ./.env
set +a

: "${BACKUP_R2_BUCKET:?}" "${BACKUP_R2_ACCESS_KEY_ID:?}" "${BACKUP_R2_SECRET_ACCESS_KEY:?}" "${R2_ACCOUNT_ID:?}"

# rclone remote "r2" from environment variables only (nothing on disk).
export RCLONE_CONFIG_R2_TYPE=s3
export RCLONE_CONFIG_R2_PROVIDER=Cloudflare
export RCLONE_CONFIG_R2_ACCESS_KEY_ID="$BACKUP_R2_ACCESS_KEY_ID"
export RCLONE_CONFIG_R2_SECRET_ACCESS_KEY="$BACKUP_R2_SECRET_ACCESS_KEY"
export RCLONE_CONFIG_R2_ENDPOINT="https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com"
export RCLONE_CONFIG_R2_NO_CHECK_BUCKET=true

stamp=$(date -u +%Y-%m-%dT%H%MZ)
file="pennywise-${stamp}.dump"
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

# Custom format: compressed, and pg_restore can restore single tables.
docker compose -f docker-compose.prod.yml exec -T postgres \
	pg_dump -U pennywise -d pennywise --format=custom --no-owner > "$tmp"
test -s "$tmp" || { echo "backup: empty dump" >&2; exit 1; }

rclone copyto "$tmp" "r2:${BACKUP_R2_BUCKET}/daily/${file}"
if [ "$(date -u +%u)" = 7 ]; then
	rclone copyto "$tmp" "r2:${BACKUP_R2_BUCKET}/weekly/${file}"
fi
if [ "$(date -u +%d)" = 01 ]; then
	rclone copyto "$tmp" "r2:${BACKUP_R2_BUCKET}/monthly/${file}"
fi

rclone delete --min-age 7d "r2:${BACKUP_R2_BUCKET}/daily/"
rclone delete --min-age 28d "r2:${BACKUP_R2_BUCKET}/weekly/"
rclone delete --min-age 183d "r2:${BACKUP_R2_BUCKET}/monthly/"
echo "backup: ${file} ($(stat -c %s "$tmp") bytes) uploaded"
