from datetime import datetime

from app.config import get_settings
from app.connectors.base import Connector, NormalizedOrder, NormalizedReview, StoreStatus


class SwiggyConnector(Connector):
    """Swiggy partner data. listing external_id = Swiggy restaurant id.

    TODO: plug in your Swiggy APIs. Each method must return the normalized
    dataclasses from base.py; nothing else in the app needs to change.
    """

    platform_code = "swiggy"

    def __init__(self, credentials: dict):
        super().__init__(credentials)
        self.base_url = get_settings().swiggy_base_url

    def fetch_reviews(self, listing_external_id: str, since: datetime | None) -> list[NormalizedReview]:
        raise NotImplementedError("swiggy: wire your reviews API in app/connectors/swiggy.py")

    def fetch_orders(self, listing_external_id: str, since: datetime | None) -> list[NormalizedOrder]:
        raise NotImplementedError("swiggy: wire your orders API in app/connectors/swiggy.py")

    def fetch_store_status(self, listing_external_id: str) -> StoreStatus:
        raise NotImplementedError("swiggy: wire your store status API in app/connectors/swiggy.py")
