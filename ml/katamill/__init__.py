"""
Katamill package: KataGo-inspired RL tooling for Nine Men's Morris.

This package provides:
- Feature extractor building rich CNN inputs
- Heuristic target builders from classic engine signals
- A neural network with multi-head outputs (policy, value, score-like, ownership-like)
- MCTS wrapper compatible with ml/game API
- Pit script entrypoints imported by pit.py
"""

__all__ = [
    "features",
    "heuristics",
    "neural_network",
    "mcts",
]


