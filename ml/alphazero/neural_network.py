#!/usr/bin/env python3
"""
Pure Alpha Zero Neural Network for Nine Men's Morris

This module implements a clean Alpha Zero neural network architecture
(not based on NNUE) specifically designed for Nine Men's Morris.

Features:
- Policy and value head outputs
- Residual block architecture
- Efficient feature extraction
- GPU/CPU compatibility
"""

import torch
import torch.nn as nn
import torch.nn.functional as F
import numpy as np
from typing import Tuple, Optional, Dict, Any
import logging

logger = logging.getLogger(__name__)


class ConvBlock(nn.Module):
    """Convolutional block with batch normalization and ReLU activation."""

    def __init__(self, in_channels: int, out_channels: int, kernel_size: int = 3, padding: int = 1):
        super(ConvBlock, self).__init__()
        self.conv = nn.Conv2d(in_channels, out_channels, kernel_size, padding=padding)
        self.bn = nn.BatchNorm2d(out_channels)

    def forward(self, x):
        return F.relu(self.bn(self.conv(x)))


class ResidualBlock(nn.Module):
    """Residual block for deep network training."""

    def __init__(self, channels: int):
        super(ResidualBlock, self).__init__()
        self.conv1 = nn.Conv2d(channels, channels, 3, padding=1)
        self.bn1 = nn.BatchNorm2d(channels)
        self.conv2 = nn.Conv2d(channels, channels, 3, padding=1)
        self.bn2 = nn.BatchNorm2d(channels)

    def forward(self, x):
        residual = x
        x = F.relu(self.bn1(self.conv1(x)))
        x = self.bn2(self.conv2(x))
        x += residual
        return F.relu(x)


class AlphaZeroNet(nn.Module):
    """
    Alpha Zero Neural Network for Nine Men's Morris.

    Architecture:
    - Input: 7x7 board representation with multiple channels
    - Backbone: Convolutional layers with residual blocks
    - Policy head: Outputs move probabilities
    - Value head: Outputs position evaluation
    """

    def __init__(self,
                 input_channels: int = 19,  # Multiple feature planes (updated for enhanced encoding)
                 num_filters: int = 256,
                 num_residual_blocks: int = 10,
                 action_size: int = 1000,  # From Game.getActionSize()
                 dropout_rate: float = 0.3):
        """
        Initialize Alpha Zero network.

        Args:
            input_channels: Number of input feature channels
            num_filters: Number of convolutional filters
            num_residual_blocks: Number of residual blocks in backbone
            action_size: Number of possible actions
            dropout_rate: Dropout rate for regularization
        """
        super(AlphaZeroNet, self).__init__()

        self.input_channels = input_channels
        self.num_filters = num_filters
        self.action_size = action_size

        # Input convolutional layer
        self.input_conv = ConvBlock(input_channels, num_filters)

        # Residual backbone
        self.residual_blocks = nn.ModuleList([
            ResidualBlock(num_filters) for _ in range(num_residual_blocks)
        ])

        # Policy head
        self.policy_conv = ConvBlock(num_filters, 32, kernel_size=1, padding=0)
        self.policy_fc = nn.Linear(32 * 7 * 7, action_size)

        # Value head
        self.value_conv = ConvBlock(num_filters, 32, kernel_size=1, padding=0)
        self.value_fc1 = nn.Linear(32 * 7 * 7, 256)
        self.value_fc2 = nn.Linear(256, 1)

        # Dropout for regularization
        self.dropout = nn.Dropout(dropout_rate)

        # Initialize weights
        self._initialize_weights()

        logger.info(f"AlphaZeroNet initialized: {input_channels} channels, "
                   f"{num_filters} filters, {num_residual_blocks} blocks")

    def _initialize_weights(self):
        """Initialize network weights using Xavier initialization."""
        for m in self.modules():
            if isinstance(m, nn.Conv2d):
                nn.init.xavier_normal_(m.weight)
                if m.bias is not None:
                    nn.init.constant_(m.bias, 0)
            elif isinstance(m, nn.Linear):
                nn.init.xavier_normal_(m.weight)
                if m.bias is not None:
                    nn.init.constant_(m.bias, 0)
            elif isinstance(m, nn.BatchNorm2d):
                nn.init.constant_(m.weight, 1)
                nn.init.constant_(m.bias, 0)

    def forward(self, x: torch.Tensor) -> Tuple[torch.Tensor, torch.Tensor]:
        """
        Forward pass through the network.

        Args:
            x: Input tensor of shape (batch_size, channels, 7, 7)

        Returns:
            Tuple of (policy_logits, value_estimate)
        """
        # Backbone
        x = self.input_conv(x)

        for block in self.residual_blocks:
            x = block(x)

        # Policy head
        policy = self.policy_conv(x)
        policy = policy.view(policy.size(0), -1)  # Flatten
        policy = self.dropout(policy)
        policy_logits = self.policy_fc(policy)

        # Value head
        value = self.value_conv(x)
        value = value.view(value.size(0), -1)  # Flatten
        value = self.dropout(value)
        value = F.relu(self.value_fc1(value))
        value = torch.tanh(self.value_fc2(value))  # Output in [-1, 1]

        return policy_logits, value

    def predict(self, board_tensor: torch.Tensor) -> Tuple[np.ndarray, float]:
        """
        Predict policy and value for a single board position.

        Args:
            board_tensor: Board representation tensor

        Returns:
            Tuple of (policy_probabilities, value_estimate)
        """
        self.eval()
        with torch.no_grad():
            if len(board_tensor.shape) == 3:
                board_tensor = board_tensor.unsqueeze(0)  # Add batch dimension

            policy_logits, value = self.forward(board_tensor)

            # Convert to probabilities
            policy_probs = F.softmax(policy_logits, dim=1).squeeze(0).cpu().numpy()
            value_scalar = value.item()

        return policy_probs, value_scalar


