"""Load demo data so the dashboard has something to show.

Creates tenant 'demo' with a restaurant brand (Google/Zomato/Swiggy) and a hotel brand
(Google/Tripadvisor/Booking). Re-running wipes and recreates the demo tenant only.

    PYTHONPATH=. ./.venv/bin/python scripts/seed_demo.py
"""

import math
import random
from datetime import date, datetime, time, timedelta, timezone

from sqlalchemy import text

from app.db import engine
from app.rollups import rollup_review_metrics

DAYS = 120
IST = timezone(timedelta(hours=5, minutes=30))
rng = random.Random(42)

BRANDS = [
    {
        "name": "Spice Route Kitchen", "slug": "spice-route", "industry": "restaurant",
        "platforms": ["google", "zomato", "swiggy"],
        "locations": [
            ("Indiranagar", "BLR01", "Bengaluru", 1.10),
            ("Koramangala", "BLR02", "Bengaluru", 1.25),
            ("Connaught Place", "DEL01", "Delhi", 0.95),
            ("Bandra West", "MUM01", "Mumbai", 1.05),
            ("Cyber Hub", "GGN01", "Gurugram", 0.80),
            ("Koregaon Park", "PUN01", "Pune", 0.70),
        ],
    },
    {
        "name": "Harbour Stays", "slug": "harbour-stays", "industry": "hotel",
        "platforms": ["google", "tripadvisor", "booking"],
        "locations": [
            ("Marine Drive", "HS-MUM", "Mumbai", 1.0),
            ("Calangute", "HS-GOA", "Goa", 1.2),
            ("Fort Kochi", "HS-COK", "Kochi", 0.8),
        ],
    },
]

AUTHORS = ["Aarav", "Priya", "Rohan", "Sneha", "Vikram", "Ananya", "Karan", "Isha", "Arjun", "Meera",
           "Rahul", "Neha", "Aditya", "Pooja", "Siddharth", "Kavya", "Nikhil", "Riya", "Manish", "Tanvi"]

REVIEW_TEXT = {
    "restaurant": {
        5: ["Absolutely loved the butter chicken, packed really well.", "Best biryani in the area, generous portion!",
            "Delivery was quick and food was still hot. Will order again.", "Great taste, great value. Paneer tikka was perfect."],
        4: ["Food was tasty, delivery took a little longer than expected.", "Good portion size, dal makhani was rich and creamy.",
            "Nice flavours overall, naan could have been softer."],
        3: ["Average experience. Food was okay but a bit oily.", "Taste was fine, packaging could be better."],
        2: ["Order arrived late and food was cold.", "Portion was smaller than last time for the same price."],
        1: ["Wrong item delivered and no response from the restaurant.", "Missing items in my order, very disappointed.",
            "Food was stale, will not order again."],
    },
    "hotel": {
        5: ["Stunning sea view and very helpful staff.", "Spotless rooms and the breakfast spread was excellent."],
        4: ["Comfortable stay, check-in took a while.", "Great location, room was slightly small."],
        3: ["Decent stay, Wi-Fi was patchy.", "Okay for the price, bathroom needed maintenance."],
        2: ["AC wasn't working properly and it took hours to fix.", "Noisy room near the lift."],
        1: ["Booking was not honoured at check-in. Terrible.", "Room was dirty and staff were rude."],
    },
}

RATING_WEIGHTS = {"google": [3, 4, 8, 25, 60], "zomato": [6, 6, 12, 30, 46], "swiggy": [7, 7, 13, 30, 43],
                  "tripadvisor": [3, 4, 10, 30, 53], "booking": [2, 4, 12, 35, 47]}


def kpi_ids(conn) -> dict[str, int]:
    return {r.code: r.id for r in conn.execute(text("SELECT id, code FROM kpi_definitions"))}


def platform_ids(conn) -> dict[str, int]:
    return {r.code: r.id for r in conn.execute(text("SELECT id, code FROM platforms"))}


