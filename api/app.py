# api/app.py
import os
import logging
from datetime import date, datetime
from typing import Optional, Dict, Any, List, Set, Tuple

from fastapi import FastAPI, Query, HTTPException, Path
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import create_engine, text
from sqlalchemy.engine import Engine

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("crimeai.api")

# ====== ENV / CONFIG ======
DATABASE_URL = os.getenv(
    "DATABASE_URL",
    "postgresql+psycopg://crimeai:crimeai@db:5432/crime_ai",
)

# CORS ขยายได้ด้วย ENV ถ้าต้องการ
LAN_PREFIX = os.getenv("LAN_PREFIX", "192.168.1.")      # เช่น 192.168.1.
FE_PORT = os.getenv("FE_PORT", "5173")
ALLOW_ORIGINS = [
    "http://api.crimeai.local",
    "http://localhost:5173",
    "http://127.0.0.1:5173",
]

ALLOW_ORIGIN_REGEX = rf"^http://{LAN_PREFIX.replace('.', r'\.')}\d+:{FE_PORT}$"

app = FastAPI(title="CrimeSenseAI API", version="2025.08.10")

# ====== DB ======
def make_engine(url: str) -> Engine:
    return create_engine(
        url,
        pool_size=10,
        max_overflow=20,
        pool_pre_ping=True,
        pool_recycle=1800,
        future=True,
    )

engine: Engine = make_engine(DATABASE_URL)

# ====== CORS ======
app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOW_ORIGINS,
    allow_origin_regex=ALLOW_ORIGIN_REGEX,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ====== Utilities ======
def _existing_columns(conn, table: str) -> Set[str]:
    rows = conn.execute(
        text(
            """
            SELECT column_name
            FROM information_schema.columns
            WHERE table_schema = 'public' AND table_name = :t
            """
        ),
        {"t": table},
    ).scalars().all()
    return set(rows)

def _build_common_where(params: Dict[str, Any], cols: Set[str]) -> Tuple[str, Dict[str, Any]]:
    """
    WHERE กลางที่อิงคอลัมน์จริง:
      - center -> center_code
      - category -> case_category_name
      - date_from/date_to -> incident_date (cast จาก ::text)
      - q -> ILIKE case_behavior/scene_description
    เงื่อนไขที่อ้างคอลัมน์ไม่มีจริงจะถูกละเว้น
    """
    conds = ["1=1"]
    sql_params: Dict[str, Any] = {}

    if params.get("center") and "center_code" in cols:
        conds.append("center_code = :center")
        sql_params["center"] = params["center"]

    if params.get("category") and "case_category_name" in cols:
        conds.append("case_category_name = :category")
        sql_params["category"] = params["category"]

    has_incident = "incident_date" in cols
    if has_incident and params.get("date_from"):
        conds.append(
            "(incident_date::text ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' "
            "AND CAST(incident_date::text AS date) >= :date_from)"
        )
        sql_params["date_from"] = params["date_from"]
    if has_incident and params.get("date_to"):
        conds.append(
            "(incident_date::text ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' "
            "AND CAST(incident_date::text AS date) <= :date_to)"
        )
        sql_params["date_to"] = params["date_to"]

    if params.get("q"):
        sub = []
        if "case_behavior" in cols:
            sub.append("case_behavior ILIKE :q")
        if "scene_description" in cols:
            sub.append("scene_description ILIKE :q")
        if sub:
            conds.append("(" + " OR ".join(sub) + ")")
            sql_params["q"] = f"%{params['q']}%"

    return " AND ".join(conds), sql_params

def _fetch_list_by_cols(conn, code_col: str, name_col: str, where_sql: str, sql_params: Dict[str, Any]) -> List[Dict[str, Any]]:
    """
    รายการ dropdown: fields = code, name, count
    ปลอดภัยเพราะชื่อคอลัมน์ whitelist จากเราเอง
    """
    sql = f"""
        WITH base AS (
            SELECT
                NULLIF(TRIM(({code_col})::text), '') AS code,
                NULLIF(TRIM(({name_col})::text), '') AS name
            FROM cases
            WHERE {where_sql}
        )
        SELECT code, name, COUNT(*) AS count
        FROM base
        WHERE code IS NOT NULL AND name IS NOT NULL
        GROUP BY code, name
        ORDER BY name ASC;
    """
    rows = conn.execute(text(sql), sql_params).mappings().all()
    return [dict(r) for r in rows]

