#!/usr/bin/env python3
"""
Training Results Visualization Tool for NNUE Training

This script reads training metrics from CSV files and generates comprehensive
visualization plots for analyzing NNUE training performance.

Usage:
    python plot_training_results.py --csv training_metrics.csv
    python plot_training_results.py --csv nnue_output/plots/training_metrics.csv --output results.png
    python plot_training_results.py --directory nnue_output/plots --interactive
"""

import argparse
import pandas as pd
import numpy as np
from pathlib import Path
import sys
import logging
from typing import Optional, List

try:
    import matplotlib.pyplot as plt
    import matplotlib.style as mplstyle
    PLOTTING_AVAILABLE = True
except ImportError:
    PLOTTING_AVAILABLE = False
    plt = None

try:
    import seaborn as sns
    SEABORN_AVAILABLE = True
except ImportError:
    SEABORN_AVAILABLE = False
    sns = None

# Set up logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Configure plotting style
if PLOTTING_AVAILABLE:
    # Try to use a nice style
    available_styles = plt.style.available
    if 'seaborn-v0_8' in available_styles:
        plt.style.use('seaborn-v0_8')
    elif 'seaborn' in available_styles:
        plt.style.use('seaborn')
    elif 'ggplot' in available_styles:
        plt.style.use('ggplot')
    else:
        plt.style.use('default')
    
    # Set up nice colors
    if SEABORN_AVAILABLE:
        sns.set_palette("husl")
    else:
        # Use matplotlib's default color cycle
        plt.rcParams['axes.prop_cycle'] = plt.cycler(color=[
            '#1f77b4', '#ff7f0e', '#2ca02c', '#d62728', '#9467bd',
            '#8c564b', '#e377c2', '#7f7f7f', '#bcbd22', '#17becf'
        ])

