-- sql/fts_thai.sql
-- เตรียม Full Text Search เบื้องต้น (ไทยแบบ simple + unaccent)
-- หมายเหตุ: PostgreSQL ยังไม่มี dictionary ภาษาไทยในตัว
-- วิธีนี้ใช้ simple parser + unaccent ช่วยลดรูปคำ

CREATE EXTENSION IF NOT EXISTS unaccent;

-- เพิ่มคอลัมน์ tsvector (ถ้ายังไม่มี)
ALTER TABLE cases
  ADD COLUMN IF NOT EXISTS fts_doc tsvector;

-- อัปเดตค่าเริ่มต้น
UPDATE cases
SET fts_doc = to_tsvector('simple', unaccent(coalesce(case_behavior,'') || ' ' || coalesce(scene_description,'')));

-- สร้าง trigger ให้ปรับอัตโนมัติ
CREATE OR REPLACE FUNCTION cases_fts_update() RETURNS trigger AS $$
BEGIN
  NEW.fts_doc := to_tsvector('simple', unaccent(coalesce(NEW.case_behavior,'') || ' ' || coalesce(NEW.scene_description,'')));
  RETURN NEW;
END
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_cases_fts_update ON cases;
CREATE TRIGGER trg_cases_fts_update
BEFORE INSERT OR UPDATE ON cases
FOR EACH ROW EXECUTE FUNCTION cases_fts_update();

-- ดัชนี GIN
CREATE INDEX IF NOT EXISTS idx_cases_fts ON cases USING GIN (fts_doc);

-- ตัวอย่างค้นหา:
-- SELECT * FROM cases WHERE fts_doc @@ to_tsquery('simple', 'รถ&จักรยานยนต์');

