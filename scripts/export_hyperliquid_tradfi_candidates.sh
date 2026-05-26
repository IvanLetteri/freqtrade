#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${1:-$(pwd)}"
OUT_DIR="${ROOT_DIR}/user_data/hyperliquid_catalog"
CONFIG_PATH="/freqtrade/user_data/config.json"
SERVICE_NAME="${SERVICE_NAME:-freqtrade}"

mkdir -p "${OUT_DIR}"

echo "==> Root: ${ROOT_DIR}"
echo "==> Output dir: ${OUT_DIR}"
echo "==> Docker service: ${SERVICE_NAME}"

echo
echo "==> 1) Export full Hyperliquid pair list (JSON)"
docker compose run --rm "${SERVICE_NAME}" \
  list-pairs \
  --exchange hyperliquid \
  --config "${CONFIG_PATH}" \
  --print-json \
  > "${OUT_DIR}/hyperliquid_pairs_full.json"

echo
echo "==> 2) Export full Hyperliquid pair list (one-column)"
docker compose run --rm "${SERVICE_NAME}" \
  list-pairs \
  --exchange hyperliquid \
  --config "${CONFIG_PATH}" \
  -1 \
  > "${OUT_DIR}/hyperliquid_pairs_full.txt"

echo
echo "==> 3) Export full Hyperliquid pair list (CSV)"
docker compose run --rm "${SERVICE_NAME}" \
  list-pairs \
  --exchange hyperliquid \
  --config "${CONFIG_PATH}" \
  --print-csv \
  > "${OUT_DIR}/hyperliquid_pairs_full.csv"

echo
echo "==> 4) Build heuristic TradFi candidate list"
grep -E -i \
'NVDA|AAPL|MSFT|AMZN|GOOG|GOOGL|META|TSLA|NFLX|AMD|INTC|SMCI|PLTR|COIN|UBER|SPY|QQQ|IWM|DIA|SPX|NDX|US500|NAS100|DJI|DAX|FTSE|CAC|NIKKEI|HSI|XAU|GOLD|XAG|SILVER|WTI|BRENT|OIL|COPPER|EURUSD|GBPUSD|USDJPY|AUDUSD|USDCHF' \
"${OUT_DIR}/hyperliquid_pairs_full.txt" \
| sort -u \
> "${OUT_DIR}/hyperliquid_tradfi_candidates.txt" || true

echo
echo "==> 5) Create review-friendly markdown table"
{
  echo "# Hyperliquid TradFi candidate pairs"
  echo
  echo "| Pair |"
  echo "|------|"
  while IFS= read -r line; do
    [ -n "${line}" ] && echo "| ${line} |"
  done < "${OUT_DIR}/hyperliquid_tradfi_candidates.txt"
} > "${OUT_DIR}/hyperliquid_tradfi_candidates.md"

echo
echo "==> 6) Summary"
echo "Saved files:"
echo "  - ${OUT_DIR}/hyperliquid_pairs_full.json"
echo "  - ${OUT_DIR}/hyperliquid_pairs_full.txt"
echo "  - ${OUT_DIR}/hyperliquid_pairs_full.csv"
echo "  - ${OUT_DIR}/hyperliquid_tradfi_candidates.txt"
echo "  - ${OUT_DIR}/hyperliquid_tradfi_candidates.md"

echo
echo "==> Preview candidates:"
if [ -s "${OUT_DIR}/hyperliquid_tradfi_candidates.txt" ]; then
  sed -n '1,80p' "${OUT_DIR}/hyperliquid_tradfi_candidates.txt"
else
  echo "No heuristic TradFi candidates found."
  echo "Open the full files and inspect manually."
fi