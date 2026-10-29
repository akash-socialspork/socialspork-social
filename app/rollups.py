"""Turn raw rows (reviews, orders, status events) into daily KPI values in metric_daily."""

from datetime import date

from sqlalchemy import text
from sqlalchemy.engine import Connection

# kpi code -> SQL expression over one location/platform/day group of reviews
_REVIEW_KPIS = {
    "avg_rating": "AVG(r.rating)",
    "review_count": "COUNT(*)",
    "positive_review_pct": "100.0 * COUNT(*) FILTER (WHERE r.rating >= 4) / COUNT(*)",
    "negative_review_count": "COUNT(*) FILTER (WHERE r.rating <= 2)",
    "response_rate": "100.0 * COUNT(*) FILTER (WHERE r.reply_status = 'replied') / COUNT(*)",
}


def rollup_review_metrics(conn: Connection, brand_id: int, start: date, end: date) -> int:
    written = 0
    for code, expr in _REVIEW_KPIS.items():
        result = conn.execute(
            text(f"""
                INSERT INTO metric_daily (location_id, platform_id, kpi_id, metric_date, value, weight)
                SELECT r.location_id, r.platform_id, k.id,
                       (r.reviewed_at AT TIME ZONE l.timezone)::date AS d,
                       {expr}, COUNT(*)
                FROM reviews r
                JOIN locations l ON l.id = r.location_id
                CROSS JOIN (SELECT id FROM kpi_definitions WHERE code = :code) k
                WHERE l.brand_id = :brand_id
                  AND (r.reviewed_at AT TIME ZONE l.timezone)::date BETWEEN :start AND :end
                GROUP BY r.location_id, r.platform_id, k.id, d
                ON CONFLICT (location_id, platform_id, kpi_id, metric_date)
                DO UPDATE SET value = EXCLUDED.value, weight = EXCLUDED.weight, updated_at = now()
            """),
            dict(code=code, brand_id=brand_id, start=start, end=end),
        )
        written += result.rowcount
    return written
