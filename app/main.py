from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from sqlalchemy import text

from app.db import engine
from app.routers import masters, metrics, reviews, sync, tenancy

app = FastAPI(title="SocialSpork API", version="0.1.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:3000", "http://localhost:5173"],
    allow_methods=["*"],
    allow_headers=["*"],
)

for r in (masters, tenancy, reviews, metrics, sync):
    app.include_router(r.router, prefix="/api")


@app.get("/health")
def health():
    with engine.connect() as conn:
        conn.execute(text("SELECT 1"))
    return {"status": "ok"}


# Dashboard UI; mounted last so /api, /docs and /health take precedence
app.mount("/", StaticFiles(directory=Path(__file__).parent.parent / "frontend", html=True), name="frontend")
