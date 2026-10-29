from datetime import date, timedelta

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.engine import Connection

from app.db import fetch_all, fetch_one, get_db
from app.rollups import rollup_review_metrics

router = APIRouter(tags=["metrics"])

# Aggregates metric_daily rows according to each KPI's aggregation rule.
# 'last' takes each location/platform's latest value in the window, then sums counts or averages the rest.
_AGG_SQL = """
WITH base AS (
  SELECT k.code, k.name, k.unit, k.aggregation, k.higher_is_better, m.code AS module,
         md.metric_date, md.value, COALESCE(md.weight, 1) AS w,
         ROW_NUMBER() OVER (PARTITION BY k.id, md.location_id, md.platform_id {date_part}
                            ORDER BY md.metric_date DESC) AS rn
  FROM metric_daily md
  JOIN kpi_definitions k ON k.id = md.kpi_id
  JOIN modules m ON m.id = k.module_id
  JOIN locations l ON l.id = md.location_id
  LEFT JOIN platforms p ON p.id = md.platform_id
  WHERE l.brand_id = :brand_id
    AND md.metric_date BETWEEN :start AND :end
    AND (CAST(:location_id AS bigint) IS NULL OR md.location_id = :location_id)
    AND (CAST(:platform AS text) IS NULL OR p.code = :platform)
    AND (CAST(:module AS text) IS NULL OR m.code = :module)
    AND (CAST(:kpi AS text) IS NULL OR k.code = :kpi)
)
SELECT code, name, unit, higher_is_better, module {date_select},
  CASE aggregation
    WHEN 'sum'          THEN SUM(value)
    WHEN 'avg'          THEN AVG(value)
    WHEN 'weighted_avg' THEN SUM(value * w) / NULLIF(SUM(w), 0)
    WHEN 'max'          THEN MAX(value)
    WHEN 'min'          THEN MIN(value)
    WHEN 'last'         THEN CASE WHEN unit = 'count' THEN SUM(value) FILTER (WHERE rn = 1)
                                  ELSE AVG(value) FILTER (WHERE rn = 1) END
  END AS value
FROM base
GROUP BY code, name, unit, aggregation, higher_is_better, module {date_select}
ORDER BY module, code {date_select}
"""


def _aggregate(db: Connection, by_date: bool, **params) -> list[dict]:
    sql = _AGG_SQL.format(
        date_part=", md.metric_date" if by_date else "",
        date_select=", metric_date" if by_date else "",
    )
    return fetch_all(db, sql, **params)


def _filters(location_id, platform, module, kpi=None):
    return dict(location_id=location_id, platform=platform, module=module, kpi=kpi)


@router.get("/brands/{brand_id}/kpis")
def brand_kpis(
    brand_id: int,
    start: date = Query(default_factory=lambda: date.today() - timedelta(days=29)),
    end: date = Query(default_factory=date.today),
    location_id: int | None = None,
    platform: str | None = None,
    module: str | None = None,
    db: Connection = Depends(get_db),
):
    """KPI cards: value for the period plus the same-length previous period for comparison."""
    if end < start:
        raise HTTPException(400, "end must be on or after start")
    span = end - start + timedelta(days=1)
    f = _filters(location_id, platform, module)
    current = _aggregate(db, False, brand_id=brand_id, start=start, end=end, **f)
    previous = {
        r["code"]: r["value"]
        for r in _aggregate(db, False, brand_id=brand_id, start=start - span, end=start - timedelta(days=1), **f)
    }
    for r in current:
        prev = previous.get(r["code"])
        r["previous_value"] = prev
        r["change_pct"] = (
            round(float((r["value"] - prev) / abs(prev) * 100), 2)
            if prev not in (None, 0) and r["value"] is not None else None
        )
    return {"start": start, "end": end, "kpis": current}


@router.get("/brands/{brand_id}/kpis/{kpi_code}/trend")
def kpi_trend(
    brand_id: int,
    kpi_code: str,
    start: date = Query(default_factory=lambda: date.today() - timedelta(days=29)),
    end: date = Query(default_factory=date.today),
    location_id: int | None = None,
    platform: str | None = None,
    db: Connection = Depends(get_db),
):
    rows = _aggregate(
        db, True, brand_id=brand_id, start=start, end=end, **_filters(location_id, platform, None, kpi_code)
    )
    return [{"date": r["metric_date"], "value": r["value"]} for r in rows]


@router.get("/brands/{brand_id}/leaderboard/{kpi_code}")
def location_leaderboard(
    brand_id: int,
    kpi_code: str,
    start: date = Query(default_factory=lambda: date.today() - timedelta(days=29)),
    end: date = Query(default_factory=date.today),
    db: Connection = Depends(get_db),
):
    """Rank locations on one KPI."""
    kpi = fetch_one(db, "SELECT higher_is_better FROM kpi_definitions WHERE code = :c", c=kpi_code)
    if not kpi:
        raise HTTPException(404, "KPI not found")
    locations = fetch_all(db, "SELECT id, name, city FROM locations WHERE brand_id = :b AND is_active", b=brand_id)
    rows = []
    for loc in locations:
        agg = _aggregate(
            db, False, brand_id=brand_id, start=start, end=end, **_filters(loc["id"], None, None, kpi_code)
        )
        rows.append({**loc, "value": agg[0]["value"] if agg else None})
    rows.sort(key=lambda r: (r["value"] is None, -(r["value"] or 0) if kpi["higher_is_better"] else (r["value"] or 0)))
    return rows


@router.post("/brands/{brand_id}/rollups/reviews")
def run_review_rollup(
    brand_id: int,
    start: date = Query(default_factory=lambda: date.today() - timedelta(days=89)),
    end: date = Query(default_factory=date.today),
    db: Connection = Depends(get_db),
):
    """Recompute review KPIs in metric_daily from the reviews table."""
    return {"rows_written": rollup_review_metrics(db, brand_id, start, end)}
