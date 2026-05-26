#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${1:-$(pwd)}"
USER_DATA_DIR="${ROOT_DIR}/user_data"
CONFIG_DIR="${USER_DATA_DIR}/configs"
STRATEGY_DIR="${USER_DATA_DIR}/strategies"
TRADFI_DIR="${STRATEGY_DIR}/tradfi"
DOCS_DIR="${ROOT_DIR}/docs_local"
ARCHIVE_DIR="${USER_DATA_DIR}/strategies_archive"

echo "==> Bootstrapping TradFi real layer in: ${ROOT_DIR}"

mkdir -p "${CONFIG_DIR}" \
         "${TRADFI_DIR}" \
         "${USER_DATA_DIR}/data" \
         "${USER_DATA_DIR}/logs" \
         "${USER_DATA_DIR}/backtest_results" \
         "${USER_DATA_DIR}/plot" \
         "${USER_DATA_DIR}/hyperopts" \
         "${USER_DATA_DIR}/hyperopt_results" \
         "${ARCHIVE_DIR}" \
         "${DOCS_DIR}"

cat > "${TRADFI_DIR}/__init__.py" <<'EOF'
__all__ = [
    "universe",
    "signals",
    "weights",
    "rebalance",
    "risk",
    "state",
    "execution",
    "reporting",
]
EOF

cat > "${USER_DATA_DIR}/config.json" <<'EOF'
{
  "add_config_files": [
    "configs/00-base.json",
    "configs/10-hyperliquid.json",
    "configs/20-tradfi-universe.json",
    "configs/30-portfolio-engine.json",
    "configs/40-dryrun.json",
    "configs/99-secrets.json"
  ]
}
EOF

cat > "${CONFIG_DIR}/00-base.json" <<'EOF'
{
  "bot_name": "ft-tradfi-layer",
  "initial_state": "running",
  "max_open_trades": 3,
  "stake_currency": "USDC",
  "stake_amount": 100,
  "tradable_balance_ratio": 0.99,
  "fiat_display_currency": "USD",
  "timeframe": "1h",
  "dry_run": true,
  "cancel_open_orders_on_exit": false,
  "pairlists": [
    {
      "method": "StaticPairList"
    }
  ],
  "api_server": {
    "enabled": true,
    "listen_ip_address": "0.0.0.0",
    "listen_port": 8080,
    "verbosity": "error",
    "enable_openapi": true,
    "jwt_secret_key": "change-me-long-random-string",
    "username": "freqtrade",
    "password": "freqtrade"
  },
  "internals": {
    "process_throttle_secs": 5
  }
}
EOF

cat > "${CONFIG_DIR}/10-hyperliquid.json" <<'EOF'
{
  "trading_mode": "futures",
  "margin_mode": "isolated",
  "exchange": {
    "name": "hyperliquid",
    "walletAddress": "0xYOUR_MAIN_WALLET",
    "privateKey": "0xYOUR_API_WALLET_PRIVATE_KEY",
    "hip3_dexes": [
      "xyz"
    ],
    "ccxt_config": {},
    "ccxt_async_config": {},
    "pair_whitelist": [
      "XYZ-NVDA/USDC:USDC"
    ],
    "pair_blacklist": []
  }
}
EOF

cat > "${CONFIG_DIR}/20-tradfi-universe.json" <<'EOF'
{
  "tradfi_universe": {
    "enabled": true,
    "asset_classes": [
      "equity",
      "index",
      "commodity"
    ],
    "symbols": [
      "XYZ-NVDA/USDC:USDC"
    ],
    "excluded_symbols": [],
    "min_universe_size": 1
  }
}
EOF

cat > "${CONFIG_DIR}/30-portfolio-engine.json" <<'EOF'
{
  "portfolio_engine": {
    "model": "equal_weight",
    "max_assets": 3,
    "cash_buffer": 0.05,
    "max_single_weight": 0.40,
    "min_position_weight_delta": 0.05,
    "selection": {
      "top_n": 3,
      "score_model": "simple_momentum"
    },
    "rebalance": {
      "enabled": true,
      "mode": "calendar",
      "frequency": "weekly",
      "weekday": 0,
      "hour_utc": 0
    }
  }
}
EOF

cat > "${CONFIG_DIR}/40-dryrun.json" <<'EOF'
{
  "dry_run": true,
  "dry_run_wallet": 1000
}
EOF

