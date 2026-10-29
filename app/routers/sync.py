from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.engine import Connection

from app.db import get_db
from app.sync import sync_reviews

router = APIRouter(tags=["sync"])


@router.post("/listings/{listing_id}/sync/reviews")
def run_review_sync(listing_id: int, db: Connection = Depends(get_db)):
    try:
        return sync_reviews(db, listing_id)
    except LookupError as e:
        raise HTTPException(404, str(e))
    except NotImplementedError as e:
        raise HTTPException(501, str(e))
    except (FileNotFoundError, PermissionError) as e:
        # Missing or expired platform session: needs a refresh, not a code fix
        raise HTTPException(503, str(e))
