-- ===== เดิมของคุณ =====
CREATE INDEX IF NOT EXISTS idx_cases_incident_time ON cases (incident_time DESC);
CREATE INDEX IF NOT EXISTS idx_cases_center        ON cases (center_code);
CREATE INDEX IF NOT EXISTS idx_cases_category      ON cases (case_category_name);
CREATE INDEX IF NOT EXISTS idx_cases_province      ON cases (province_name);
CREATE INDEX IF NOT EXISTS idx_cases_amphur        ON cases (amphur_name);
CREATE INDEX IF NOT EXISTS idx_cases_tambol        ON cases (tambol_name);

-- ===== เพิ่มเติมสำหรับโค้ดล่าสุด =====
-- เราใช้ incident_date แบบ cast จาก text->date บ่อย (filters และปี)
CREATE INDEX IF NOT EXISTS idx_cases_incident_date_txt
ON cases ((CAST(incident_date::text AS date)));

-- ปีจาก fids_no: segment ที่ 3 เป็นเลข 2 หลัก (YY) → ค.ศ. = 1957 + YY
-- ใช้ฟังก์ชันทำความสะอาดตัวเลขให้ปลอดภัยก่อนแปลง
CREATE INDEX IF NOT EXISTS idx_cases_fids_year
ON cases ((1957 + CAST(NULLIF(regexp_replace(split_part(fids_no,'-',3),'[^0-9]','','g'),'') AS int)));

-- (ทางเลือก ถ้าค้น q หนัก ๆ ด้วย ILIKE ให้เปิดส่วนนี้)
-- CREATE EXTENSION IF NOT EXISTS pg_trgm;
-- CREATE INDEX IF NOT EXISTS idx_cases_behavior_trgm ON cases USING gin (case_behavior gin_trgm_ops);
-- CREATE INDEX IF NOT EXISTS idx_cases_scene_trgm    ON cases USING gin (scene_description gin_trgm_ops);

