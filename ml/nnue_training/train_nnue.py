#!/usr/bin/env python3
"""
NNUE training script for Sanmill
Uses training data generated from Perfect Database to train the neural network
"""

import torch
import torch.nn as nn
import torch.optim as optim
import torch.nn.functional as F
from torch.utils.data import Dataset, DataLoader
import numpy as np
import argparse
import os
import time
from typing import Tuple, List, Optional
import logging
from pathlib import Path

# Set up logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

class MillNNUE(nn.Module):
    """
    NNUE model for Mill game evaluation
    Architecture: Input features -> Hidden layer (ReLU) -> Output
    """
    
    def __init__(self, feature_size: int = 95, hidden_size: int = 256):
        super(MillNNUE, self).__init__()
        self.feature_size = feature_size
        self.hidden_size = hidden_size
        
        # Input layer to hidden layer
        self.input_layer = nn.Linear(feature_size, hidden_size)
        
        # Hidden layer for both perspectives (white and black)
        self.hidden_white = nn.Linear(hidden_size, hidden_size)
        self.hidden_black = nn.Linear(hidden_size, hidden_size)
        
        # Output layer (combine both perspectives)
        self.output_layer = nn.Linear(hidden_size * 2, 1)
        
        # Initialize weights
        self._init_weights()
    
    def _init_weights(self):
        """Initialize network weights"""
        for m in self.modules():
            if isinstance(m, nn.Linear):
                nn.init.kaiming_normal_(m.weight, mode='fan_out', nonlinearity='relu')
                if m.bias is not None:
                    nn.init.constant_(m.bias, 0)
    
    def forward(self, x: torch.Tensor, side_to_move: torch.Tensor) -> torch.Tensor:
        """
        Forward pass
        Args:
            x: Feature tensor [batch_size, feature_size]
            side_to_move: Side to move tensor [batch_size], 0=white, 1=black
        Returns:
            Evaluation tensor [batch_size, 1]
        """
        batch_size = x.size(0)
        
        # Input to hidden transformation
        hidden = F.relu(self.input_layer(x))
        
        # Perspective-specific transformations
        hidden_w = F.relu(self.hidden_white(hidden))
        hidden_b = F.relu(self.hidden_black(hidden))
        
        # Combine perspectives based on side to move
        # For each sample, choose the appropriate perspective
        combined = torch.zeros(batch_size, self.hidden_size * 2, device=x.device)
        
        # White to move: use white perspective first
        white_mask = (side_to_move == 0).unsqueeze(1)
        combined[white_mask.squeeze(), :self.hidden_size] = hidden_w[white_mask.squeeze()]
        combined[white_mask.squeeze(), self.hidden_size:] = hidden_b[white_mask.squeeze()]
        
        # Black to move: use black perspective first
        black_mask = (side_to_move == 1).unsqueeze(1)
        combined[black_mask.squeeze(), :self.hidden_size] = hidden_b[black_mask.squeeze()]
        combined[black_mask.squeeze(), self.hidden_size:] = hidden_w[black_mask.squeeze()]
        
        # Final output
        output = self.output_layer(combined)
        return output

