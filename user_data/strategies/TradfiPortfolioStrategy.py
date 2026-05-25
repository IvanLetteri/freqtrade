from __future__ import annotations

from datetime import datetime, timezone
from typing import Optional

from pandas import DataFrame

from freqtrade.persistence import Trade
from freqtrade.strategy import IStrategy


class TradfiPortfolioStrategy(IStrategy):
    """
    TradFi portfolio strategy - V2
    4 assets, equal weight, 10% cash buffer, weekly rebalance, 5% threshold.
    """

    INTERFACE_VERSION = 3
    can_short = False
    timeframe = "1h"
    startup_candle_count = 50
    process_only_new_candles = True
    position_adjustment_enable = True

    minimal_roi = {"0": 100.0}
    stoploss = -0.99
    use_exit_signal = True
    exit_profit_only = False
    ignore_roi_if_entry_signal = False

    order_types = {
        "entry": "limit",
        "exit": "limit",
        "emergency_exit": "market",
        "force_entry": "market",
        "force_exit": "market",
        "stoploss": "market",
        "stoploss_on_exchange": False,
    }

    def __init__(self, config: dict) -> None:
        super().__init__(config)

        tradfi_cfg = config.get("tradfi_universe", {})
        pe_cfg = config.get("portfolio_engine", {})
        reb_cfg = pe_cfg.get("rebalance", {})

        self.universe = list(tradfi_cfg.get("symbols", []))
        self.max_assets = int(pe_cfg.get("max_assets", 4))
        self.cash_buffer = float(pe_cfg.get("cash_buffer", 0.10))
        self.rebalance_threshold = float(pe_cfg.get("min_position_weight_delta", 0.05))

        self.rebalance_enabled = bool(reb_cfg.get("enabled", True))
        self.rebalance_frequency = reb_cfg.get("frequency", "weekly")
        self.rebalance_weekday = int(reb_cfg.get("weekday", 0))
        self.rebalance_hour_utc = int(reb_cfg.get("hour_utc", 0))

    def version(self) -> str:
        return "2.0.0"

    def populate_indicators(self, dataframe: DataFrame, metadata: dict) -> DataFrame:
        dataframe["ret_5"] = dataframe["close"].pct_change(5).fillna(0.0)
        dataframe["ret_20"] = dataframe["close"].pct_change(20).fillna(0.0)
        dataframe["vol_20"] = dataframe["close"].pct_change().rolling(20).std().fillna(1e-9)
        dataframe["score"] = ((0.6 * dataframe["ret_5"]) + (0.4 * dataframe["ret_20"])) / dataframe["vol_20"]
        return dataframe

    def populate_entry_trend(self, dataframe: DataFrame, metadata: dict) -> DataFrame:
        pair = metadata.get("pair", "")
        dataframe["enter_long"] = 0
        dataframe["enter_tag"] = ""

        if pair not in self.universe:
            return dataframe

        dataframe.loc[
            (dataframe["score"] > 0) & (dataframe["volume"] > 0),
            ["enter_long", "enter_tag"]
        ] = (1, "portfolio_entry")

        return dataframe

    def populate_exit_trend(self, dataframe: DataFrame, metadata: dict) -> DataFrame:
        pair = metadata.get("pair", "")
        dataframe["exit_long"] = 0
        dataframe["exit_tag"] = ""

        if pair not in self.universe:
            dataframe.loc[:, ["exit_long", "exit_tag"]] = (1, "pair_outside_universe")
            return dataframe

        dataframe.loc[
            (dataframe["score"] < 0) & (dataframe["volume"] > 0),
            ["exit_long", "exit_tag"]
        ] = (1, "negative_score")

        return dataframe

    def leverage(
        self,
        pair: str,
        current_time: datetime,
        current_rate: float,
        proposed_leverage: float,
        max_leverage: float,
        entry_tag: Optional[str],
        side: str,
        **kwargs,
    ) -> float:
        return min(1.0, max_leverage)

    def custom_stake_amount(
        self,
        pair: str,
        current_time: datetime,
        current_rate: float,
        proposed_stake: float,
        min_stake: Optional[float],
        max_stake: float,
        leverage: float,
        entry_tag: Optional[str],
        side: str,
        **kwargs,
    ) -> float:
        target_weight = self._target_weight_for_pair(pair)
        if target_weight <= 0:
            return 0.0

        stake = proposed_stake * target_weight

        if min_stake is not None:
            stake = max(stake, min_stake)

        stake = min(stake, max_stake)
        return max(stake, 0.0)

    def custom_exit(
        self,
        pair: str,
        trade: Trade,
        current_time: datetime,
        current_rate: float,
        current_profit: float,
        **kwargs,
    ):
        if pair not in self.universe:
            return "pair_removed"

        if self._target_weight_for_pair(pair) <= 0:
            return "target_zero"

        return None

    def adjust_trade_position(
        self,
        trade: Trade,
        current_time: datetime,
        current_rate: float,
        current_profit: float,
        min_stake: Optional[float],
        max_stake: float,
        current_entry_rate: float,
        current_exit_rate: float,
        current_entry_profit: float,
        current_exit_profit: float,
        **kwargs,
    ):
        if not self._is_rebalance_time(current_time):
            return None

        pair = trade.pair
        target_weight = self._target_weight_for_pair(pair)
        if target_weight <= 0:
            return None

        current_weight = self._estimate_current_weight(trade)
        delta = target_weight - current_weight

        if abs(delta) < self.rebalance_threshold:
            return None

        if delta <= 0:
            return None

        additional_stake = max_stake * delta

        if min_stake is not None and additional_stake < min_stake:
            return None

        return min(additional_stake, max_stake)

    def _investable_weight(self) -> float:
        return max(0.0, 1.0 - self.cash_buffer)

    def _active_universe(self) -> list[str]:
        return self.universe[: self.max_assets]

    def _equal_weight_targets(self) -> dict[str, float]:
        active = self._active_universe()
        if not active:
            return {}
        w = self._investable_weight() / len(active)
        return {pair: w for pair in active}

    def _target_weight_for_pair(self, pair: str) -> float:
        return self._equal_weight_targets().get(pair, 0.0)

    def _is_rebalance_time(self, now: datetime | None = None) -> bool:
        now = now or datetime.now(timezone.utc)

        if not self.rebalance_enabled:
            return False

        if self.rebalance_frequency == "weekly":
            return now.weekday() == self.rebalance_weekday and now.hour >= self.rebalance_hour_utc

        return False

    def _estimate_current_weight(self, trade: Trade) -> float:
        active = self._active_universe()
        if not active:
            return 0.0

        open_trades_in_universe = [p for p in active if p]
        if not open_trades_in_universe:
            return 0.0

        return 1.0 / len(open_trades_in_universe)