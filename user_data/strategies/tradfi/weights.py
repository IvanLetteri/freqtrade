from __future__ import annotations


class WeightModel:
    def __init__(self, config: dict) -> None:
        pe = config.get("portfolio_engine", {})
        self.max_assets = int(pe.get("max_assets", 4))
        self.cash_buffer = float(pe.get("cash_buffer", 0.10))
        self.rebalance_threshold = float(pe.get("min_position_weight_delta", 0.05))
        self.universe = list(config.get("tradfi_universe", {}).get("symbols", []))

    def investable_weight(self) -> float:
        return max(0.0, 1.0 - self.cash_buffer)

    def equal_weight_targets(self) -> dict[str, float]:
        active = self.universe[: self.max_assets]
        if not active:
            return {}
        w = self.investable_weight() / len(active)
        return {pair: w for pair in active}

    def target_weight_for_pair(self, pair: str) -> float:
        return self.equal_weight_targets().get(pair, 0.0)