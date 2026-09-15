#!/usr/bin/env bash
set -euo pipefail

APP_DIR="/opt/kebun-app/administrasi-perkebunan-v70-vps/02-vps-selfhost"
LOCK_FILE="/tmp/kebun-auto-deploy.lock"

exec 9>"$LOCK_FILE"
flock -n 9 || exit 0

cd "$APP_DIR"

# Jangan deploy jika ada perubahan lokal pada file yang dilacak Git.
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
  echo "[$(date '+%F %T')] SKIP: ada perubahan lokal yang belum di-commit."
  exit 1
fi

git fetch origin main --quiet
LOCAL_HEAD="$(git rev-parse HEAD)"
REMOTE_HEAD="$(git rev-parse origin/main)"

if [ "$LOCAL_HEAD" = "$REMOTE_HEAD" ]; then
  exit 0
fi

STAMP="$(date '+%Y-%m-%d_%H-%M-%S')"
echo "[$(date '+%F %T')] Update ditemukan: $LOCAL_HEAD -> $REMOTE_HEAD"

# Backup database/uploads sebelum perubahan source diterapkan.
if [ -f scripts/backup.sh ]; then
  echo "[$(date '+%F %T')] Menjalankan backup..."
  bash scripts/backup.sh
fi

# Ambil source terbaru hanya dengan fast-forward.
git merge --ff-only origin/main

# Build dulu. Jika build gagal, source dikembalikan ke commit lama dan app lama tetap berjalan.
if ! docker compose build app; then
  echo "[$(date '+%F %T')] BUILD GAGAL. Rollback source ke $LOCAL_HEAD"
  git reset --hard "$LOCAL_HEAD"
  exit 1
fi

# Jalankan container baru setelah build sukses.
docker compose up -d app

# Health check sederhana ke aplikasi lokal.
if command -v curl >/dev/null 2>&1; then
  HEALTHY=0
  for _ in $(seq 1 30); do
    if curl -fsS --max-time 3 http://127.0.0.1:8088/ >/dev/null 2>&1; then
      HEALTHY=1
      break
    fi
    sleep 2
  done

  if [ "$HEALTHY" -ne 1 ]; then
    echo "[$(date '+%F %T')] HEALTH CHECK GAGAL. Rollback ke $LOCAL_HEAD"
    git reset --hard "$LOCAL_HEAD"
    docker compose build app
    docker compose up -d app
    exit 1
  fi
fi

echo "[$(date '+%F %T')] DEPLOY BERHASIL: $REMOTE_HEAD"
