"""
Perfect database module for accessing optimal game state evaluations.

This module provides functionality to read and interact with perfect databases
that contain optimal evaluations for game positions.
"""

# Make commonly used classes available at package level
try:
    from .perfect_db_reader import PerfectDB
except ImportError:
    # Handle import issues gracefully
    PerfectDB = None

__all__ = ['PerfectDB']