def marketplace_day(day_idx: int, d: date, scale: float, platform_share: float) -> dict[str, tuple[float, float | None]]:
    """One outlet/platform/day of marketplace KPIs -> {kpi_code: (value, weight)}."""
    weekend = 1.35 if d.weekday() >= 4 else 1.0
    growth = 1 + day_idx / DAYS * 0.18
    season = 1 + 0.08 * math.sin(day_idx / 9)
    orders = max(5, int(rng.gauss(85, 10) * scale * weekend * growth * season * platform_share))
    aov = rng.uniform(380, 460)
    gross = orders * aov
    cancel_rate = rng.uniform(1.0, 4.5)
    cancelled = orders * cancel_rate / 100
    discount_orders = int(orders * rng.uniform(0.35, 0.6))
    discount = discount_orders * rng.uniform(60, 95)
    impressions = int(orders * rng.uniform(55, 75))
    menu_views = int(impressions * rng.uniform(0.08, 0.12))
    carts = int(menu_views * rng.uniform(0.32, 0.42))
    ad_spend = gross * rng.uniform(0.04, 0.08)
    ad_sales = ad_spend * rng.uniform(4.0, 7.5)
    offline_events = rng.choices([0, 1, 2], [70, 24, 6])[0]
    downtime = offline_events * rng.uniform(8, 35)
    online_pct = max(85.0, 100 - downtime / (14 * 60) * 100 - rng.uniform(0, 1.5))
    return {
        "delivered_orders": (orders, None),
        "gross_revenue": (gross, None),
        "net_revenue": (gross * rng.uniform(0.70, 0.76), None),
        "avg_order_value": (aov, orders),
        "online_pct": (online_pct, 1),
        "avg_prep_time": (rng.gauss(14.5 * 60, 90), orders),
        "mfr_accuracy": (rng.uniform(78, 96), orders),
        "delayed_orders_pct": (rng.uniform(3, 11), orders),
        "cancellation_rate": (cancel_rate, orders),
        "cancellation_loss": (cancelled * aov, None),
        "impressions": (impressions, None),
        "menu_views": (menu_views, None),
        "add_to_cart": (carts, None),
        "funnel_orders": (orders, None),
        "menu_to_order_pct": (orders / max(menu_views, 1) * 100, menu_views),
        "ad_spend": (ad_spend, None),
        "ad_sales": (ad_sales, None),
        "ad_impressions": (int(impressions * rng.uniform(0.3, 0.45)), None),
        "ad_menu_visits": (int(menu_views * rng.uniform(0.3, 0.45)), None),
        "ad_orders": (int(orders * rng.uniform(0.2, 0.32)), None),
        "ad_roi": (ad_sales / ad_spend, ad_spend),
        "discount_given": (discount, None),
        "discount_gross_sales": (discount_orders * aov, None),
        "discounted_orders": (discount_orders, None),
        "discount_per_order": (discount / max(discount_orders, 1), discount_orders),
        "discount_pct_revenue": (discount / gross * 100, gross),
        "offline_events": (offline_events, None),
        "avg_downtime": (downtime / offline_events if offline_events else 0, offline_events or None),
        "downtime_revenue_loss": (downtime / 60 * (gross / 14), None),
        "auto_recovery_pct": (rng.uniform(70, 95), offline_events or None),
        "stock_out_items": (rng.choices([0, 1, 2, 3, 4], [40, 25, 18, 10, 7])[0], None),
    }