class MillDataset(Dataset):
    """Dataset for Mill NNUE training"""
    
    def __init__(self, data_file: str, max_samples: Optional[int] = None):
        """
        Load training data from file
        Args:
            data_file: Path to training data file
            max_samples: Maximum number of samples to load (None for all)
        """
        self.features = []
        self.targets = []
        self.side_to_move = []
        self.phases = []
        
        self._load_data(data_file, max_samples)
        
        # Convert to tensors
        self.features = torch.tensor(self.features, dtype=torch.float32)
        self.targets = torch.tensor(self.targets, dtype=torch.float32).unsqueeze(1)
        self.side_to_move = torch.tensor(self.side_to_move, dtype=torch.long)
        
        logger.info(f"Loaded {len(self.features)} training samples")
    
    def _load_data(self, data_file: str, max_samples: Optional[int]):
        """Load data from training file"""
        with open(data_file, 'r') as f:
            lines = f.readlines()
        
        # Skip header comments
        data_lines = [line for line in lines if not line.startswith('#')]
        
        if len(data_lines) == 0:
            raise ValueError("No data found in training file")
        
        # First line should contain the number of samples
        try:
            total_samples = int(data_lines[0].strip())
            data_lines = data_lines[1:]
        except (ValueError, IndexError):
            logger.warning("Could not read sample count, processing all lines")
            total_samples = len(data_lines)
        
        if max_samples:
            total_samples = min(total_samples, max_samples)
            data_lines = data_lines[:total_samples]
        
        logger.info(f"Processing {len(data_lines)} data lines...")
        
        for i, line in enumerate(data_lines):
            if i % 10000 == 0:
                logger.info(f"Processed {i}/{len(data_lines)} samples")
            
            try:
                parts = line.strip().split(' | ')
                if len(parts) < 4:
                    continue
                
                # Parse features
                feature_str = parts[0]
                features = [int(x) for x in feature_str.split()]
                
                # Parse target evaluation
                target = float(parts[1])
                
                # Parse phase (not used directly in training but useful for analysis)
                phase = int(parts[2])
                
                # Parse FEN to extract side to move
                fen = parts[3]
                fen_parts = fen.split()
                if len(fen_parts) >= 2:
                    side = 0 if fen_parts[1] == 'w' else 1
                else:
                    side = 0  # Default to white
                
                self.features.append(features)
                self.targets.append(target)
                self.side_to_move.append(side)
                self.phases.append(phase)
                
            except (ValueError, IndexError) as e:
                logger.warning(f"Skipping malformed line {i}: {e}")
                continue
    
    def __len__(self):
        return len(self.features)
    
    def __getitem__(self, idx):
        return {
            'features': self.features[idx],
            'target': self.targets[idx],
            'side_to_move': self.side_to_move[idx]
        }

def train_epoch(model: nn.Module, 
                dataloader: DataLoader, 
                optimizer: torch.optim.Optimizer, 
                criterion: nn.Module,
                device: torch.device) -> float:
    """Train for one epoch"""
    model.train()
    total_loss = 0.0
    num_batches = 0
    
    for batch in dataloader:
        features = batch['features'].to(device)
        targets = batch['target'].to(device)
        side_to_move = batch['side_to_move'].to(device)
        
        optimizer.zero_grad()
        
        # Forward pass
        outputs = model(features, side_to_move)
        loss = criterion(outputs, targets)
        
        # Backward pass
        loss.backward()
        optimizer.step()
        
        total_loss += loss.item()
        num_batches += 1
    
    return total_loss / num_batches

def validate_epoch(model: nn.Module, 
                  dataloader: DataLoader, 
                  criterion: nn.Module,
                  device: torch.device) -> Tuple[float, float]:
    """Validate for one epoch"""
    model.eval()
    total_loss = 0.0
    total_accuracy = 0.0
    num_batches = 0
    
    with torch.no_grad():
        for batch in dataloader:
            features = batch['features'].to(device)
            targets = batch['target'].to(device)
            side_to_move = batch['side_to_move'].to(device)
            
            outputs = model(features, side_to_move)
            loss = criterion(outputs, targets)
            
            # Calculate accuracy (for win/loss/draw predictions)
            predictions = torch.sign(outputs)
            target_signs = torch.sign(targets)
            accuracy = (predictions == target_signs).float().mean()
            
            total_loss += loss.item()
            total_accuracy += accuracy.item()
            num_batches += 1
    
    return total_loss / num_batches, total_accuracy / num_batches

def save_model_c_format(model: nn.Module, filepath: str):
    """Save model in C++ compatible format"""
    model.eval()
    
    # Extract weights and biases
    input_weights = model.input_layer.weight.detach().cpu().numpy()
    input_biases = model.input_layer.bias.detach().cpu().numpy()
    
    hidden_white_weights = model.hidden_white.weight.detach().cpu().numpy()
    hidden_white_biases = model.hidden_white.bias.detach().cpu().numpy()
    
    hidden_black_weights = model.hidden_black.weight.detach().cpu().numpy()
    hidden_black_biases = model.hidden_black.bias.detach().cpu().numpy()
    
    output_weights = model.output_layer.weight.detach().cpu().numpy()
    output_bias = model.output_layer.bias.detach().cpu().numpy()
    
    # Convert to int16/int8 format for C++ and quantize consistently with C++ side
    # Scale and quantize weights
    input_scale = 1024.0
    relu_div = 64.0
    output_scale = 127.0

    input_weights_int16 = np.clip(input_weights * input_scale, -32767, 32767).astype(np.int16)
    input_biases_int32 = np.clip(input_biases * input_scale, -2147483647, 2147483647).astype(np.int32)

    # Output weights expect two HIDDEN_SIZE blocks (current + opponent)
    # Duplicate learned output to both blocks for first export
    output_weights_block = np.tile(output_weights, (1, 2))
    output_weights_int8 = np.clip(output_weights_block.flatten() * output_scale, -127, 127).astype(np.int8)
    output_bias_int32 = np.clip(output_bias * output_scale, -2147483647, 2147483647).astype(np.int32)
    
    # Save in binary format
    with open(filepath, 'wb') as f:
        # Write header
        f.write(b'SANMILL1')
        
        # Write dimensions
        f.write(np.array([model.feature_size, model.hidden_size], dtype=np.int32).tobytes())
        
        # Write weights
        f.write(input_weights_int16.tobytes())
        f.write(input_biases_int32.tobytes())
        f.write(output_weights_int8.tobytes())
        f.write(output_bias_int32.tobytes())
    
    logger.info(f"Model saved in C++ format to {filepath}")

