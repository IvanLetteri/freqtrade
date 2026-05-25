# TradFi Layer Architecture

Freqtrade core remains untouched.
Custom portfolio logic lives under user_data/strategies/tradfi.
TradfiPortfolioStrategy is a thin adapter over portfolio modules.
