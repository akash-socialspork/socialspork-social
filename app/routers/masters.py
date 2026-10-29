from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.engine import Connection

from app.db import fetch_all, fetch_one, get_db

router = APIRouter(tags=["masters"])


@router.get("/industries")
def list_industries(db: Connection = Depends(get_db)):
    return fetch_all(db, "SELECT id, code, name FROM industries WHERE is_active ORDER BY name")


@router.get("/platforms")
def list_platforms(db: Connection = Depends(get_db)):
    return fetch_all(db, "SELECT * FROM platforms WHERE is_active ORDER BY id")


@router.get("/modules")
def list_modules(db: Connection = Depends(get_db)):
    return fetch_all(db, "SELECT * FROM modules WHERE is_active ORDER BY sort_order")


@router.get("/kpis")
def list_kpis(db: Connection = Depends(get_db)):
    return fetch_all(
        db,
        """SELECT k.id, k.code, k.name, k.unit, k.aggregation, k.higher_is_better, m.code AS module
           FROM kpi_definitions k JOIN modules m ON m.id = k.module_id
           WHERE k.is_active ORDER BY m.sort_order, k.id""",
    )


@router.get("/widget-types")
def list_widget_types(db: Connection = Depends(get_db)):
    return fetch_all(db, "SELECT * FROM widget_types ORDER BY id")


@router.get("/industries/{code}/config")
def industry_config(code: str, db: Connection = Depends(get_db)):
    """Default modules, platforms, KPIs and review topics for an industry."""
    industry = fetch_one(db, "SELECT id, code, name FROM industries WHERE code = :code", code=code)
    if not industry:
        raise HTTPException(404, "Industry not found")
    iid = industry["id"]
    return {
        "industry": industry,
        "modules": fetch_all(
            db,
            """SELECT m.code, m.name, m.scope FROM industry_modules im
               JOIN modules m ON m.id = im.module_id
               WHERE im.industry_id = :iid ORDER BY m.sort_order""",
            iid=iid,
        ),
        "platforms": fetch_all(
            db,
            """SELECT p.code, p.name, p.category FROM industry_platforms ip
               JOIN platforms p ON p.id = ip.platform_id
               WHERE ip.industry_id = :iid ORDER BY p.id""",
            iid=iid,
        ),
        "kpis": fetch_all(
            db,
            """SELECT k.code, k.name, k.unit, m.code AS module FROM industry_kpis ik
               JOIN kpi_definitions k ON k.id = ik.kpi_id
               JOIN modules m ON m.id = k.module_id
               WHERE ik.industry_id = :iid ORDER BY ik.sort_order""",
            iid=iid,
        ),
        "review_topics": fetch_all(
            db,
            """SELECT code, name FROM review_topics
               WHERE industry_id = :iid OR industry_id IS NULL ORDER BY industry_id NULLS FIRST, id""",
            iid=iid,
        ),
    }