def _fetch_with_fallback(conn, code_col: str, name_col: str, where_sql: str, sql_params: Dict[str, Any]) -> List[Dict[str, Any]]:
    items = _fetch_list_by_cols(conn, code_col, name_col, where_sql, sql_params)
    return items if items else _fetch_list_by_cols(conn, code_col, name_col, "1=1", {})

def _select_list_for_cases(existing: Set[str]) -> str:
    want = [
        ("fids_no", "case_id"),
        ("center_code", "CenterCode"),
        ("case_behavior", "CaseBehavior"),
        ("scene_description", "SceneDescription"),
        ("case_category_name", "CaseCategoryName"),
        ("police_station_name", "PoliceStationName"),
        ("province_name", "ProvinceName"),
        ("amphur_name", "AmphurName"),
        ("tambol_name", "TambolName"),
        ("incident_date", "IncidentDate"),
    ]
    parts = []
    for col, alias in want:
        if col in existing:
            if alias == "case_id":
                parts.append(f"{col} AS {alias}")
            else:
                parts.append(f'{col} AS "{alias}"')
    return ",\n              ".join(parts) if parts else 'fids_no AS case_id'

# ====== Meta / Health ======
@app.get("/", tags=["meta"])
def root():
    return {"name": "CrimeSenseAI API", "ok": True, "time": datetime.now().isoformat()}

@app.get("/health", tags=["meta"])
def health():
    try:
        with engine.begin() as conn:
            ver = conn.execute(text("SELECT version();")).scalar_one()
            now_ = conn.execute(text("SELECT NOW();")).scalar_one()
        return {"status": "ok", "db": "connected", "version": str(ver), "now": str(now_)}
    except Exception as e:
        logger.exception("Health check failed")
        return {"status": "error", "message": str(e)}

# ====== Stats ======
@app.get("/stats", tags=["stats"])
def stats():
    try:
        with engine.begin() as conn:
            c_cases = conn.execute(text("SELECT COUNT(*) FROM cases;")).scalar_one()
            try:
                c_ev = conn.execute(text("SELECT COUNT(*) FROM evidences;")).scalar_one()
            except Exception:
                c_ev = 0
        return {"cases": int(c_cases), "evidences": int(c_ev)}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Stats failed: {e}")

# ====== Cases List ======
@app.get("/cases", tags=["cases"])
def list_cases(
    limit: int = Query(100, ge=1, le=5000),
    offset: int = Query(0, ge=0),
    center: Optional[str] = Query(None, description="center_code"),
    category: Optional[str] = Query(None),
    date_from: Optional[date] = Query(None),
    date_to: Optional[date] = Query(None),
    q: Optional[str] = Query(None, description="ค้นคำ/ประโยคในพฤติการณ์/คำอธิบาย"),
    province: Optional[str] = Query(None),
    amphur: Optional[str] = Query(None),
    tambol: Optional[str] = Query(None),
):
    try:
        with engine.begin() as conn:
            cols = _existing_columns(conn, "cases")
            params = {"center": center, "category": category, "date_from": date_from, "date_to": date_to, "q": q}
            where_sql, sql_params = _build_common_where(params, cols)

            if province and "province_name" in cols:
                where_sql += " AND province_name = :province"
                sql_params["province"] = province
            if amphur and "amphur_name" in cols:
                where_sql += " AND amphur_name = :amphur"
                sql_params["amphur"] = amphur
            if tambol and "tambol_name" in cols:
                where_sql += " AND tambol_name = :tambol"
                sql_params["tambol"] = tambol

            select_list = _select_list_for_cases(cols)
            order_sql = 'ORDER BY "IncidentDate" DESC NULLS LAST' if "incident_date" in cols else ""

            sql = f"""
                WITH base AS (
                    SELECT
                      {select_list}
                    FROM cases
                    WHERE {where_sql}
                )
                SELECT * FROM base
                {order_sql}
                LIMIT :limit OFFSET :offset;
            """
            sql_params.update({"limit": limit, "offset": offset})
            rows = conn.execute(text(sql), sql_params).mappings().all()

            count_sql = f"SELECT COUNT(*) FROM cases WHERE {where_sql};"
            total = conn.execute(text(count_sql), sql_params).scalar_one()

        return {"total": int(total), "items": [dict(r) for r in rows]}
    except Exception as e:
        logger.exception("list_cases failed")
        raise HTTPException(status_code=500, detail=f"/cases failed: {e}")

