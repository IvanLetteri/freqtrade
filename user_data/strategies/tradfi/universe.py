from __future__ import annotations


class TradfiUniverse:
    def __init__(self, config: dict) -> None:
        tradfi_cfg = config.get("tradfi_universe", {})
        self.enabled = tradfi_cfg.get("enabled", True)
        self.symbols = list(tradfi_cfg.get("symbols", []))
        self.excluded_symbols = set(tradfi_cfg.get("excluded_symbols", []))

    def is_pair_allowed(self, pair: str) -> bool:
        if not self.enabled:
            return False
        if pair in self.excluded_symbols:
            return False
        if self.symbols and pair not in self.symbols:
            return False
        return True

    def allowed_pairs(self) -> list[str]:
        return [p for p in self.symbols if p not in self.excluded_symbols]