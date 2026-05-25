from __future__ import annotations


class SignalEngine:
    def __init__(self, config: dict) -> None:
        self.config = config

    @staticmethod
    def compute_score(momentum_fast, momentum_slow, volatility):
        vol = volatility.replace(0, 1e-9)
        return (0.6 * momentum_fast + 0.4 * momentum_slow) / vol