# ====== Case Detail ======
@app.get("/cases/{case_id}", tags=["cases"])
def get_case_by_id(case_id: str = Path(..., description="รหัสคดี (fids_no หรือ case_id)")):
    try:
        with engine.begin() as conn:
            cols = _existing_columns(conn, "cases")
            id_cols = [c for c in ("fids_no", "case_id") if c in cols]
            if not id_cols:
                raise HTTPException(status_code=500, detail="No id column (fids_no/case_id) in cases")
            where = " OR ".join([f"{c} = :cid" for c in id_cols])
            row = conn.execute(text(f"SELECT * FROM cases WHERE {where} LIMIT 1"), {"cid": case_id}).mappings().first()
            if not row:
                raise HTTPException(status_code=404, detail="Case not found")
            return dict(row)
    except HTTPException:
        raise
    except Exception as e:
        logger.exception("get_case_by_id failed")
        raise HTTPException(status_code=500, detail=f"/cases/{case_id} failed: {e}")

# ====== Filters (Dropdowns) ======
@app.get("/cases/filters", tags=["cases"])
def get_all_filters(
    center: Optional[str] = Query(None, description="center_code"),
    category: Optional[str] = Query(None),
    date_from: Optional[date] = Query(None),
    date_to: Optional[date] = Query(None),
    q: Optional[str] = Query(None, description="free-text search"),
):
    try:
        with engine.begin() as conn:
            cols = _existing_columns(conn, "cases")
            params = {"center": center, "category": category, "date_from": date_from, "date_to": date_to, "q": q}
            where_sql, sql_params = _build_common_where(params, cols)

            def ok(col: str) -> bool:
                return col in cols

            centers = _fetch_with_fallback(conn, "center_code", "center_code", where_sql, sql_params) if ok("center_code") else []
            provinces = _fetch_with_fallback(conn, "province_name", "province_name", where_sql, sql_params) if ok("province_name") else []
            amphurs = _fetch_with_fallback(conn, "amphur_name", "amphur_name", where_sql, sql_params) if ok("amphur_name") else []
            tambols = _fetch_with_fallback(conn, "tambol_name", "tambol_name", where_sql, sql_params) if ok("tambol_name") else []
            categories = _fetch_with_fallback(conn, "case_category_name", "case_category_name", where_sql, sql_params) if ok("case_category_name") else []

            # ---------- years (จาก incident_date หรือ fids_no segment) ----------
            years: List[Dict[str, Any]] = []
            if ok("incident_date") or ok("fids_no"):
                try:
                    year_exprs: List[str] = []
                    if ok("incident_date"):
                        year_exprs.append(
                            "CASE WHEN incident_date::text ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' "
                            "THEN EXTRACT(YEAR FROM CAST(incident_date::text AS date))::int ELSE NULL END"
                        )
                    if ok("fids_no"):
                        year_exprs.append(
                            "CASE WHEN split_part(fids_no,'-',3) ~ '^[0-9]{2}$' "
                            "THEN 1957 + CAST(split_part(fids_no,'-',3) AS int) ELSE NULL END"
                        )
                    year_expr = "COALESCE(" + ", ".join(year_exprs) + ")"

                    years_sql = f"""
                        WITH base AS (
                            SELECT {year_expr} AS yr
                            FROM cases
                            WHERE {where_sql}
                        )
                        SELECT yr AS code, yr AS name, COUNT(*) AS count
                        FROM base
                        WHERE yr IS NOT NULL
                        GROUP BY yr
                        ORDER BY name DESC;
                    """
                    years = [dict(r) for r in conn.execute(text(years_sql), sql_params).mappings().all()]
                    if not years:
                        years_sql_all = f"""
                            WITH base AS (
                                SELECT {year_expr} AS yr
                                FROM cases
                            )
                            SELECT yr AS code, yr AS name, COUNT(*) AS count
                            FROM base
                            WHERE yr IS NOT NULL
                            GROUP BY yr
                            ORDER BY name DESC;
                        """
                        years = [dict(r) for r in conn.execute(text(years_sql_all)).mappings().all()]
                except Exception:
                    years = []

        return {
            "centers": centers,
            "provinces": provinces,
            "amphurs": amphurs,
            "tambols": tambols,
            "categories": categories,
            "years": years,
        }
    except Exception as e:
        logger.exception("filters failed")
        raise HTTPException(status_code=500, detail=f"/cases/filters failed: {e}")

