#!/usr/bin/env bash
set -euo pipefail

# ====== ปรับค่าตามสภาพแวดล้อมของคุณ ======
PG_CONTAINER="crime_ai_postgres"
PG_DB="crime_ai"
PG_USER="crimeai"

API_HOSTNAME="api.crimeai.local"   # host ใช้กับ reverse proxy
API_URL="http://127.0.0.1"         # ที่ยิงจากเครื่องคุณ
SYNC_PREFIXES='["01-CSI","01-CNT","01-NBI","01-AYA","01-LRI","01-SPK","01-SRI","01-SBR","01-ATG"]'

# ====== 0) Backup ก่อน ======
echo "🗄️  Backup Postgres..."
docker exec -i "$PG_CONTAINER" pg_dump -U "$PG_USER" -d "$PG_DB" -Fc > "backup_${PG_DB}_$(date +%Y%m%d_%H%M%S).dump"
echo "✅ Backup saved: backup_${PG_DB}_*.dump"

# ====== 1) ล้างข้อมูลเก่า (drop & create schema ให้ตรงกับ app.py ปัจจุบัน) ======
echo "🧹 Reset schema..."
docker exec -i "$PG_CONTAINER" psql -U "$PG_USER" -d "$PG_DB" -v ON_ERROR_STOP=1 <<'SQL'
BEGIN;

-- ลบ VIEW/FUNCTION เผื่อมีอยู่ก่อน
DROP VIEW IF EXISTS vw_center_monthly_summary CASCADE;
DROP VIEW IF EXISTS vw_center_summary CASCADE;
DROP VIEW IF EXISTS vw_center_base CASCADE;
DROP FUNCTION IF EXISTS fn_center_summary_between(timestamptz, timestamptz) CASCADE;

-- ลบตารางเก่า
DROP TABLE IF EXISTS evidences CASCADE;
DROP TABLE IF EXISTS cases CASCADE;

-- สร้างตารางใหม่ให้ตรงกับ app.py ล่าสุด
CREATE TABLE cases (
  id BIGSERIAL PRIMARY KEY,
  fids_no TEXT UNIQUE NOT NULL,

  -- ค่าดิบ/รวม เวลา
  case_issue_time timestamptz,
  case_issue_date date,
  case_issue_time_str TEXT,

  case_category_name  TEXT,
  police_station_name TEXT,
  province_name       TEXT,
  amphur_name         TEXT,
  tambol_name         TEXT,
  scene_description   TEXT,
  case_behavior       TEXT,

  center_code TEXT,
  fids_year_ce INT,
  incident_time timestamptz
);

CREATE TABLE evidences (
  id BIGSERIAL PRIMARY KEY,
  fids_no TEXT NOT NULL REFERENCES cases(fids_no) ON DELETE CASCADE,
  evidence_detail TEXT,
  evidence_amount TEXT,
  evidence_unit TEXT
);

-- ดัชนี
CREATE INDEX idx_cases_time_desc ON cases(case_issue_time DESC);
CREATE INDEX idx_cases_incident  ON cases(incident_time DESC);
CREATE INDEX idx_cases_center    ON cases(center_code);
CREATE INDEX idx_cases_category  ON cases(case_category_name);
CREATE INDEX idx_cases_province  ON cases(province_name);

CREATE UNIQUE INDEX evid_uq
  ON evidences (fids_no, evidence_detail, evidence_amount, evidence_unit);
CREATE INDEX idx_evidences_fids_no ON evidences(fids_no);

-- VIEW/FUNCTION สำหรับสรุป
CREATE OR REPLACE VIEW vw_center_base AS
SELECT
  c.fids_no,
  c.center_code,
  COALESCE(c.incident_time, c.case_issue_time) AS eff_time
FROM cases c;

CREATE OR REPLACE VIEW vw_center_summary AS
WITH e AS (
  SELECT fids_no, COUNT(*)::bigint AS evidences_count
  FROM evidences
  GROUP BY fids_no
),
b AS (
  SELECT
    vb.center_code,
    vb.eff_time,
    COALESCE(e.evidences_count, 0) AS evidences_count
  FROM vw_center_base vb
  LEFT JOIN e USING (fids_no)
)
SELECT
  center_code,
  COUNT(*)::bigint AS cases_count,
  SUM(evidences_count)::bigint AS evidences_count,
  MIN(eff_time) AS min_time,
  MAX(eff_time) AS max_time
FROM b
GROUP BY center_code;

CREATE OR REPLACE FUNCTION fn_center_summary_between(
  from_ts timestamptz,
  to_ts   timestamptz
)
RETURNS TABLE (
  center_code TEXT,
  cases_count BIGINT,
  evidences_count BIGINT,
  min_time timestamptz,
  max_time timestamptz
)
LANGUAGE sql
AS $$
  WITH e AS (
    SELECT fids_no, COUNT(*)::bigint AS evidences_count
    FROM evidences
    GROUP BY fids_no
  ),
  b AS (
    SELECT
      vb.center_code,
      vb.eff_time,
      COALESCE(e.evidences_count, 0) AS evidences_count
    FROM vw_center_base vb
    LEFT JOIN e USING (fids_no)
    WHERE vb.eff_time BETWEEN from_ts AND to_ts
  )
  SELECT
    center_code,
    COUNT(*)::bigint AS cases_count,
    SUM(evidences_count)::bigint AS evidences_count,
    MIN(eff_time) AS min_time,
    MAX(eff_time) AS max_time
  FROM b
  GROUP BY center_code
  ORDER BY center_code;
$$;

CREATE OR REPLACE VIEW vw_center_monthly_summary AS
WITH e AS (
  SELECT fids_no, COUNT(*)::bigint AS evidences_count
  FROM evidences
  GROUP BY fids_no
),
b AS (
  SELECT
    vb.center_code,
    date_trunc('month', vb.eff_time) AS month_bucket,
    COALESCE(e.evidences_count, 0) AS evidences_count
  FROM vw_center_base vb
  LEFT JOIN e USING (fids_no)
)
SELECT
  center_code,
  month_bucket,
  COUNT(*)::bigint AS cases_count,
  SUM(evidences_count)::bigint AS evidences_count
FROM b
GROUP BY center_code, month_bucket
ORDER BY center_code, month_bucket;

COMMIT;
SQL

echo "✅ Schema has been reset."

# ====== 2) รีดีพลอย API ให้ใช้ app.py ล่าสุด ======
echo "🐳 Rebuild & restart API..."
docker compose build api
docker compose up -d --force-recreate api

# ====== 3) ยิงซิงก์ใหม่ ======
echo "🔄 Sync from FIDS (prefixes=${SYNC_PREFIXES})..."
curl -sS -X POST -H "Content-Type: application/json" \
  -d "{\"prefixes\": ${SYNC_PREFIXES}}" \
  -H "Host: ${API_HOSTNAME}" "${API_URL}/sync" | jq .

# ====== 4) ตรวจผล ======
echo "📊 /stats"
curl -sS -H "Host: ${API_HOSTNAME}" "${API_URL}/stats" | jq .

echo "📊 /stats/detail"
curl -sS -H "Host: ${API_HOSTNAME}" "${API_URL}/stats/detail" | jq .

echo "📊 /stats/monthly (ตัวอย่าง 10 รายการแรก)"
curl -sS -H "Host: ${API_HOSTNAME}" "${API_URL}/stats/monthly" | jq . | head -n 40