class MillBoardEncoder:
    """
    Encoder for converting Nine Men's Morris board to neural network input tensor.

    Creates multiple feature planes representing different aspects of the game state.
    """

    def __init__(self):
        """Initialize board encoder."""
        # Define valid positions on the board (same as in generate_training_data.py)
        self.allowed_places = np.array([
            [1, 0, 0, 1, 0, 0, 1],
            [0, 1, 0, 1, 0, 1, 0],
            [0, 0, 1, 1, 1, 0, 0],
            [1, 1, 1, 0, 1, 1, 1],
            [0, 0, 1, 1, 1, 0, 0],
            [0, 1, 0, 1, 0, 1, 0],
            [1, 0, 0, 1, 0, 0, 1]
        ], dtype=bool)

        # Create coordinate mapping for valid positions
        self.coord_to_feature = {}
        self.feature_to_coord = {}
        feature_idx = 0

        for y in range(7):
            for x in range(7):
                if self.allowed_places[x][y]:
                    self.coord_to_feature[(x, y)] = feature_idx
                    self.feature_to_coord[feature_idx] = (x, y)
                    feature_idx += 1

        self.num_valid_positions = feature_idx  # Should be 24

        logger.info(f"Board encoder initialized: {self.num_valid_positions} valid positions")

    def encode_board(self, board, current_player: int = 1, board_state: dict = None) -> torch.Tensor:
        """
        Encode board state into neural network input tensor.

        Args:
            board: Board object from ml/game
            current_player: Current player (1 for white, -1 for black)
            board_state: Optional dict with additional state info from TrainingPosition

        Returns:
            Tensor of shape (19, 7, 7) with multiple feature planes
        """
        # Initialize feature planes
        channels = []

        # Feature plane 0: Current player pieces
        current_pieces = np.zeros((7, 7), dtype=np.float32)
        # Feature plane 1: Opponent pieces
        opponent_pieces = np.zeros((7, 7), dtype=np.float32)
        # Feature plane 2: Empty valid positions
        empty_positions = np.zeros((7, 7), dtype=np.float32)

        for x in range(7):
            for y in range(7):
                if self.allowed_places[x][y]:
                    piece = board.pieces[x][y]
                    if piece == current_player:
                        current_pieces[x][y] = 1.0
                    elif piece == -current_player:
                        opponent_pieces[x][y] = 1.0
                    else:
                        empty_positions[x][y] = 1.0

        channels.extend([current_pieces, opponent_pieces, empty_positions])

        # Feature plane 3: Valid moves mask
        valid_moves_mask = np.zeros((7, 7), dtype=np.float32)
        try:
            # Try multiple import paths for Game
            try:
                from game.Game import Game
            except ImportError:
                import sys
                import os
                current_dir = os.path.dirname(os.path.abspath(__file__))
                game_dir = os.path.join(os.path.dirname(current_dir), 'game')
                if game_dir not in sys.path:
                    sys.path.insert(0, game_dir)
                from Game import Game

            game = Game()
            valid_moves = game.getValidMoves(board, current_player)
            # This is simplified - you may need to map actions to board positions
            # For now, mark all empty valid positions as potentially valid moves
            valid_moves_mask = empty_positions.copy()
        except Exception as e:
            # Fallback if Game import fails
            valid_moves_mask = empty_positions.copy()

        channels.append(valid_moves_mask)

        # Feature planes 4-6: Mill patterns
        # Horizontal mills
        horizontal_mills = np.zeros((7, 7), dtype=np.float32)
        # Vertical mills
        vertical_mills = np.zeros((7, 7), dtype=np.float32)
        # All mill positions
        mill_positions = np.zeros((7, 7), dtype=np.float32)

        # Mark positions that are part of potential mills
        # This is simplified - full implementation would check actual mill patterns
        mill_positions = self.allowed_places.astype(np.float32)

        channels.extend([horizontal_mills, vertical_mills, mill_positions])

        # Feature planes 7-8: Pieces in hand (enhanced with training data)
        current_in_hand = np.full((7, 7), 0.0, dtype=np.float32)
        opponent_in_hand = np.full((7, 7), 0.0, dtype=np.float32)

        # Use training data if available, otherwise fallback
        if board_state and 'white_pieces_in_hand' in board_state and 'black_pieces_in_hand' in board_state:
            white_hand_count = board_state['white_pieces_in_hand']
            black_hand_count = board_state['black_pieces_in_hand']

            if current_player == 1:  # White
                current_hand_count = white_hand_count
                opponent_hand_count = black_hand_count
            else:  # Black
                current_hand_count = black_hand_count
                opponent_hand_count = white_hand_count
        elif hasattr(board, 'pieces_in_hand_count'):
            current_hand_count = board.pieces_in_hand_count(current_player)
            opponent_hand_count = board.pieces_in_hand_count(-current_player)
        else:
            # Fallback calculation
            total_pieces = 9
            current_on_board = board.count(current_player)
            opponent_on_board = board.count(-current_player)
            current_hand_count = max(0, total_pieces - current_on_board)
            opponent_hand_count = max(0, total_pieces - opponent_on_board)

        # Normalize hand count to [0, 1]
        current_in_hand.fill(current_hand_count / 9.0)
        opponent_in_hand.fill(opponent_hand_count / 9.0)

        channels.extend([current_in_hand, opponent_in_hand])

        # Feature planes 9-12: Game phase indicators (enhanced)
        placement_phase = np.zeros((7, 7), dtype=np.float32)
        moving_phase = np.zeros((7, 7), dtype=np.float32)
        flying_phase = np.zeros((7, 7), dtype=np.float32)
        removal_phase = np.zeros((7, 7), dtype=np.float32)

        # Use training data for accurate phase detection
        if board_state and 'is_removal_phase' in board_state:
            if board_state['is_removal_phase']:
                removal_phase.fill(1.0)
            else:
                # Determine normal phase
                phase = getattr(board, 'period', 0)
                if phase == 0:  # Placement
                    placement_phase.fill(1.0)
                elif phase == 1:  # Moving
                    moving_phase.fill(1.0)
                elif phase == 2:  # Flying
                    flying_phase.fill(1.0)
        else:
            # Fallback to original logic
            phase = getattr(board, 'period', 0)
            if phase == 0:  # Placement
                placement_phase.fill(1.0)
            elif phase == 1:  # Moving
                moving_phase.fill(1.0)
            elif phase == 2:  # Flying
                flying_phase.fill(1.0)
            elif phase == 3:  # Removal
                removal_phase.fill(1.0)

        channels.extend([placement_phase, moving_phase, flying_phase, removal_phase])

        # Feature plane 13: Move count
        move_count = np.full((7, 7), 0.0, dtype=np.float32)
        if board_state and 'total_moves_played' in board_state:
            # Use training data for accurate move count
            move_count.fill(min(board_state['total_moves_played'] / 100.0, 1.0))
        elif hasattr(board, 'put_pieces'):
            # Fallback to board attribute
            move_count.fill(min(board.put_pieces / 100.0, 1.0))

        channels.append(move_count)

        # Feature plane 14: Steps to result (new)
        steps_plane = np.full((7, 7), 0.0, dtype=np.float32)
        if board_state and 'steps_to_result' in board_state:
            steps = board_state['steps_to_result']
            if steps >= 0:
                # Normalize steps to [0, 1], clamp large values
                normalized_steps = min(steps / 50.0, 1.0)  # Assume max 50 steps
                steps_plane.fill(normalized_steps)

        channels.append(steps_plane)

        # Feature planes 15-16: Piece count indicators
        current_piece_count = np.full((7, 7), 0.0, dtype=np.float32)
        opponent_piece_count = np.full((7, 7), 0.0, dtype=np.float32)

        # Use training data if available
        if board_state and 'white_pieces_on_board' in board_state and 'black_pieces_on_board' in board_state:
            white_count = board_state['white_pieces_on_board']
            black_count = board_state['black_pieces_on_board']

            if current_player == 1:  # White
                current_piece_count.fill(white_count / 9.0)
                opponent_piece_count.fill(black_count / 9.0)
            else:  # Black
                current_piece_count.fill(black_count / 9.0)
                opponent_piece_count.fill(white_count / 9.0)
        else:
            # Fallback to counting from board
            current_piece_count.fill(board.count(current_player) / 9.0)
            opponent_piece_count.fill(board.count(-current_player) / 9.0)

        channels.extend([current_piece_count, opponent_piece_count])

        # Feature planes 17-18: Player indicator and bias
        current_player_plane = np.full((7, 7), 1.0 if current_player == 1 else 0.0, dtype=np.float32)
        constant_plane = np.ones((7, 7), dtype=np.float32)

        channels.extend([current_player_plane, constant_plane])

        # Stack all channels
        board_tensor = torch.FloatTensor(np.stack(channels))

        assert board_tensor.shape == (19, 7, 7), f"Expected (19, 7, 7), got {board_tensor.shape}"

        return board_tensor


