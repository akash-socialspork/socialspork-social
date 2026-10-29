from datetime import date, timedelta

from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from sqlalchemy.engine import Connection

from app.connectors import get_connector
from app.db import execute, fetch_all, fetch_one, get_db

router = APIRouter(tags=["reviews"])


class ReplyIn(BaseModel):
    body: str
    source: str = "manual"
    template_id: int | None = None


@router.get("/brands/{brand_id}/reviews")
def list_reviews(
    brand_id: int,
    location_id: int | None = None,
    platform: str | None = None,
    min_rating: float | None = None,
    max_rating: float | None = None,
    sentiment: str | None = None,
    reply_status: str | None = None,
    q: str | None = None,
    limit: int = Query(50, le=200),
    offset: int = 0,
    db: Connection = Depends(get_db),
):
    return fetch_all(
        db,
        """SELECT r.id, r.rating, r.title, r.body, r.author_name, r.reviewed_at, r.sentiment,
                  r.reply_status, p.code AS platform, l.id AS location_id, l.name AS location_name,
                  (SELECT body FROM review_replies rr WHERE rr.review_id = r.id
                   ORDER BY rr.created_at DESC LIMIT 1) AS latest_reply
           FROM reviews r
           JOIN locations l ON l.id = r.location_id
           JOIN platforms p ON p.id = r.platform_id
           WHERE l.brand_id = :brand_id
             AND (CAST(:location_id AS bigint) IS NULL OR r.location_id = :location_id)
             AND (CAST(:platform AS text) IS NULL OR p.code = :platform)
             AND (CAST(:min_rating AS numeric) IS NULL OR r.rating >= :min_rating)
             AND (CAST(:max_rating AS numeric) IS NULL OR r.rating <= :max_rating)
             AND (CAST(:sentiment AS text) IS NULL OR r.sentiment = :sentiment)
             AND (CAST(:reply_status AS text) IS NULL OR r.reply_status = :reply_status)
             AND (CAST(:q AS text) IS NULL OR r.body ILIKE '%' || :q || '%')
           ORDER BY r.reviewed_at DESC
           LIMIT :limit OFFSET :offset""",
        brand_id=brand_id, location_id=location_id, platform=platform, min_rating=min_rating,
        max_rating=max_rating, sentiment=sentiment, reply_status=reply_status, q=q,
        limit=limit, offset=offset,
    )


@router.get("/brands/{brand_id}/reviews/summary")
def reviews_summary(
    brand_id: int,
    start: date = Query(default_factory=lambda: date.today() - timedelta(days=29)),
    end: date = Query(default_factory=date.today),
    db: Connection = Depends(get_db),
):
    params = dict(brand_id=brand_id, start=start, end=end)
    where = """FROM reviews r JOIN locations l ON l.id = r.location_id
               JOIN platforms p ON p.id = r.platform_id
               WHERE l.brand_id = :brand_id
                 AND (r.reviewed_at AT TIME ZONE l.timezone)::date BETWEEN :start AND :end"""
    totals = fetch_one(
        db,
        f"""SELECT COUNT(*) AS total, ROUND(AVG(r.rating), 2) AS avg_rating,
                   COUNT(*) FILTER (WHERE r.reply_status = 'replied') AS replied,
                   COUNT(*) FILTER (WHERE r.reply_status = 'pending') AS pending {where}""",
        **params,
    )
    return {
        **totals,
        "by_rating": fetch_all(
            db, f"SELECT FLOOR(r.rating)::int AS stars, COUNT(*) AS count {where} GROUP BY 1 ORDER BY 1 DESC", **params
        ),
        "by_platform": fetch_all(
            db,
            f"""SELECT p.code AS platform, COUNT(*) AS count, ROUND(AVG(r.rating), 2) AS avg_rating
                {where} GROUP BY p.code ORDER BY count DESC""",
            **params,
        ),
        "by_sentiment": fetch_all(
            db, f"SELECT r.sentiment, COUNT(*) AS count {where} GROUP BY r.sentiment", **params
        ),
    }


@router.post("/reviews/{review_id}/replies", status_code=201)
def create_reply(review_id: int, body: ReplyIn, db: Connection = Depends(get_db)):
    """Save a reply as a draft. Publish it with POST /replies/{id}/publish."""
    if not fetch_one(db, "SELECT 1 FROM reviews WHERE id = :id", id=review_id):
        raise HTTPException(404, "Review not found")
    reply = fetch_one(
        db,
        """INSERT INTO review_replies (review_id, body, source, template_id)
           VALUES (:rid, :body, :source, :template_id) RETURNING *""",
        rid=review_id, **body.model_dump(),
    )
    execute(db, "UPDATE reviews SET reply_status = 'drafted' WHERE id = :id AND reply_status = 'pending'", id=review_id)
    return reply


@router.post("/replies/{reply_id}/publish")
def publish_reply(reply_id: int, db: Connection = Depends(get_db)):
    """Post the reply to the platform through its connector."""
    row = fetch_one(
        db,
        """SELECT rr.id, rr.body, r.id AS review_id, r.external_review_id, p.code AS platform,
                  ll.external_id AS listing_external_id, pc.credentials_ref
           FROM review_replies rr
           JOIN reviews r ON r.id = rr.review_id
           JOIN platforms p ON p.id = r.platform_id
           JOIN location_listings ll ON ll.id = r.listing_id
           LEFT JOIN platform_connections pc ON pc.id = ll.connection_id
           WHERE rr.id = :id""",
        id=reply_id,
    )
    if not row:
        raise HTTPException(404, "Reply not found")
    connector = get_connector(row["platform"], row["credentials_ref"])
    try:
        connector.post_reply(row["listing_external_id"], row["external_review_id"], row["body"])
    except NotImplementedError as e:
        raise HTTPException(501, str(e))
    except Exception as e:
        # Return instead of raising so the failure is committed, not rolled back
        execute(db, "UPDATE review_replies SET status = 'failed', error = :e WHERE id = :id", e=str(e), id=reply_id)
        return JSONResponse({"detail": f"Platform error: {e}"}, status_code=502)
    execute(db, "UPDATE review_replies SET status = 'published', published_at = now() WHERE id = :id", id=reply_id)
    execute(db, "UPDATE reviews SET reply_status = 'replied' WHERE id = :id", id=row["review_id"])
    return {"status": "published"}
