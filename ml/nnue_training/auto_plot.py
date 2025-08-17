#!/usr/bin/env python3
"""
Automatic plotting integration for NNUE training

This script automatically detects training CSV files and generates visualizations.
It can be called from train_nnue.py or used standalone.
"""

import os
import sys
from pathlib import Path
import logging

# Add current directory to path to import plot_training_results
sys.path.insert(0, str(Path(__file__).parent))

logger = logging.getLogger(__name__)

def auto_generate_plots(csv_file: str = None, output_dir: str = None, 
                       comprehensive_only: bool = False) -> bool:
    """
    Automatically generate training plots from CSV data
    
    This function is optimized to be called only AFTER training completion
    to avoid interrupting the training process with frequent plotting.
    
    Args:
        csv_file: Path to CSV file (if None, searches for training_metrics.csv)
        output_dir: Output directory for plots (if None, uses 'plots')
        comprehensive_only: If True, only generate comprehensive plot for faster execution
        
    Returns:
        True if successful, False otherwise
    """
    try:
        from plot_training_results import TrainingResultsPlotter, find_csv_files
        
        # Find CSV file if not provided
        if csv_file is None:
            # Search in common locations
            search_dirs = [
                Path.cwd() / "nnue_output" / "plots",  # Primary location for pipeline mode
                Path.cwd() / "nnue_output",
                Path.cwd(),
                Path.cwd() / "plots"  # Fallback for legacy mode
            ]
            
            for search_dir in search_dirs:
                if search_dir.exists():
                    csv_files = find_csv_files(str(search_dir))
                    if csv_files:
                        csv_file = str(csv_files[0])  # Use the first found
                        break
            
            if csv_file is None:
                logger.warning("No training_metrics.csv file found in common locations")
                return False
        
        # Set default output directory
        if output_dir is None:
            # Try to use nnue_output/plots if it exists, otherwise fall back to plots
            nnue_plots_dir = Path.cwd() / "nnue_output" / "plots"
            if nnue_plots_dir.exists():
                output_dir = str(nnue_plots_dir)
            else:
                output_dir = "plots"
        
        logger.info(f"Generating plots from: {csv_file}")
        logger.info(f"Output directory: {output_dir}")
        
        # Create plotter and generate plots with performance timing
        import time
        start_time = time.time()
        
        plotter = TrainingResultsPlotter(csv_file, output_dir)
        
        if comprehensive_only:
            logger.info("Generating comprehensive plot only (fast mode)...")
            plot_file = plotter.create_comprehensive_plot()
            logger.info(f"Generated comprehensive plot: {plot_file}")
        else:
            logger.info("Generating all training visualization plots...")
            generated_files = plotter.generate_all_plots()
            if generated_files:
                logger.info(f"Successfully generated {len(generated_files)} visualization plots:")
                for plot_file in generated_files:
                    logger.info(f"  • {plot_file}")
            else:
                logger.warning("No plots were generated")
        
        elapsed_time = time.time() - start_time
        logger.info(f"Plot generation completed in {elapsed_time:.2f} seconds")
        return True
        
    except ImportError as e:
        logger.error(f"Missing dependencies for plotting: {e}")
        logger.info("Install dependencies with: pip install matplotlib pandas")
        return False
    except Exception as e:
        logger.error(f"Failed to generate plots: {e}")
        return False


def main():
    """Command line interface for auto plotting"""
    import argparse
    
    parser = argparse.ArgumentParser(description="Automatically generate NNUE training plots")
    parser.add_argument('--csv', type=str, help='Path to training CSV file')
    parser.add_argument('--output', type=str, help='Output directory for plots')
    parser.add_argument('--comprehensive-only', action='store_true', 
                       help='Generate only comprehensive plot')
    parser.add_argument('--verbose', '-v', action='store_true', help='Verbose logging')
    
    args = parser.parse_args()
    
    # Set up logging
    log_level = logging.DEBUG if args.verbose else logging.INFO
    logging.basicConfig(level=log_level, format='%(asctime)s - %(levelname)s - %(message)s')
    
    # Generate plots
    success = auto_generate_plots(
        csv_file=args.csv,
        output_dir=args.output,
        comprehensive_only=args.comprehensive_only
    )
    
    if success:
        logger.info("Plot generation completed successfully!")
        return 0
    else:
        logger.error("Plot generation failed!")
        return 1


if __name__ == '__main__':
    sys.exit(main())
