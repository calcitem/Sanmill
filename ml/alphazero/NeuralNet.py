from abc import ABC, abstractmethod


class NeuralNet(ABC):
    """Abstract base class for AlphaZero neural network wrappers.

    Implementations should provide training, inference, and checkpoint I/O.
    """

    def __init__(self, game, args):
        self.game = game
        self.args = args

    @abstractmethod
    def train(self, examples):
        """Train the network from a list of (board, pi, v, period) samples."""
        raise NotImplementedError

    @abstractmethod
    def predict(self, canonical_board):
        """Return (pi, v) for the given canonical board."""
        raise NotImplementedError

    @abstractmethod
    def save_checkpoint(self, folder: str, filename: str):
        """Save model weights to folder/filename."""
        raise NotImplementedError

    @abstractmethod
    def load_checkpoint(self, folder: str, filename: str):
        """Load model weights from folder/filename."""
        raise NotImplementedError


