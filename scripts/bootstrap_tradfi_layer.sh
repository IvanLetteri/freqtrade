#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${1:-$(pwd)}"
USER_DATA_DIR="${ROOT_DIR}/user_data"
CONFIG_DIR="${USER_DATA_DIR}/configs"
STRATEGY_DIR="${USER_DATA_DIR}/strategies"
TRADFI_DIR="${STRATEGY_DIR}/tradfi"
DOCS_DIR="${ROOT_DIR}/docs_local"
ARCHIVE_DIR="${USER_DATA_DIR}/strategies_archive"

echo "==> Root dir: ${ROOT_DIR}"
echo "==> user_data dir: ${USER_DATA_DIR}"

mkdir -p "${CONFIG_DIR}"
mkdir -p "${TRADFI_DIR}"
mkdir -p "${USER_DATA_DIR}/data"
mkdir -p "${USER_DATA_DIR}/logs"
mkdir -p "${USER_DATA_DIR}/backtest_results"
mkdir -p "${USER_DATA_DIR}/plot"
mkdir -p "${USER_DATA_DIR}/hyperopts"
mkdir -p "${USER_DATA_DIR}/hyperopt_results"
mkdir -p "${ARCHIVE_DIR}"
mkdir -p "${DOCS_DIR}"

touch "${TRADFI_DIR}/__init__.py"

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
  "max_open_trades": 5,
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
    "rebalance": {
      "enabled": true,
      "mode": "calendar",
      "frequency": "weekly",
      "weekday": 1,
      "hour_utc": 0
    },
    "selection": {
      "top_n": 3,
      "score_model": "simple_momentum"
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

## Goal
Turn Freqtrade into a TradFi-oriented portfolio execution engine on Hyperliquid without modifying core code.

## Principles
- Keep core Freqtrade untouched.
- Keep all custom logic under user_data/.
- Use config layering.
- Use one thin strategy as orchestration layer.
- Keep portfolio logic in dedicated modules.

## Main runtime flow
1. Universe selection
2. Signal scoring
3. Weight calculation
4. Risk validation
5. Rebalance decision
6. Execution planning
EOF

cat > "${DOCS_DIR}/decisions.md" <<'EOF'
# Architecture Decisions

- Freqtrade core remains unmodified.
- All custom code lives in user_data/strategies/tradfi/.
- Config is split into multiple JSON files.
- Hyperliquid HIP-3 TradFi symbols are declared in config.
- First implementation uses equal-weight portfolio logic.
EOF

cat > "${DOCS_DIR}/symbol-map.md" <<'EOF'
# Symbol Map

Track verified Hyperliquid HIP-3 TradFi symbols here.

| Pair | Asset Class | Status | Notes |
|------|-------------|--------|-------|
| XYZ-NVDA/USDC:USDC | equity | candidate | verify with list-pairs |
EOF

cat > "${STRATEGY_DIR}/TradfiPortfolioStrategy.py" <<'EOF'
from freqtrade.strategy import IStrategy
from pandas import DataFrame

from tradfi.universe import TradfiUniverse
from tradfi.signals import SignalEngine
from tradfi.weights import WeightModel
from tradfi.rebalance import RebalanceEngine
from tradfi.risk import RiskPolicy
from tradfi.state import PortfolioState
from tradfi.execution import ExecutionPlanner


class TradfiPortfolioStrategy(IStrategy):
    INTERFACE_VERSION = 3
    can_short = False
    timeframe = "1h"
    startup_candle_count = 200
    minimal_roi = {"0": 0.10}
    stoploss = -0.10

    def __init__(self, config: dict) -> None:
        super().__init__(config)
        self.universe = TradfiUniverse(config)
        self.signal_engine = SignalEngine(config)
        self.weight_model = WeightModel(config)
        self.rebalance_engine = RebalanceEngine(config)
        self.risk_policy = RiskPolicy(config)
        self.execution_planner = ExecutionPlanner(config)

    def populate_indicators(self, dataframe: DataFrame, metadata: dict) -> DataFrame:
        dataframe["ret_5"] = dataframe["close"].pct_change(5)
        dataframe["ret_20"] = dataframe["close"].pct_change(20)
        dataframe["vol_20"] = dataframe["close"].pct_change().rolling(20).std()
        return dataframe

    def populate_entry_trend(self, dataframe: DataFrame, metadata: dict) -> DataFrame:
        dataframe["enter_long"] = 0
        dataframe["enter_tag"] = ""

        pair = metadata.get("pair", "")
        if self.universe.is_pair_allowed(pair):
            dataframe.loc[
                (dataframe["ret_20"] > 0) & (dataframe["volume"] > 0),
                ["enter_long", "enter_tag"]
            ] = (1, "tradfi_candidate")

        return dataframe

    def populate_exit_trend(self, dataframe: DataFrame, metadata: dict) -> DataFrame:
        dataframe["exit_long"] = 0
        dataframe["exit_tag"] = ""

        dataframe.loc[
            (dataframe["ret_20"] < 0),
            ["exit_long", "exit_tag"]
        ] = (1, "tradfi_exit")

        return dataframe
EOF

cat > "${TRADFI_DIR}/universe.py" <<'EOF'
from dataclasses import dataclass


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
        self.symbols = set(tradfi_cfg.get("symbols", []))
        self.asset_classes = set(tradfi_cfg.get("asset_classes", []))
        self.excluded_symbols = set(tradfi_cfg.get("excluded_symbols", []))

    def is_pair_allowed(self, pair: str) -> bool:
        if pair in self.excluded_symbols:
            return False
        if self.symbols and pair not in self.symbols:
            return False
        return True

    def classify_pair(self, pair: str) -> str:
        upper = pair.upper()
        if any(x in upper for x in ["GOLD", "XAU", "SILVER", "XAG", "WTI", "BRENT", "OIL"]):
            return "commodity"
        if any(x in upper for x in ["US500", "SPX", "NDX", "NAS100", "DAX", "FTSE"]):
            return "index"
        return "equity"
EOF

cat > "${TRADFI_DIR}/signals.py" <<'EOF'
from dataclasses import dataclass


@dataclass
class SignalSnapshot:
    pair: str
    score: float
    momentum: float
    volatility: float
    eligible: bool


class SignalEngine:
    def __init__(self, config: dict) -> None:
        self.config = config

    def compute_score(self, momentum: float, volatility: float) -> float:
        if volatility == 0:
            return momentum
        return momentum / volatility
EOF

cat > "${TRADFI_DIR}/weights.py" <<'EOF'
from dataclasses import dataclass


@dataclass
class TargetAllocation:
    pair: str
    weight: float
    reason: str


class WeightModel:
    def __init__(self, config: dict) -> None:
        pe = config.get("portfolio_engine", {})
        self.model = pe.get("model", "equal_weight")
        self.max_assets = pe.get("max_assets", 3)
        self.max_single_weight = pe.get("max_single_weight", 0.40)

    def equal_weight(self, pairs: list[str]) -> list[TargetAllocation]:
        if not pairs:
            return []
        n = min(len(pairs), self.max_assets)
        weight = min(1.0 / n, self.max_single_weight)
        return [
            TargetAllocation(pair=p, weight=weight, reason="equal_weight")
            for p in pairs[:n]
        ]
EOF

cat > "${TRADFI_DIR}/rebalance.py" <<'EOF'
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
        self.enabled = reb.get("enabled", True)
        self.frequency = reb.get("frequency", "weekly")
        self.weekday = reb.get("weekday", 1)

    def should_rebalance(self, now: datetime | None = None) -> RebalanceDecision:
        now = now or datetime.now(timezone.utc)
        if not self.enabled:
            return RebalanceDecision(False, "disabled")
        if self.frequency == "weekly" and now.weekday() == self.weekday:
            return RebalanceDecision(True, "scheduled_weekly_rebalance")
        return RebalanceDecision(False, "no_rebalance")
EOF

cat > "${TRADFI_DIR}/risk.py" <<'EOF'
from dataclasses import dataclass


@dataclass
class RiskCheckResult:
    allowed: bool
    reason: str


class RiskPolicy:
    def __init__(self, config: dict) -> None:
        pe = config.get("portfolio_engine", {})
        self.cash_buffer = pe.get("cash_buffer", 0.05)
        self.max_single_weight = pe.get("max_single_weight", 0.40)

    def validate_weight(self, weight: float) -> RiskCheckResult:
        if weight > self.max_single_weight:
            return RiskCheckResult(False, "weight_above_limit")
        return RiskCheckResult(True, "ok")
EOF

cat > "${TRADFI_DIR}/state.py" <<'EOF'
from dataclasses import dataclass, field


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
    positions: list[PositionState] = field(default_factory=list)

    def current_pairs(self) -> list[str]:
        return [p.pair for p in self.positions]
EOF

cat > "${TRADFI_DIR}/execution.py" <<'EOF'
from dataclasses import dataclass


@dataclass
class ExecutionIntent:
    pair: str
    action: str
    target_weight: float
    reason: str


class ExecutionPlanner:
    def __init__(self, config: dict) -> None:
        self.config = config

    def weights_to_intents(self, targets) -> list[ExecutionIntent]:
        intents = []
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
import json
from dataclasses import asdict


class PortfolioReporter:
    def save_snapshot(self, obj, file_path: str) -> None:
        with open(file_path, "w", encoding="utf-8") as f:
            json.dump(asdict(obj), f, indent=2, ensure_ascii=False)
EOF

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

echo "==> TradFi layer bootstrap completato."
echo "==> Prossimi passi consigliati:"
echo "    1) Controlla user_data/config.json"
echo "    2) Inserisci le chiavi in user_data/configs/99-secrets.json"
echo "    3) Verifica la strategy con:"
echo "       docker compose run --rm freqtrade list-strategies --strategy-path /freqtrade/user_data/strategies"