def main():
    parser = argparse.ArgumentParser(description='Train NNUE for Mill game')
    parser.add_argument('--data', required=True, help='Training data file')
    parser.add_argument('--output', default='nnue_model.bin', help='Output model file')
    parser.add_argument('--epochs', type=int, default=100, help='Number of training epochs')
    parser.add_argument('--batch-size', type=int, default=1024, help='Batch size')
    parser.add_argument('--lr', type=float, default=0.001, help='Learning rate')
    parser.add_argument('--hidden-size', type=int, default=256, help='Hidden layer size')
    parser.add_argument('--max-samples', type=int, help='Maximum training samples')
    parser.add_argument('--val-split', type=float, default=0.1, help='Validation split ratio')
    parser.add_argument('--device', default='auto', help='Device to use (cpu/cuda/auto)')
    
    args = parser.parse_args()
    
    # Setup device
    if args.device == 'auto':
        device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
    else:
        device = torch.device(args.device)
    
    logger.info(f"Using device: {device}")
    
    # Load dataset
    logger.info("Loading training data...")
    dataset = MillDataset(args.data, args.max_samples)
    
    # Split into train/validation
    val_size = int(len(dataset) * args.val_split)
    train_size = len(dataset) - val_size
    
    train_dataset, val_dataset = torch.utils.data.random_split(
        dataset, [train_size, val_size],
        generator=torch.Generator().manual_seed(42)
    )
    
    # Create data loaders
    train_loader = DataLoader(train_dataset, batch_size=args.batch_size, shuffle=True, num_workers=4)
    val_loader = DataLoader(val_dataset, batch_size=args.batch_size, shuffle=False, num_workers=4)
    
    # Create model
    model = MillNNUE(feature_size=95, hidden_size=args.hidden_size).to(device)
    logger.info(f"Model created with {sum(p.numel() for p in model.parameters())} parameters")
    
    # Setup training
    optimizer = optim.Adam(model.parameters(), lr=args.lr)
    criterion = nn.MSELoss()
    scheduler = optim.lr_scheduler.ReduceLROnPlateau(optimizer, patience=10, factor=0.5)
    
    best_val_loss = float('inf')
    patience_counter = 0
    max_patience = 20
    
    logger.info("Starting training...")
    
    for epoch in range(args.epochs):
        start_time = time.time()
        
        # Train
        train_loss = train_epoch(model, train_loader, optimizer, criterion, device)
        
        # Validate
        val_loss, val_accuracy = validate_epoch(model, val_loader, criterion, device)
        
        # Update learning rate
        scheduler.step(val_loss)
        
        epoch_time = time.time() - start_time
        
        logger.info(f"Epoch {epoch+1}/{args.epochs}: "
                   f"Train Loss: {train_loss:.6f}, "
                   f"Val Loss: {val_loss:.6f}, "
                   f"Val Acc: {val_accuracy:.4f}, "
                   f"Time: {epoch_time:.2f}s")
        
        # Early stopping
        if val_loss < best_val_loss:
            best_val_loss = val_loss
            patience_counter = 0
            # Save best model
            torch.save(model.state_dict(), f"{args.output}.pytorch")
            save_model_c_format(model, args.output)
        else:
            patience_counter += 1
            if patience_counter >= max_patience:
                logger.info(f"Early stopping after {epoch+1} epochs")
                break
    
    logger.info(f"Training completed. Best validation loss: {best_val_loss:.6f}")
    logger.info(f"Model saved to {args.output}")

if __name__ == '__main__':
    main()
