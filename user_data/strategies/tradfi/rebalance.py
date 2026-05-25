from __future__ import annotations

from datetime import datetime, timezone


class RebalanceEngine:
    def __init__(self, config: dict) -> None:
        pe = config.get("portfolio_engine", {})
        reb = pe.get("rebalance", {})
        self.enabled = bool(reb.get("enabled", True))
        self.frequency = reb.get("frequency", "weekly")
        self.weekday = int(reb.get("weekday", 0))
        self.hour_utc = int(reb.get("hour_utc", 0))

    def is_rebalance_time(self, now: datetime | None = None) -> bool:
        now = now or datetime.now(timezone.utc)
        if not self.enabled:
            return False
        if self.frequency == "weekly":
            return now.weekday() == self.weekday and now.hour >= self.hour_utc
        return False