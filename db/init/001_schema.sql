-- db/init/001_schema.sql
CREATE TABLE IF NOT EXISTS cases (
  id BIGSERIAL PRIMARY KEY,
  fids_no TEXT UNIQUE NOT NULL,
  case_issue_time timestamptz,
  case_category_name TEXT,
  police_station_name TEXT,
  province_name TEXT,
  amphur_name TEXT,
  tambol_name TEXT,
  scene_description TEXT,
  case_behavior TEXT
);

CREATE TABLE IF NOT EXISTS evidences (
  id BIGSERIAL PRIMARY KEY,
  fids_no TEXT NOT NULL REFERENCES cases(fids_no) ON DELETE CASCADE,
  evidence_detail TEXT,
  evidence_amount TEXT,
  evidence_unit TEXT
);

-- index เบื้องต้น
CREATE INDEX IF NOT EXISTS idx_cases_time_desc ON cases(case_issue_time DESC);
CREATE INDEX IF NOT EXISTS idx_cases_category  ON cases(case_category_name);
CREATE INDEX IF NOT EXISTS idx_cases_province  ON cases(province_name);

-- กันซ้ำที่ evidences
CREATE UNIQUE INDEX IF NOT EXISTS evid_uq
ON evidences (fids_no, evidence_detail, evidence_amount, evidence_unit);