cat > "${CONFIG_DIR}/99-secrets.json" <<'EOF'
{
  "exchange": {
    "walletAddress": "0xREPLACE_ME",
    "privateKey": "0xREPLACE_ME"
  }
}
EOF

cat > "${DOCS_DIR}/architecture.md" <<'EOF'
# TradFi Layer Architecture

Freqtrade core remains untouched.
Custom portfolio logic lives under user_data/strategies/tradfi.
TradfiPortfolioStrategy is a thin adapter over portfolio modules.
EOF

cat > "${DOCS_DIR}/decisions.md" <<'EOF'
# Architecture Decisions

- Keep upstream freqtrade clean.
- Use config layering.
- Use one thin strategy.
- Use simple indicators first.
- Validate loading before adding complexity.
EOF

cat > "${DOCS_DIR}/symbol-map.md" <<'EOF'
# Symbol Map

| Pair | Asset Class | Status | Notes |
|------|-------------|--------|-------|
| XYZ-NVDA/USDC:USDC | equity | candidate | verify with list-pairs |
EOF

cat > "${TRADFI_DIR}/universe.py" <<'EOF'
from __future__ import annotations

from dataclasses import dataclass
from typing import Iterable, List


@dataclass
class AssetDescriptor:
    pair: str
    symbol: str
    asset_class: str
    venue: str
    enabled: bool = True


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

    def allowed_pairs(self) -> List[str]:
        return [p for p in self.symbols if p not in self.excluded_symbols]

    def classify_pair(self, pair: str) -> str:
        up = pair.upper()
        if any(token in up for token in ["GOLD", "XAU", "SILVER", "XAG", "WTI", "BRENT", "OIL"]):
            return "commodity"
        if any(token in up for token in ["US500", "SPX", "NDX", "NAS100", "DAX", "FTSE"]):
            return "index"
        return "equity"

    def describe(self, pairs: Iterable[str]) -> List[AssetDescriptor]:
        out: List[AssetDescriptor] = []
        for pair in pairs:
            symbol = pair.split("/")[0]
            out.append(
                AssetDescriptor(
                    pair=pair,
                    symbol=symbol,
                    asset_class=self.classify_pair(pair),
                    venue="hyperliquid",
                    enabled=self.is_pair_allowed(pair),
                )
            )
        return out
EOF

cat > "${TRADFI_DIR}/signals.py" <<'EOF'
from __future__ import annotations

from dataclasses import dataclass
from typing import Optional


@dataclass
class SignalSnapshot:
    pair: str
    momentum_fast: float
    momentum_slow: float
    volatility: float
    score: float
    eligible: bool


class SignalEngine:
    def __init__(self, config: dict) -> None:
        self.config = config

    @staticmethod
    def safe_float(value: Optional[float], default: float = 0.0) -> float:
        try:
            if value is None:
                return default
            if value != value:
                return default
            return float(value)
        except (TypeError, ValueError):
            return default

    def compute_score(self, momentum_fast: float, momentum_slow: float, volatility: float) -> float:
        mf = self.safe_float(momentum_fast)
        ms = self.safe_float(momentum_slow)
        vol = max(self.safe_float(volatility, 1.0), 1e-9)
        return (0.6 * mf + 0.4 * ms) / vol

    def snapshot_for_pair(
        self,
        pair: str,
        momentum_fast: float,
        momentum_slow: float,
        volatility: float,
    ) -> SignalSnapshot:
        score = self.compute_score(momentum_fast, momentum_slow, volatility)
        eligible = score > 0
        return SignalSnapshot(
            pair=pair,
            momentum_fast=self.safe_float(momentum_fast),
            momentum_slow=self.safe_float(momentum_slow),
            volatility=self.safe_float(volatility, 1.0),
            score=score,
            eligible=eligible,
        )
EOF

cat > "${TRADFI_DIR}/weights.py" <<'EOF'
from __future__ import annotations

from dataclasses import dataclass
from typing import Iterable, List


@dataclass
class TargetAllocation:
    pair: str
    weight: float
    reason: str


