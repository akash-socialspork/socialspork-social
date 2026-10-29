"""Pull data from a platform connector into our tables."""

import json

from sqlalchemy.engine import Connection

from app.connectors import get_connector
from app.db import execute, fetch_one


def sync_reviews(conn: Connection, listing_id: int) -> dict:
    listing = fetch_one(
        conn,
        """SELECT ll.id, ll.location_id, ll.platform_id, ll.external_id, p.code AS platform,
                  pc.credentials_ref,
                  (SELECT MAX(r.reviewed_at) FROM reviews r WHERE r.listing_id = ll.id) AS last_review_at
           FROM location_listings ll
           JOIN platforms p ON p.id = ll.platform_id
           LEFT JOIN platform_connections pc ON pc.id = ll.connection_id
           WHERE ll.id = :id""",
        id=listing_id,
    )
    if not listing:
        raise LookupError("Listing not found")

    job = fetch_one(
        conn,
        """INSERT INTO sync_jobs (listing_id, job_type, status, started_at)
           VALUES (:id, 'reviews', 'running', now()) RETURNING id""",
        id=listing_id,
    )
    connector = get_connector(listing["platform"], listing["credentials_ref"])
    reviews = connector.fetch_reviews(listing["external_id"], listing["last_review_at"])

    for r in reviews:
        execute(
            conn,
            """INSERT INTO reviews (listing_id, location_id, platform_id, external_review_id, author_name,
                                    rating, title, body, reviewed_at, reply_status, raw)
               VALUES (:listing_id, :location_id, :platform_id, :ext_id, :author, :rating, :title, :body,
                       :reviewed_at, :reply_status, CAST(:raw AS jsonb))
               ON CONFLICT (platform_id, external_review_id) DO UPDATE
               SET rating = EXCLUDED.rating, body = EXCLUDED.body, raw = EXCLUDED.raw,
                   reply_status = CASE WHEN EXCLUDED.reply_status = 'replied' THEN 'replied'
                                       ELSE reviews.reply_status END""",
            listing_id=listing["id"], location_id=listing["location_id"], platform_id=listing["platform_id"],
            ext_id=r.external_review_id, author=r.author_name, rating=r.rating, title=r.title, body=r.body,
            reviewed_at=r.reviewed_at, reply_status="replied" if r.existing_reply else "pending",
            raw=json.dumps(r.raw, default=str),
        )

    execute(
        conn,
        "UPDATE sync_jobs SET status = 'success', records_in = :n, finished_at = now() WHERE id = :id",
        n=len(reviews), id=job["id"],
    )
    return {"listing_id": listing_id, "reviews_synced": len(reviews)}
