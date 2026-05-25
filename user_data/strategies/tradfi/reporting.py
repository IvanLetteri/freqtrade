from __future__ import annotations

import json
from dataclasses import asdict, is_dataclass
from pathlib import Path
from typing import Any


class PortfolioReporter:
    def save_snapshot(self, obj: Any, file_path: str) -> None:
        payload = asdict(obj) if is_dataclass(obj) else obj
        path = Path(file_path)
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("w", encoding="utf-8") as handle:
            json.dump(payload, handle, indent=2, ensure_ascii=False)