class AlphaZeroNetworkWrapper:
    """
    Wrapper class for Alpha Zero network with training utilities.

    Provides higher-level interface for training and inference.
    """

    def __init__(self,
                 model_args: Dict[str, Any],
                 device: Optional[str] = None):
        """
        Initialize network wrapper.

        Args:
            model_args: Model configuration parameters
            device: Device to run on ('cuda' or 'cpu')
        """
        self.device = device or ('cuda' if torch.cuda.is_available() else 'cpu')
        self.model_args = model_args

        # Initialize network
        self.net = AlphaZeroNet(**model_args).to(self.device)
        self.encoder = MillBoardEncoder()

        # Training utilities
        self.optimizer = None
        self.loss_fn_policy = nn.CrossEntropyLoss()
        self.loss_fn_value = nn.MSELoss()

        logger.info(f"AlphaZeroNetworkWrapper initialized on device: {self.device}")

    def predict(self, board, current_player: int = 1) -> Tuple[np.ndarray, float]:
        """
        Predict policy and value for a board position.

        Args:
            board: Board object
            current_player: Current player

        Returns:
            Tuple of (policy_probabilities, value_estimate)
        """
        board_tensor = self.encoder.encode_board(board, current_player)
        board_tensor = board_tensor.to(self.device)

        return self.net.predict(board_tensor)

    def train_step(self,
                   boards: list,
                   target_policies: list,
                   target_values: list,
                   learning_rate: float = 1e-3) -> Dict[str, float]:
        """
        Perform a single training step.

        Args:
            boards: List of board objects
            target_policies: List of target policy distributions
            target_values: List of target values
            learning_rate: Learning rate for optimization

        Returns:
            Dictionary of loss values
        """
        if self.optimizer is None:
            self.optimizer = torch.optim.Adam(self.net.parameters(), lr=learning_rate)

        # Encode boards
        board_tensors = []
        for i, board in enumerate(boards):
            # Determine current player from the training data context
            # This is simplified - you may need to pass player info explicitly
            current_player = 1  # Default to white
            board_tensor = self.encoder.encode_board(board, current_player)
            board_tensors.append(board_tensor)

        # Stack tensors
        batch_boards = torch.stack(board_tensors).to(self.device)
        batch_policies = torch.FloatTensor(target_policies).to(self.device)
        batch_values = torch.FloatTensor(target_values).to(self.device)

        # Forward pass
        self.net.train()
        pred_policies, pred_values = self.net(batch_boards)

        # Calculate losses
        policy_loss = self.loss_fn_policy(pred_policies, batch_policies)
        value_loss = self.loss_fn_value(pred_values.squeeze(), batch_values)
        total_loss = policy_loss + value_loss

        # Backward pass
        self.optimizer.zero_grad()
        total_loss.backward()
        self.optimizer.step()

        return {
            'total_loss': total_loss.item(),
            'policy_loss': policy_loss.item(),
            'value_loss': value_loss.item()
        }

    def save(self, filepath: str):
        """Save model checkpoint."""
        checkpoint = {
            'model_state_dict': self.net.state_dict(),
            'model_args': self.model_args,
            'optimizer_state_dict': self.optimizer.state_dict() if self.optimizer else None
        }
        torch.save(checkpoint, filepath)
        logger.info(f"Model saved to {filepath}")

    def load(self, filepath: str) -> bool:
        """
        Load model checkpoint.

        Args:
            filepath: Path to checkpoint file

        Returns:
            True if loaded successfully, False otherwise
        """
        try:
            checkpoint = torch.load(filepath, map_location=self.device)
            self.net.load_state_dict(checkpoint['model_state_dict'])

            if checkpoint.get('optimizer_state_dict') and self.optimizer:
                self.optimizer.load_state_dict(checkpoint['optimizer_state_dict'])

            logger.info(f"Model loaded from {filepath}")
            return True
        except Exception as e:
            logger.error(f"Failed to load model from {filepath}: {e}")
            return False
