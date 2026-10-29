# SocialSpork API

Multi-industry reputation + marketplace intelligence backend (FastAPI + Postgres).

## Setup

```bash
python3.13 -m venv .venv && ./.venv/bin/pip install -r requirements.txt
cp .env.example .env            # then fill in API keys
createdb socialspork
psql -d socialspork -f db/001_schema.sql
psql -d socialspork -f db/002_seed_masters.sql
```

## Run

```bash
PYTHONPATH=. ./.venv/bin/python scripts/seed_demo.py   # optional demo restaurant + hotel brands
./.venv/bin/uvicorn app.main:app --reload --reload-dir app --port 8010
```

Dashboard: http://localhost:8010/ · API docs: http://localhost:8010/docs

The dashboard (`frontend/`) is plain HTML/JS + Chart.js with no build step, served by FastAPI.

## Layout

```
db/                 schema + master seed
app/main.py         FastAPI app
app/routers/        masters, tenancy, reviews, metrics, sync
app/connectors/     one class per platform (google, zomato, swiggy) -> normalized dataclasses
app/sync.py         connector -> reviews table
app/rollups.py      raw rows -> metric_daily KPIs
```

## How the dashboard stays dynamic

- `GET /api/brands/{id}/config` returns the modules + KPIs the frontend should render,
  based on the brand's industry (`industry_modules`, `industry_kpis`) plus `brand_modules` overrides.
- All KPI values live in `metric_daily` and are aggregated by each KPI's `aggregation` rule,
  so `GET /api/brands/{id}/kpis?module=...` works for any industry without new code.

## Adding a platform

1. Insert it into `platforms` (and `industry_platforms`).
2. Subclass `Connector` in `app/connectors/`, return the dataclasses from `base.py`.
3. Register it in `app/connectors/__init__.py`.

Credentials: set `platform_connections.credentials_ref` to
- `env:MY_VAR` – JSON object in `MY_VAR` in `.env` (e.g. `{"access_token": "..."}`), or
- `file:/path/to/creds.json` – JSON file re-read on every call.

Swap for a secrets manager before production.

### Zomato session

Zomato uses the merchant-dashboard session that `restaurant-data-pipeline/scraping/zomato_refresh_session.py`
refreshes daily into `zomato_cookies.json`. Point `ZOMATO_COOKIE_FILE` in `.env` at that file and every
Zomato listing without its own connection uses it. CSRF headers come from the `csrf` and
`__Host-zmxcsrft` cookies. A 503 from a sync means the file is missing or the session expired:
re-run the refresh script.