class WeightModel:
    def __init__(self, config: dict) -> None:
        pe = config.get("portfolio_engine", {})
        self.model = pe.get("model", "equal_weight")
        self.max_assets = int(pe.get("max_assets", 3))
        self.max_single_weight = float(pe.get("max_single_weight", 0.40))

    def equal_weight(self, pairs: Iterable[str]) -> List[TargetAllocation]:
        pair_list = list(pairs)[: self.max_assets]
        if not pair_list:
            return []

        raw = 1.0 / len(pair_list)
        weight = min(raw, self.max_single_weight)
        return [
            TargetAllocation(pair=pair, weight=weight, reason="equal_weight_target")
            for pair in pair_list
        ]
EOF

cat > "${TRADFI_DIR}/rebalance.py" <<'EOF'
from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone


@dataclass
class RebalanceDecision:
    should_rebalance: bool
    reason: str


class RebalanceEngine:
    def __init__(self, config: dict) -> None:
        pe = config.get("portfolio_engine", {})
        reb = pe.get("rebalance", {})
        self.enabled = bool(reb.get("enabled", True))
        self.frequency = reb.get("frequency", "weekly")
        self.weekday = int(reb.get("weekday", 0))
        self.hour_utc = int(reb.get("hour_utc", 0))

    def should_rebalance(self, now: datetime | None = None) -> RebalanceDecision:
        now = now or datetime.now(timezone.utc)
        if not self.enabled:
            return RebalanceDecision(False, "rebalance_disabled")

        if self.frequency == "weekly":
            if now.weekday() == self.weekday and now.hour >= self.hour_utc:
                return RebalanceDecision(True, "scheduled_weekly_rebalance")
            return RebalanceDecision(False, "outside_weekly_window")

        return RebalanceDecision(True, "fallback_rebalance")
EOF

cat > "${TRADFI_DIR}/risk.py" <<'EOF'
from __future__ import annotations

from dataclasses import dataclass


@dataclass
class RiskCheckResult:
    allowed: bool
    reason: str


class RiskPolicy:
    def __init__(self, config: dict) -> None:
        pe = config.get("portfolio_engine", {})
        self.cash_buffer = float(pe.get("cash_buffer", 0.05))
        self.max_single_weight = float(pe.get("max_single_weight", 0.40))

    def validate_weight(self, weight: float) -> RiskCheckResult:
        if weight < 0:
            return RiskCheckResult(False, "negative_weight")
        if weight > self.max_single_weight:
            return RiskCheckResult(False, "weight_above_limit")
        return RiskCheckResult(True, "ok")
EOF

cat > "${TRADFI_DIR}/state.py" <<'EOF'
from __future__ import annotations

from dataclasses import dataclass, field
from typing import List


@dataclass
class PositionState:
    pair: str
    amount: float = 0.0
    value: float = 0.0
    weight: float = 0.0


@dataclass
class PortfolioState:
    equity: float = 0.0
    cash: float = 0.0
    positions: List[PositionState] = field(default_factory=list)

    def current_pairs(self) -> List[str]:
        return [p.pair for p in self.positions]
EOF

cat > "${TRADFI_DIR}/execution.py" <<'EOF'
from __future__ import annotations

from dataclasses import dataclass
from typing import Iterable, List


@dataclass
class ExecutionIntent:
    pair: str
    action: str
    target_weight: float
    reason: str


class ExecutionPlanner:
    def __init__(self, config: dict) -> None:
        self.config = config

    def weights_to_intents(self, targets: Iterable) -> List[ExecutionIntent]:
        intents: List[ExecutionIntent] = []
        for target in targets:
            intents.append(
                ExecutionIntent(
                    pair=target.pair,
                    action="hold_or_open",
                    target_weight=target.weight,
                    reason=target.reason,
                )
            )
        return intents
EOF

cat > "${TRADFI_DIR}/reporting.py" <<'EOF'
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
EOF

cat > "${STRATEGY_DIR}/TradfiPortfolioStrategy.py" <<'EOF'
from __future__ import annotations

from pandas import DataFrame

from freqtrade.strategy import IStrategy

from tradfi.universe import TradfiUniverse
from tradfi.signals import SignalEngine
from tradfi.weights import WeightModel
from tradfi.rebalance import RebalanceEngine
from tradfi.risk import RiskPolicy
from tradfi.execution import ExecutionPlanner


