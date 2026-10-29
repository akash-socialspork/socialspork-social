from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.engine import Connection

from app.db import fetch_all, fetch_one, get_db

router = APIRouter(tags=["tenancy"])


class TenantIn(BaseModel):
    name: str
    slug: str
    type: str = "direct"


class BrandIn(BaseModel):
    name: str
    slug: str
    industry_code: str


class LocationIn(BaseModel):
    name: str
    code: str | None = None
    address: str | None = None
    area: str | None = None
    city: str | None = None
    state: str | None = None
    pincode: str | None = None
    latitude: float | None = None
    longitude: float | None = None
    phone: str | None = None


class ListingIn(BaseModel):
    platform_code: str
    external_id: str
    external_url: str | None = None
    listing_name: str | None = None


# --- tenants ---------------------------------------------------------------

@router.get("/tenants")
def list_tenants(db: Connection = Depends(get_db)):
    return fetch_all(db, "SELECT * FROM tenants ORDER BY id")


@router.post("/tenants", status_code=201)
def create_tenant(body: TenantIn, db: Connection = Depends(get_db)):
    return fetch_one(
        db,
        "INSERT INTO tenants (name, slug, type) VALUES (:name, :slug, :type) RETURNING *",
        **body.model_dump(),
    )


# --- brands ----------------------------------------------------------------

@router.get("/tenants/{tenant_id}/brands")
def list_brands(tenant_id: int, db: Connection = Depends(get_db)):
    return fetch_all(
        db,
        """SELECT b.*, i.code AS industry_code FROM brands b
           JOIN industries i ON i.id = b.industry_id
           WHERE b.tenant_id = :tid ORDER BY b.name""",
        tid=tenant_id,
    )


@router.post("/tenants/{tenant_id}/brands", status_code=201)
def create_brand(tenant_id: int, body: BrandIn, db: Connection = Depends(get_db)):
    industry = fetch_one(db, "SELECT id FROM industries WHERE code = :c", c=body.industry_code)
    if not industry:
        raise HTTPException(400, f"Unknown industry '{body.industry_code}'")
    return fetch_one(
        db,
        """INSERT INTO brands (tenant_id, industry_id, name, slug)
           VALUES (:tid, :iid, :name, :slug) RETURNING *""",
        tid=tenant_id, iid=industry["id"], name=body.name, slug=body.slug,
    )


@router.get("/brands/{brand_id}/config")
def brand_config(brand_id: int, db: Connection = Depends(get_db)):
    """What the frontend should render for this brand: industry defaults + brand overrides."""
    brand = fetch_one(
        db,
        """SELECT b.id, b.name, b.industry_id, i.code AS industry_code, i.name AS industry_name
           FROM brands b JOIN industries i ON i.id = b.industry_id WHERE b.id = :bid""",
        bid=brand_id,
    )
    if not brand:
        raise HTTPException(404, "Brand not found")
    modules = fetch_all(
        db,
        """SELECT m.code, m.name, m.scope,
                  COALESCE(bm.is_enabled, im.module_id IS NOT NULL) AS enabled
           FROM modules m
           LEFT JOIN industry_modules im ON im.module_id = m.id AND im.industry_id = :iid
           LEFT JOIN brand_modules bm ON bm.module_id = m.id AND bm.brand_id = :bid
           WHERE im.module_id IS NOT NULL OR bm.module_id IS NOT NULL
           ORDER BY m.sort_order""",
        iid=brand["industry_id"], bid=brand_id,
    )
    enabled = [m for m in modules if m["enabled"]]
    kpis = fetch_all(
        db,
        """SELECT k.code, k.name, k.unit, k.higher_is_better, m.code AS module
           FROM industry_kpis ik
           JOIN kpi_definitions k ON k.id = ik.kpi_id
           JOIN modules m ON m.id = k.module_id
           WHERE ik.industry_id = :iid AND m.code = ANY(:mods)
           ORDER BY ik.sort_order""",
        iid=brand["industry_id"], mods=[m["code"] for m in enabled],
    )
    connected = fetch_all(
        db,
        """SELECT DISTINCT p.code, p.name FROM location_listings ll
           JOIN locations l ON l.id = ll.location_id
           JOIN platforms p ON p.id = ll.platform_id
           WHERE l.brand_id = :bid AND ll.is_active""",
        bid=brand_id,
    )
    return {"brand": brand, "modules": enabled, "kpis": kpis, "connected_platforms": connected}


# --- locations & listings --------------------------------------------------

@router.get("/brands/{brand_id}/locations")
def list_locations(brand_id: int, db: Connection = Depends(get_db)):
    return fetch_all(db, "SELECT * FROM locations WHERE brand_id = :bid ORDER BY name", bid=brand_id)


@router.post("/brands/{brand_id}/locations", status_code=201)
def create_location(brand_id: int, body: LocationIn, db: Connection = Depends(get_db)):
    return fetch_one(
        db,
        """INSERT INTO locations (brand_id, name, code, address, area, city, state, pincode,
                                  latitude, longitude, phone)
           VALUES (:bid, :name, :code, :address, :area, :city, :state, :pincode,
                   :latitude, :longitude, :phone)
           RETURNING *""",
        bid=brand_id, **body.model_dump(),
    )


@router.get("/locations/{location_id}/listings")
def list_listings(location_id: int, db: Connection = Depends(get_db)):
    return fetch_all(
        db,
        """SELECT ll.*, p.code AS platform_code FROM location_listings ll
           JOIN platforms p ON p.id = ll.platform_id
           WHERE ll.location_id = :lid ORDER BY p.id""",
        lid=location_id,
    )


@router.post("/locations/{location_id}/listings", status_code=201)
def create_listing(location_id: int, body: ListingIn, db: Connection = Depends(get_db)):
    platform = fetch_one(db, "SELECT id FROM platforms WHERE code = :c", c=body.platform_code)
    if not platform:
        raise HTTPException(400, f"Unknown platform '{body.platform_code}'")
    return fetch_one(
        db,
        """INSERT INTO location_listings (location_id, platform_id, external_id, external_url, listing_name)
           VALUES (:lid, :pid, :external_id, :external_url, :listing_name)
           RETURNING *""",
        lid=location_id, pid=platform["id"],
        external_id=body.external_id, external_url=body.external_url, listing_name=body.listing_name,
    )