# ====== Simple Lists (split endpoints) ======
@app.get("/cases/centers", tags=["cases"])
def list_centers(
    category: Optional[str] = None,
    date_from: Optional[date] = None,
    date_to: Optional[date] = None,
    q: Optional[str] = None,
):
    with engine.begin() as conn:
        cols = _existing_columns(conn, "cases")
        params = {"center": None, "category": category, "date_from": date_from, "date_to": date_to, "q": q}
        where_sql, sql_params = _build_common_where(params, cols)
        return _fetch_with_fallback(conn, "center_code", "center_code", where_sql, sql_params) if "center_code" in cols else []

@app.get("/cases/provinces", tags=["cases"])
def list_provinces(
    center: Optional[str] = None,
    category: Optional[str] = None,
    date_from: Optional[date] = None,
    date_to: Optional[date] = None,
    q: Optional[str] = None,
):
    with engine.begin() as conn:
        cols = _existing_columns(conn, "cases")
        params = {"center": center, "category": category, "date_from": date_from, "date_to": date_to, "q": q}
        where_sql, sql_params = _build_common_where(params, cols)
        return _fetch_with_fallback(conn, "province_name", "province_name", where_sql, sql_params) if "province_name" in cols else []

@app.get("/cases/amphurs", tags=["cases"])
def list_amphurs(
    province: str = Query(..., description="ชื่อจังหวัด"),
    center: Optional[str] = None,
    category: Optional[str] = None,
    date_from: Optional[date] = None,
    date_to: Optional[date] = None,
    q: Optional[str] = None,
):
    with engine.begin() as conn:
        cols = _existing_columns(conn, "cases")
        params = {"center": center, "category": category, "date_from": date_from, "date_to": date_to, "q": q}
        where_sql, sql_params = _build_common_where(params, cols)
        if "province_name" in cols:
            where_sql = f"{where_sql} AND province_name = :province"
            sql_params["province"] = province
        return _fetch_with_fallback(conn, "amphur_name", "amphur_name", where_sql, sql_params) if "amphur_name" in cols else []

@app.get("/cases/tambols", tags=["cases"])
def list_tambols(
    amphur: str = Query(..., description="ชื่ออำเภอ"),
    province: Optional[str] = None,
    center: Optional[str] = None,
    category: Optional[str] = None,
    date_from: Optional[date] = Query(None),
    date_to: Optional[date] = Query(None),
    q: Optional[str] = Query(None),
):
    with engine.begin() as conn:
        cols = _existing_columns(conn, "cases")
        params = {"center": center, "category": category, "date_from": date_from, "date_to": date_to, "q": q}
        where_sql, sql_params = _build_common_where(params, cols)
        if "amphur_name" in cols:
            where_sql = f"{where_sql} AND amphur_name = :amphur"
            sql_params["amphur"] = amphur
        if province and "province_name" in cols:
            where_sql += " AND province_name = :province"
            sql_params["province"] = province
        return _fetch_with_fallback(conn, "tambol_name", "tambol_name", where_sql, sql_params) if "tambol_name" in cols else []