def main() -> None:
    today = date.today()
    start = today - timedelta(days=DAYS - 1)
    with engine.begin() as conn:
        conn.execute(text("DELETE FROM tenants WHERE slug = 'demo'"))
        tenant_id = conn.execute(text(
            "INSERT INTO tenants (name, slug, type) VALUES ('SocialSpork Demo', 'demo', 'internal') RETURNING id"
        )).scalar_one()
        kpis, plats = kpi_ids(conn), platform_ids(conn)
        metric_rows, review_rows = [], []

        for b in BRANDS:
            brand_id = conn.execute(text(
                """INSERT INTO brands (tenant_id, industry_id, name, slug)
                   SELECT :t, id, :n, :s FROM industries WHERE code = :i RETURNING id"""
            ), dict(t=tenant_id, n=b["name"], s=b["slug"], i=b["industry"])).scalar_one()

            for area, code, city, scale in b["locations"]:
                loc_id = conn.execute(text(
                    """INSERT INTO locations (brand_id, name, code, area, city) VALUES (:b, :n, :c, :a, :city)
                       RETURNING id"""
                ), dict(b=brand_id, n=f"{b['name']} - {area}", c=code, a=area, city=city)).scalar_one()

                for p in b["platforms"]:
                    listing_id = conn.execute(text(
                        """INSERT INTO location_listings (location_id, platform_id, external_id, listing_name, current_status)
                           VALUES (:l, :p, :e, :n, :s) RETURNING id"""
                    ), dict(l=loc_id, p=plats[p], e=f"demo-{p}-{code}", n=f"{b['name']} - {area}",
                            s="online" if rng.random() > 0.1 else "offline")).scalar_one()

                    # reviews
                    per_day = {"google": 1.6, "zomato": 2.2, "swiggy": 2.0, "tripadvisor": 0.7, "booking": 1.1}[p] * scale
                    for day_idx in range(DAYS):
                        d = start + timedelta(days=day_idx)
                        for _ in range(int(per_day + rng.random())):
                            rating = rng.choices([1, 2, 3, 4, 5], RATING_WEIGHTS[p])[0]
                            ts = min(datetime.combine(d, time(rng.randint(9, 23), rng.randint(0, 59)), IST),
                                     datetime.now(IST) - timedelta(minutes=rng.randint(5, 600)))
                            age = (today - d).days
                            status = "pending" if age < 3 and rng.random() < 0.7 else (
                                "replied" if rng.random() < (0.92 if rating <= 2 else 0.75) else "pending")
                            review_rows.append(dict(
                                li=listing_id, lo=loc_id, p=plats[p], e=f"demo-{listing_id}-{len(review_rows)}",
                                a=f"{rng.choice(AUTHORS)} {rng.choice('ABDKMPRSV')}.", r=rating,
                                b=rng.choice(REVIEW_TEXT[b["industry"]][rating]) if rng.random() < 0.8 else None,
                                t=ts, s=status,
                                sent="positive" if rating >= 4 else "neutral" if rating == 3 else "negative",
                            ))

                    # marketplace KPIs
                    if b["industry"] == "restaurant" and p in ("zomato", "swiggy"):
                        share = 0.55 if p == "zomato" else 0.45
                        for day_idx in range(DAYS):
                            d = start + timedelta(days=day_idx)
                            for code_, (val, w) in marketplace_day(day_idx, d, scale, share).items():
                                metric_rows.append(dict(l=loc_id, p=plats[p], k=kpis[code_], d=d, v=round(val, 4), w=w))

                    # platform rating snapshot
                    rating_now = round(rng.uniform(3.9, 4.6), 1)
                    for day_idx in range(0, DAYS, 7):
                        d = start + timedelta(days=day_idx)
                        metric_rows.append(dict(l=loc_id, p=plats[p], k=kpis["listing_rating"], d=d,
                                                v=round(rating_now - 0.2 + 0.2 * day_idx / DAYS, 2), w=None))
                        metric_rows.append(dict(l=loc_id, p=plats[p], k=kpis["total_reviews"], d=d,
                                                v=int(800 * scale + day_idx * per_day), w=None))
                    conn.execute(text("UPDATE location_listings SET current_rating = :r WHERE id = :id"),
                                 dict(r=rating_now, id=listing_id))

            # brand-level open tickets snapshot
            for loc in conn.execute(text("SELECT id FROM locations WHERE brand_id = :b"), dict(b=brand_id)):
                metric_rows.append(dict(l=loc.id, p=None, k=kpis["open_tickets"], d=today, v=rng.randint(0, 6), w=None))

        conn.execute(text(
            """INSERT INTO reviews (listing_id, location_id, platform_id, external_review_id, author_name, rating, body,
                                    reviewed_at, reply_status, sentiment)
               VALUES (:li, :lo, :p, :e, :a, :r, :b, :t, :s, :sent)"""
        ), review_rows)
        conn.execute(text(
            """INSERT INTO metric_daily (location_id, platform_id, kpi_id, metric_date, value, weight)
               VALUES (:l, :p, :k, :d, :v, :w)"""
        ), metric_rows)

        brand_ids = [r.id for r in conn.execute(text("SELECT id FROM brands WHERE tenant_id = :t"), dict(t=tenant_id))]
        rolled = sum(rollup_review_metrics(conn, bid, start, today) for bid in brand_ids)

    print(f"demo tenant {tenant_id}: {len(review_rows)} reviews, {len(metric_rows)} metric rows, {rolled} review KPI rows")


if __name__ == "__main__":
    main()