class TradfiPortfolioStrategy(IStrategy):
    """
    Minimal TradFi-oriented strategy scaffold.

    Goal:
    - load cleanly with list-strategies
    - provide valid indicators / entry / exit columns
    - keep custom logic outside freqtrade core
    """

    INTERFACE_VERSION = 3
    can_short = False
    timeframe = "1h"
    startup_candle_count = 50
    process_only_new_candles = True

    minimal_roi = {
        "0": 0.10
    }
    stoploss = -0.10
    use_exit_signal = True
    exit_profit_only = False
    ignore_roi_if_entry_signal = False

    order_types = {
        "entry": "limit",
        "exit": "limit",
        "stoploss": "market",
        "stoploss_on_exchange": False,
    }

    def __init__(self, config: dict) -> None:
        super().__init__(config)
        self.tradfi_universe = TradfiUniverse(config)
        self.signal_engine = SignalEngine(config)
        self.weight_model = WeightModel(config)
        self.rebalance_engine = RebalanceEngine(config)
        self.risk_policy = RiskPolicy(config)
        self.execution_planner = ExecutionPlanner(config)

    def populate_indicators(self, dataframe: DataFrame, metadata: dict) -> DataFrame:
        dataframe["ret_5"] = dataframe["close"].pct_change(5)
        dataframe["ret_20"] = dataframe["close"].pct_change(20)
        dataframe["vol_20"] = dataframe["close"].pct_change().rolling(20).std()

        dataframe["ret_5"] = dataframe["ret_5"].fillna(0.0)
        dataframe["ret_20"] = dataframe["ret_20"].fillna(0.0)
        dataframe["vol_20"] = dataframe["vol_20"].fillna(1.0)

        return dataframe

    def populate_entry_trend(self, dataframe: DataFrame, metadata: dict) -> DataFrame:
        pair = metadata.get("pair", "")

        dataframe["enter_long"] = 0
        dataframe["enter_tag"] = ""

        if not self.tradfi_universe.is_pair_allowed(pair):
            return dataframe

        last_score = self.signal_engine.compute_score(
            dataframe["ret_5"],
            dataframe["ret_20"],
            dataframe["vol_20"],
        )

        dataframe["score"] = last_score

        dataframe.loc[
            (
                (dataframe["score"] > 0)
                & (dataframe["volume"] > 0)
            ),
            ["enter_long", "enter_tag"]
        ] = (1, "tradfi_momentum")

        return dataframe

    def populate_exit_trend(self, dataframe: DataFrame, metadata: dict) -> DataFrame:
        dataframe["exit_long"] = 0
        dataframe["exit_tag"] = ""

        dataframe.loc[
            (
                (dataframe["ret_20"] < 0)
                & (dataframe["volume"] > 0)
            ),
            ["exit_long", "exit_tag"]
        ] = (1, "tradfi_negative_momentum")

        return dataframe
EOF

if [ -f "${ROOT_DIR}/.gitignore" ]; then
  grep -qxF 'user_data/configs/99-secrets.json' "${ROOT_DIR}/.gitignore" || echo 'user_data/configs/99-secrets.json' >> "${ROOT_DIR}/.gitignore"
  grep -qxF 'user_data/logs/' "${ROOT_DIR}/.gitignore" || echo 'user_data/logs/' >> "${ROOT_DIR}/.gitignore"
  grep -qxF 'user_data/data/' "${ROOT_DIR}/.gitignore" || echo 'user_data/data/' >> "${ROOT_DIR}/.gitignore"
  grep -qxF 'user_data/backtest_results/' "${ROOT_DIR}/.gitignore" || echo 'user_data/backtest_results/' >> "${ROOT_DIR}/.gitignore"
  grep -qxF 'user_data/hyperopt_results/' "${ROOT_DIR}/.gitignore" || echo 'user_data/hyperopt_results/' >> "${ROOT_DIR}/.gitignore"
  grep -qxF 'user_data/plot/' "${ROOT_DIR}/.gitignore" || echo 'user_data/plot/' >> "${ROOT_DIR}/.gitignore"
else
  cat > "${ROOT_DIR}/.gitignore" <<'EOF'
user_data/configs/99-secrets.json
user_data/logs/
user_data/data/
user_data/backtest_results/
user_data/hyperopt_results/
user_data/plot/
__pycache__/
*.pyc
EOF
fi

echo
echo "==> Bootstrap completato."
echo "==> Prova subito questi comandi:"
echo "docker compose run --rm freqtrade list-strategies --strategy-path /freqtrade/user_data/strategies"
echo "docker compose run --rm freqtrade trade --config /freqtrade/user_data/config.json --strategy TradfiPortfolioStrategy"