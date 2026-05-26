from __future__ import annotations

import json
import os
from datetime import datetime, timezone
from pathlib import Path
from tempfile import NamedTemporaryFile
from typing import Any

from fastapi import FastAPI, HTTPException
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field, ValidationError

BASE_DIR = Path(__file__).resolve().parent
STATIC_DIR = BASE_DIR / "static"

USER_DATA_DIR = Path(os.getenv("PORTFOLIO_USER_DATA_DIR", BASE_DIR.parent / "user_data"))
CONFIG_DIR = USER_DATA_DIR / "configs"
HISTORY_DIR = CONFIG_DIR / ".history"

CONFIG_FILES = {
    "hyperliquid": CONFIG_DIR / "10-hyperliquid.json",
    "tradfi_universe": CONFIG_DIR / "20-tradfi-universe.json",
    "portfolio_engine": CONFIG_DIR / "30-portfolio-engine.json",
}


class TradfiUniversePayload(BaseModel):
    enabled: bool = True
    asset_classes: list[str] = Field(default_factory=list)
    symbols: list[str] = Field(default_factory=list)
    excluded_symbols: list[str] = Field(default_factory=list)
    min_universe_size: int = 1


app = FastAPI(title="TradFi Portfolio UI", version="0.3.0")


def ensure_dirs() -> None:
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    HISTORY_DIR.mkdir(parents=True, exist_ok=True)


def read_json_file(path: Path) -> dict[str, Any]:
    if not path.exists():
        raise HTTPException(status_code=404, detail=f"Config file not found: {path}")
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise HTTPException(status_code=500, detail=f"Invalid JSON in {path.name}: {exc.msg}") from exc


def atomic_write_json(path: Path, payload: dict[str, Any]) -> None:
    ensure_dirs()

    if path.exists():
        timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        backup_path = HISTORY_DIR / f"{path.stem}.{timestamp}.bak.json"
        backup_path.write_text(path.read_text(encoding="utf-8"), encoding="utf-8")

    with NamedTemporaryFile("w", encoding="utf-8", dir=path.parent, delete=False) as tmp:
        json.dump(payload, tmp, indent=2, ensure_ascii=False)
        tmp.write("\n")
        tmp.flush()
        os.fsync(tmp.fileno())
        temp_name = tmp.name

    os.replace(temp_name, path)


@app.get("/api/health")
async def health():
    return JSONResponse(
        {
            "status": "ok",
            "service": "portfolio-ui",
            "version": "0.3.0",
            "user_data_dir": str(USER_DATA_DIR),
            "config_dir": str(CONFIG_DIR),
            "history_dir": str(HISTORY_DIR),
        }
    )


@app.get("/api/config")
async def get_all_config():
    payload = {}
    for key, path in CONFIG_FILES.items():
        payload[key] = {
            "path": str(path),
            "exists": path.exists(),
            "data": read_json_file(path) if path.exists() else None,
        }
    return JSONResponse(payload)


@app.get("/api/config/{config_name}")
async def get_config(config_name: str):
    path = CONFIG_FILES.get(config_name)
    if path is None:
        raise HTTPException(status_code=404, detail=f"Unknown config: {config_name}")

    return JSONResponse(
        {
            "name": config_name,
            "path": str(path),
            "exists": path.exists(),
            "data": read_json_file(path),
        }
    )


@app.post("/api/config/tradfi_universe")
async def save_tradfi_universe(payload: TradfiUniversePayload):
    symbols = [s.strip() for s in payload.symbols if s.strip()]
    excluded_symbols = [s.strip() for s in payload.excluded_symbols if s.strip()]
    asset_classes = [a.strip() for a in payload.asset_classes if a.strip()]

    if len(symbols) == 0:
        raise HTTPException(status_code=400, detail="symbols must contain at least one pair")

    if payload.min_universe_size < 1:
        raise HTTPException(status_code=400, detail="min_universe_size must be >= 1")

    if payload.min_universe_size > len(symbols):
        raise HTTPException(
            status_code=400,
            detail="min_universe_size cannot be greater than the number of symbols",
        )

    body = {
        "tradfi_universe": {
            "enabled": payload.enabled,
            "asset_classes": asset_classes,
            "symbols": symbols,
            "excluded_symbols": excluded_symbols,
            "min_universe_size": payload.min_universe_size,
        }
    }

    path = CONFIG_FILES["tradfi_universe"]
    atomic_write_json(path, body)

    return JSONResponse(
        {
            "status": "saved",
            "path": str(path),
            "data": body,
        }
    )


app.mount("/", StaticFiles(directory=str(STATIC_DIR), html=True), name="static")