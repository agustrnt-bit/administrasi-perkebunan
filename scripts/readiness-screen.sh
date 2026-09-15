#!/usr/bin/env bash
set -euo pipefail

APP_DIR="/opt/kebun-app/administrasi-perkebunan-v70-vps/02-vps-selfhost"
cd "$APP_DIR"

echo "=== ADMINISTRASI PERKEBUNAN · READINESS SCREEN ==="
echo "Waktu: $(date '+%F %T %Z')"
echo

echo "[1] Git / source"
printf "HEAD: "
git log -1 --oneline
printf "Working tree: "
if [ -z "$(git status --porcelain --untracked-files=no)" ]; then echo "CLEAN"; else echo "DIRTY"; git status --short --untracked-files=no; fi
echo

echo "[2] Docker services"
docker compose ps
echo

echo "[3] App local health"
if curl -fsS --max-time 5 http://127.0.0.1:8088/ >/dev/null 2>&1; then
  echo "APP_HTTP=OK"
else
  echo "APP_HTTP=FAIL"
fi
echo

echo "[4] Runtime workspace identity (tanpa menampilkan email/password)"
RUNTIME_USER_ID="$(docker compose exec -T app node -e 'const c=require("node:crypto"); const configured=(process.env.ADMIN_USER_ID||"").trim(); const email=(process.env.ADMIN_EMAIL||"").trim().toLowerCase(); process.stdout.write(configured || c.createHash("sha256").update(email).digest("hex").slice(0,32));' 2>/dev/null || true)"
if [ -n "$RUNTIME_USER_ID" ]; then
  echo "RUNTIME_USER_ID=$RUNTIME_USER_ID"
else
  echo "RUNTIME_USER_ID=UNAVAILABLE"
fi
echo

echo "[5] Database records by logical table"
docker compose exec -T db sh -lc 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -P pager=off -c "SELECT table_name, COUNT(*) AS rows FROM app_records GROUP BY table_name ORDER BY table_name;"'
echo

echo "[6] Core table counts for runtime workspace"
if [ -n "$RUNTIME_USER_ID" ]; then
  docker compose exec -T db sh -lc "psql -U \"\$POSTGRES_USER\" -d \"\$POSTGRES_DB\" -P pager=off -c \"SELECT x.kind, COUNT(r.id) AS rows FROM (VALUES ('kebun'),('accounts'),('transactions'),('accounting_accounts'),('accounting_system_mappings'),('accounting_settings'),('accounting_periods'),('opening_balances'),('suppliers'),('supplier_bills'),('purchase_invoices'),('inventory_groups'),('inventory_items'),('inventory_warehouses'),('inventory_warehouse_balances'),('fixed_asset_groups'),('fixed_assets'),('tbs'),('payroll_runs')) AS x(kind) LEFT JOIN app_records r ON r.table_name = x.kind || ':' || '$RUNTIME_USER_ID' GROUP BY x.kind ORDER BY x.kind;\""
fi
echo

echo "[7] COA integrity for runtime workspace"
if [ -n "$RUNTIME_USER_ID" ]; then
  docker compose exec -T db sh -lc "psql -U \"\$POSTGRES_USER\" -d \"\$POSTGRES_DB\" -P pager=off -c \"SELECT COUNT(*) AS total_coa, COUNT(*) FILTER (WHERE COALESCE((record->>'active')::boolean,true)) AS active_coa, COUNT(*) FILTER (WHERE COALESCE((record->>'level')::int,4)=4 AND COALESCE((record->>'posting')::boolean,true)) AS posting_coa, COUNT(*) FILTER (WHERE COALESCE(record->>'systemKey','') <> '') AS system_coa FROM app_records WHERE table_name='accounting_accounts:' || '$RUNTIME_USER_ID';\""
  docker compose exec -T db sh -lc "psql -U \"\$POSTGRES_USER\" -d \"\$POSTGRES_DB\" -P pager=off -c \"SELECT record->>'code' AS code, record->>'name' AS name, record->>'level' AS level, record->>'systemKey' AS system_key FROM app_records WHERE table_name='accounting_accounts:' || '$RUNTIME_USER_ID' ORDER BY record->>'code' LIMIT 20;\""
fi
echo

echo "[8] Workspace mismatch check"
if [ -n "$RUNTIME_USER_ID" ]; then
  docker compose exec -T db sh -lc "psql -U \"\$POSTGRES_USER\" -d \"\$POSTGRES_DB\" -P pager=off -c \"WITH t AS (SELECT table_name, split_part(table_name, ':', 1) kind, substring(table_name from position(':' in table_name)+1) workspace FROM app_records WHERE table_name LIKE '%:%') SELECT workspace, COUNT(DISTINCT kind) AS logical_tables, COUNT(*) AS records, CASE WHEN workspace='$RUNTIME_USER_ID' THEN 'RUNTIME' ELSE 'OTHER' END AS relation FROM t WHERE kind IN ('kebun','accounts','transactions','accounting_accounts','accounting_system_mappings','accounting_settings','accounting_periods','opening_balances','suppliers','purchase_invoices','inventory_items','fixed_assets','tbs','payroll_runs') GROUP BY workspace ORDER BY relation DESC, records DESC;\""
fi
echo

echo "=== END SCREEN ==="