class TrainingResultsPlotter:
    """
    Comprehensive visualization tool for NNUE training results
    """
    
    def __init__(self, csv_file: str, output_dir: str = "plots"):
        if not PLOTTING_AVAILABLE:
            raise ImportError("Matplotlib is required for plotting. Install with: pip install matplotlib")
        
        self.csv_file = Path(csv_file)
        self.output_dir = Path(output_dir)
        self.output_dir.mkdir(exist_ok=True)
        
        # Load data
        self.data = self.load_training_data()
        if self.data is None:
            raise ValueError(f"Failed to load training data from {csv_file}")
        
        logger.info(f"Loaded training data: {len(self.data)} epochs")
        
    def load_training_data(self) -> Optional[pd.DataFrame]:
        """Load training metrics from CSV file"""
        try:
            if not self.csv_file.exists():
                logger.error(f"CSV file not found: {self.csv_file}")
                return None
            
            data = pd.read_csv(self.csv_file)
            
            # Validate required columns
            required_columns = ['Epoch', 'Train_Loss', 'Val_Loss', 'Val_Accuracy', 
                              'Learning_Rate', 'Gradient_Norm', 'Epoch_Time']
            missing_columns = [col for col in required_columns if col not in data.columns]
            
            if missing_columns:
                logger.error(f"Missing required columns: {missing_columns}")
                logger.info(f"Available columns: {list(data.columns)}")
                return None
            
            # Data validation
            if len(data) == 0:
                logger.error("CSV file is empty")
                return None
            
            # Clean data - remove any rows with all NaN values
            data = data.dropna(how='all')
            
            # Sort by epoch to ensure proper ordering
            data = data.sort_values('Epoch').reset_index(drop=True)
            
            logger.info(f"Data summary:")
            logger.info(f"  Epochs: {data['Epoch'].min():.0f} - {data['Epoch'].max():.0f}")
            logger.info(f"  Final train loss: {data['Train_Loss'].iloc[-1]:.6f}")
            logger.info(f"  Final val loss: {data['Val_Loss'].iloc[-1]:.6f}")
            logger.info(f"  Best val accuracy: {data['Val_Accuracy'].max():.4f}")
            
            return data
            
        except Exception as e:
            logger.error(f"Error loading CSV file: {e}")
            return None
    
    def create_comprehensive_plot(self, save_path: Optional[str] = None, 
                                show_plot: bool = False) -> str:
        """Create a comprehensive 6-panel training analysis plot"""
        
        # Create figure with subplots
        fig, axes = plt.subplots(2, 3, figsize=(18, 12))
        fig.suptitle('NNUE Training Results Analysis', fontsize=16, fontweight='bold')
        
        # 1. Loss Curves
        ax1 = axes[0, 0]
        ax1.plot(self.data['Epoch'], self.data['Train_Loss'], 'b-', linewidth=2, label='Training Loss', alpha=0.8)
        ax1.plot(self.data['Epoch'], self.data['Val_Loss'], 'r-', linewidth=2, label='Validation Loss', alpha=0.8)
        ax1.set_xlabel('Epoch')
        ax1.set_ylabel('Loss')
        ax1.set_title('Loss Curves')
        ax1.legend()
        ax1.grid(True, alpha=0.3)
        ax1.set_yscale('log')  # Log scale for better visualization
        
        # Add best validation loss annotation
        best_val_idx = self.data['Val_Loss'].idxmin()
        best_val_loss = self.data['Val_Loss'].iloc[best_val_idx]
        best_epoch = self.data['Epoch'].iloc[best_val_idx]
        ax1.annotate(f'Best Val Loss: {best_val_loss:.6f}\nEpoch: {best_epoch:.0f}', 
                    xy=(best_epoch, best_val_loss), xytext=(0.7, 0.8),
                    textcoords='axes fraction', fontsize=10,
                    bbox=dict(boxstyle='round', facecolor='yellow', alpha=0.7),
                    arrowprops=dict(arrowstyle='->', color='red'))
        
        # 2. Validation Accuracy
        ax2 = axes[0, 1]
        ax2.plot(self.data['Epoch'], self.data['Val_Accuracy'], 'g-', linewidth=2, alpha=0.8)
        ax2.set_xlabel('Epoch')
        ax2.set_ylabel('Accuracy')
        ax2.set_title('Validation Accuracy')
        ax2.grid(True, alpha=0.3)
        ax2.set_ylim([0, 1])
        
        # Add best accuracy annotation
        best_acc = self.data['Val_Accuracy'].max()
        best_acc_epoch = self.data['Epoch'].iloc[self.data['Val_Accuracy'].idxmax()]
        ax2.annotate(f'Best Accuracy: {best_acc:.4f}\nEpoch: {best_acc_epoch:.0f}', 
                    xy=(best_acc_epoch, best_acc), xytext=(0.05, 0.8),
                    textcoords='axes fraction', fontsize=10,
                    bbox=dict(boxstyle='round', facecolor='lightgreen', alpha=0.7),
                    arrowprops=dict(arrowstyle='->', color='green'))
        
        # 3. Learning Rate Schedule
        ax3 = axes[0, 2]
        ax3.plot(self.data['Epoch'], self.data['Learning_Rate'], 'purple', linewidth=2, alpha=0.8)
        ax3.set_xlabel('Epoch')
        ax3.set_ylabel('Learning Rate')
        ax3.set_title('Learning Rate Schedule')
        ax3.grid(True, alpha=0.3)
        ax3.set_yscale('log')
        
        # 4. Gradient Norms
        ax4 = axes[1, 0]
        ax4.plot(self.data['Epoch'], self.data['Gradient_Norm'], 'orange', linewidth=2, alpha=0.8)
        ax4.set_xlabel('Epoch')
        ax4.set_ylabel('Gradient Norm')
        ax4.set_title('Gradient Norms')
        ax4.grid(True, alpha=0.3)
        
        # Add warning zones for gradient issues
        ax4.axhline(y=10.0, color='red', linestyle='--', alpha=0.5, label='High Gradient Warning')
        ax4.axhline(y=0.001, color='blue', linestyle='--', alpha=0.5, label='Low Gradient Warning')
        ax4.legend(fontsize=8)
        
        # 5. Training Time Analysis
        ax5 = axes[1, 1]
        ax5.plot(self.data['Epoch'], self.data['Epoch_Time'], 'brown', linewidth=2, alpha=0.8)
        ax5.set_xlabel('Epoch')
        ax5.set_ylabel('Time (seconds)')
        ax5.set_title('Epoch Training Time')
        ax5.grid(True, alpha=0.3)
        
        # Add average time line
        avg_time = self.data['Epoch_Time'].mean()
        ax5.axhline(y=avg_time, color='red', linestyle='--', alpha=0.7)
        ax5.text(0.02, 0.98, f'Avg: {avg_time:.1f}s', 
                transform=ax5.transAxes, verticalalignment='top', fontsize=10,
                bbox=dict(boxstyle='round', facecolor='white', alpha=0.8))
        
        # 6. Overfitting Analysis (Val/Train Loss Ratio)
        ax6 = axes[1, 2]
        loss_ratios = self.data['Val_Loss'] / self.data['Train_Loss']
        ax6.plot(self.data['Epoch'], loss_ratios, 'teal', linewidth=2, alpha=0.8)
        ax6.set_xlabel('Epoch')
        ax6.set_ylabel('Val Loss / Train Loss')
        ax6.set_title('Overfitting Indicator')
        ax6.grid(True, alpha=0.3)
        
        # Add threshold lines
        ax6.axhline(y=1.0, color='green', linestyle='--', alpha=0.7, label='Ideal (1.0)')
        ax6.axhline(y=1.2, color='orange', linestyle='--', alpha=0.5, label='Warning (1.2)')
        ax6.axhline(y=1.5, color='red', linestyle='--', alpha=0.5, label='Overfitting (1.5)')
        ax6.legend(fontsize=8)
        
        plt.tight_layout()
        
        # Save plot
        if save_path is None:
            save_path = self.output_dir / "training_analysis_comprehensive.png"
        else:
            save_path = Path(save_path)
        
        plt.savefig(save_path, dpi=300, bbox_inches='tight', facecolor='white')
        logger.info(f"Comprehensive training plot saved to {save_path}")
        
        if show_plot:
            plt.show()
        else:
            plt.close()
            
        return str(save_path)
    
    def create_loss_convergence_plot(self, save_path: Optional[str] = None, 
                                   show_plot: bool = False) -> str:
        """Create a detailed loss convergence analysis plot"""
        
        fig, ((ax1, ax2), (ax3, ax4)) = plt.subplots(2, 2, figsize=(15, 10))
        fig.suptitle('Loss Convergence Analysis', fontsize=16, fontweight='bold')
        
        # 1. Linear scale loss
        ax1.plot(self.data['Epoch'], self.data['Train_Loss'], 'b-', linewidth=2, label='Training Loss', alpha=0.8)
        ax1.plot(self.data['Epoch'], self.data['Val_Loss'], 'r-', linewidth=2, label='Validation Loss', alpha=0.8)
        ax1.set_xlabel('Epoch')
        ax1.set_ylabel('Loss')
        ax1.set_title('Loss Curves (Linear Scale)')
        ax1.legend()
        ax1.grid(True, alpha=0.3)
        
        # 2. Log scale loss
        ax2.plot(self.data['Epoch'], self.data['Train_Loss'], 'b-', linewidth=2, label='Training Loss', alpha=0.8)
        ax2.plot(self.data['Epoch'], self.data['Val_Loss'], 'r-', linewidth=2, label='Validation Loss', alpha=0.8)
        ax2.set_xlabel('Epoch')
        ax2.set_ylabel('Loss (Log Scale)')
        ax2.set_title('Loss Curves (Log Scale)')
        ax2.set_yscale('log')
        ax2.legend()
        ax2.grid(True, alpha=0.3)
        
        # 3. Loss difference
        loss_diff = self.data['Val_Loss'] - self.data['Train_Loss']
        ax3.plot(self.data['Epoch'], loss_diff, 'purple', linewidth=2, alpha=0.8)
        ax3.set_xlabel('Epoch')
        ax3.set_ylabel('Val Loss - Train Loss')
        ax3.set_title('Loss Difference (Val - Train)')
        ax3.grid(True, alpha=0.3)
        ax3.axhline(y=0, color='black', linestyle='-', alpha=0.3)
        
        # 4. Moving average of losses (smoothed trends)
        window = max(5, len(self.data) // 20)  # Adaptive window size
        train_ma = self.data['Train_Loss'].rolling(window=window, center=True).mean()
        val_ma = self.data['Val_Loss'].rolling(window=window, center=True).mean()
        
        ax4.plot(self.data['Epoch'], train_ma, 'b-', linewidth=3, label=f'Train MA({window})', alpha=0.8)
        ax4.plot(self.data['Epoch'], val_ma, 'r-', linewidth=3, label=f'Val MA({window})', alpha=0.8)
        ax4.plot(self.data['Epoch'], self.data['Train_Loss'], 'b-', linewidth=1, alpha=0.3)
        ax4.plot(self.data['Epoch'], self.data['Val_Loss'], 'r-', linewidth=1, alpha=0.3)
        ax4.set_xlabel('Epoch')
        ax4.set_ylabel('Loss')
        ax4.set_title('Smoothed Loss Trends')
        ax4.legend()
        ax4.grid(True, alpha=0.3)
        
        plt.tight_layout()
        
        # Save plot
        if save_path is None:
            save_path = self.output_dir / "loss_convergence_analysis.png"
        else:
            save_path = Path(save_path)
        
        plt.savefig(save_path, dpi=300, bbox_inches='tight', facecolor='white')
        logger.info(f"Loss convergence plot saved to {save_path}")
        
        if show_plot:
            plt.show()
        else:
            plt.close()
            
        return str(save_path)
    
    def create_performance_summary(self, save_path: Optional[str] = None, 
                                 show_plot: bool = False) -> str:
        """Create a performance summary with key statistics"""
        
        fig, ((ax1, ax2), (ax3, ax4)) = plt.subplots(2, 2, figsize=(15, 10))
        fig.suptitle('Training Performance Summary', fontsize=16, fontweight='bold')
        
        # 1. Training progress histogram
        ax1.hist(self.data['Train_Loss'], bins=30, alpha=0.7, color='blue', label='Train Loss', density=True)
        ax1.hist(self.data['Val_Loss'], bins=30, alpha=0.7, color='red', label='Val Loss', density=True)
        ax1.set_xlabel('Loss Value')
        ax1.set_ylabel('Density')
        ax1.set_title('Loss Distribution')
        ax1.legend()
        ax1.grid(True, alpha=0.3)
        
        # 2. Accuracy improvement over time
        ax2.plot(self.data['Epoch'], self.data['Val_Accuracy'], 'g-', linewidth=2, alpha=0.8)
        # Add trend line
        z = np.polyfit(self.data['Epoch'], self.data['Val_Accuracy'], 1)
        p = np.poly1d(z)
        ax2.plot(self.data['Epoch'], p(self.data['Epoch']), 'k--', alpha=0.7, 
                label=f'Trend: {z[0]:.6f}x + {z[1]:.4f}')
        ax2.set_xlabel('Epoch')
        ax2.set_ylabel('Validation Accuracy')
        ax2.set_title('Accuracy Trend Analysis')
        ax2.legend()
        ax2.grid(True, alpha=0.3)
        
        # 3. Learning rate vs loss correlation
        ax3.scatter(self.data['Learning_Rate'], self.data['Val_Loss'], 
                   c=self.data['Epoch'], cmap='viridis', alpha=0.7, s=30)
        ax3.set_xlabel('Learning Rate')
        ax3.set_ylabel('Validation Loss')
        ax3.set_title('LR vs Loss Correlation')
        ax3.set_xscale('log')
        ax3.set_yscale('log')
        ax3.grid(True, alpha=0.3)
        
        # Add colorbar for epochs
        cbar = plt.colorbar(ax3.collections[0], ax=ax3)
        cbar.set_label('Epoch')
        
        # 4. Training efficiency (loss reduction per time)
        total_time = self.data['Epoch_Time'].sum()
        initial_loss = self.data['Val_Loss'].iloc[0]
        final_loss = self.data['Val_Loss'].iloc[-1]
        loss_reduction = initial_loss - final_loss
        efficiency = loss_reduction / total_time
        
        # Create text summary
        ax4.axis('off')
        summary_text = f"""
Training Summary Statistics:

• Total Epochs: {len(self.data):,}
• Total Training Time: {total_time:.1f} seconds ({total_time/3600:.2f} hours)
• Average Time per Epoch: {self.data['Epoch_Time'].mean():.2f} seconds

• Initial Training Loss: {self.data['Train_Loss'].iloc[0]:.6f}
• Final Training Loss: {self.data['Train_Loss'].iloc[-1]:.6f}
• Training Loss Reduction: {self.data['Train_Loss'].iloc[0] - self.data['Train_Loss'].iloc[-1]:.6f}

• Initial Validation Loss: {initial_loss:.6f}
• Final Validation Loss: {final_loss:.6f}
• Validation Loss Reduction: {loss_reduction:.6f}

• Best Validation Loss: {self.data['Val_Loss'].min():.6f}
• Best Validation Accuracy: {self.data['Val_Accuracy'].max():.4f}

• Final Learning Rate: {self.data['Learning_Rate'].iloc[-1]:.2e}
• Average Gradient Norm: {self.data['Gradient_Norm'].mean():.4f}

• Training Efficiency: {efficiency:.8f} loss reduction per second
        """
        
        ax4.text(0.05, 0.95, summary_text, transform=ax4.transAxes, fontsize=11,
                verticalalignment='top', fontfamily='monospace',
                bbox=dict(boxstyle='round', facecolor='lightblue', alpha=0.8))
        
        plt.tight_layout()
        
        # Save plot
        if save_path is None:
            save_path = self.output_dir / "performance_summary.png"
        else:
            save_path = Path(save_path)
        
        plt.savefig(save_path, dpi=300, bbox_inches='tight', facecolor='white')
        logger.info(f"Performance summary saved to {save_path}")
        
        if show_plot:
            plt.show()
        else:
            plt.close()
            
        return str(save_path)
    
    def generate_all_plots(self, show_plots: bool = False) -> List[str]:
        """Generate all available visualization plots"""
        
        logger.info("Generating comprehensive training visualization...")
        generated_files = []
        
        try:
            # Generate all plot types
            comprehensive_plot = self.create_comprehensive_plot(show_plot=show_plots)
            generated_files.append(comprehensive_plot)
            
            convergence_plot = self.create_loss_convergence_plot(show_plot=show_plots)
            generated_files.append(convergence_plot)
            
            summary_plot = self.create_performance_summary(show_plot=show_plots)
            generated_files.append(summary_plot)
            
            logger.info(f"Successfully generated {len(generated_files)} visualization plots:")
            for file_path in generated_files:
                logger.info(f"  • {file_path}")
                
        except Exception as e:
            logger.error(f"Error generating plots: {e}")
            raise
            
        return generated_files


def find_csv_files(directory: str) -> List[Path]:
    """Find all training_metrics.csv files in a directory"""
    directory = Path(directory)
    csv_files = []
    
    # Look for training_metrics.csv
    direct_csv = directory / "training_metrics.csv"
    if direct_csv.exists():
        csv_files.append(direct_csv)
    
    # Look in subdirectories
    for subdir in directory.glob("*/"):
        if subdir.is_dir():
            subdir_csv = subdir / "training_metrics.csv"
            if subdir_csv.exists():
                csv_files.append(subdir_csv)
    
    return csv_files


def main():
    parser = argparse.ArgumentParser(description="Visualize NNUE training results from CSV data")
    
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--csv', type=str, help='Path to training_metrics.csv file')
    group.add_argument('--directory', type=str, help='Directory to search for training_metrics.csv files')
    
    parser.add_argument('--output', type=str, help='Output directory for plots (default: plots/)')
    parser.add_argument('--show', action='store_true', help='Display plots interactively')
    parser.add_argument('--comprehensive-only', action='store_true', 
                       help='Generate only the comprehensive plot')
    
    args = parser.parse_args()
    
    # Set up output directory
    output_dir = args.output if args.output else "plots"
    
    csv_files = []
    if args.csv:
        csv_file = Path(args.csv)
        if not csv_file.exists():
            logger.error(f"CSV file not found: {csv_file}")
            return 1
        csv_files = [csv_file]
    else:
        csv_files = find_csv_files(args.directory)
        if not csv_files:
            logger.error(f"No training_metrics.csv files found in directory: {args.directory}")
            return 1
        logger.info(f"Found {len(csv_files)} CSV files to process")
    
    # Process each CSV file
    for csv_file in csv_files:
        logger.info(f"Processing: {csv_file}")
        
        try:
            # Create plotter
            plotter = TrainingResultsPlotter(str(csv_file), output_dir)
            
            if args.comprehensive_only:
                # Generate only comprehensive plot
                plot_file = plotter.create_comprehensive_plot(show_plot=args.show)
                logger.info(f"Generated comprehensive plot: {plot_file}")
            else:
                # Generate all plots
                generated_files = plotter.generate_all_plots(show_plots=args.show)
                logger.info(f"Successfully processed {csv_file}")
                
        except Exception as e:
            logger.error(f"Failed to process {csv_file}: {e}")
            continue
    
    logger.info("Visualization generation completed!")
    return 0


if __name__ == '__main__':
    sys.exit(main())
