#!/usr/bin/env python3
"""
Loss Analysis Tool for Katamill Training

Analyzes and visualizes training loss progression across iterations.
"""

import json
import os
import sys
import argparse
import logging
from pathlib import Path
from typing import Dict, List, Any, Optional

# Setup logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Try to import plotting libraries
try:
    import matplotlib.pyplot as plt
    import numpy as np
    HAS_PLOTTING = True
except ImportError:
    HAS_PLOTTING = False
    logger.warning("Matplotlib not available. Only text analysis will be provided.")


def load_training_report(report_path: str) -> Dict[str, Any]:
    """Load training report from JSON file."""
    if not os.path.exists(report_path):
        raise FileNotFoundError(f"Training report not found: {report_path}")
    
    with open(report_path, 'r') as f:
        report = json.load(f)
    
    return report


def extract_loss_data(report: Dict[str, Any]) -> Dict[str, List[float]]:
    """Extract loss progression data from training report."""
    iterations = report.get('iterations', [])
    
    loss_data = {
        'iteration': [],
        'total_loss': [],
        'policy_loss': [],
        'value_loss': [],
        'score_loss': [],
        'ownership_loss': [],
        'mill_potential_loss': [],
        'win_rate': [],
        'time_minutes': []
    }
    
    for result in iterations:
        iteration_num = result.get('iteration', 0)
        training_losses = result.get('training_losses', {})
        eval_results = result.get('eval_results', {})
        
        loss_data['iteration'].append(iteration_num)
        loss_data['total_loss'].append(training_losses.get('total', None))
        loss_data['policy_loss'].append(training_losses.get('policy', None))
        loss_data['value_loss'].append(training_losses.get('value', None))
        loss_data['score_loss'].append(training_losses.get('score', None))
        loss_data['ownership_loss'].append(training_losses.get('ownership', None))
        loss_data['mill_potential_loss'].append(training_losses.get('mill_potential', None))
        loss_data['win_rate'].append(eval_results.get('win_rate', None))
        loss_data['time_minutes'].append(result.get('time_minutes', None))
    
    return loss_data


def analyze_loss_trends(loss_data: Dict[str, List[float]]) -> Dict[str, Any]:
    """Analyze loss trends and provide insights."""
    analysis = {}
    
    # Filter out None values for analysis
    total_losses = [x for x in loss_data['total_loss'] if x is not None]
    policy_losses = [x for x in loss_data['policy_loss'] if x is not None]
    value_losses = [x for x in loss_data['value_loss'] if x is not None]
    win_rates = [x for x in loss_data['win_rate'] if x is not None]
    
    if len(total_losses) >= 2:
        # Calculate trends
        first_loss = total_losses[0]
        last_loss = total_losses[-1]
        total_trend = ((last_loss - first_loss) / first_loss) * 100
        
        analysis['total_loss_trend'] = {
            'first': first_loss,
            'last': last_loss,
            'change_percent': total_trend,
            'trend': 'improving' if total_trend < 0 else 'degrading'
        }
        
        # Calculate volatility
        if len(total_losses) > 2:
            import statistics
            volatility = statistics.stdev(total_losses) / statistics.mean(total_losses)
            analysis['loss_volatility'] = volatility
    
    if len(policy_losses) >= 2:
        first_policy = policy_losses[0]
        last_policy = policy_losses[-1]
        policy_trend = ((last_policy - first_policy) / first_policy) * 100
        
        analysis['policy_loss_trend'] = {
            'first': first_policy,
            'last': last_policy,
            'change_percent': policy_trend,
            'trend': 'improving' if policy_trend < 0 else 'degrading'
        }
    
    if len(win_rates) >= 2:
        first_wr = win_rates[0]
        last_wr = win_rates[-1]
        wr_trend = last_wr - first_wr
        
        analysis['win_rate_trend'] = {
            'first': first_wr,
            'last': last_wr,
            'change': wr_trend,
            'trend': 'improving' if wr_trend > 0 else 'degrading'
        }
    
    return analysis


def print_text_analysis(loss_data: Dict[str, List[float]], analysis: Dict[str, Any]):
    """Print detailed text analysis of loss progression."""
    print("=" * 60)
    print("KATAMILL TRAINING LOSS ANALYSIS")
    print("=" * 60)
    
    # Print iteration-by-iteration breakdown
    print("\nITERATION BREAKDOWN:")
    for i, iteration in enumerate(loss_data['iteration']):
        total = loss_data['total_loss'][i]
        policy = loss_data['policy_loss'][i]
        value = loss_data['value_loss'][i]
        win_rate = loss_data['win_rate'][i]
        time_min = loss_data['time_minutes'][i]
        
        print(f"  Iteration {iteration}:")
        if total is not None:
            print(f"    Total Loss: {total:.4f}")
            print(f"    Policy Loss: {policy:.4f}")
            print(f"    Value Loss: {value:.4f}")
        else:
            print(f"    Loss data: Not available")
        
        if win_rate is not None:
            print(f"    Win Rate: {win_rate:.1f}%")
        if time_min is not None:
            print(f"    Training Time: {time_min:.1f} minutes")
        print()
    
    # Print trend analysis
    print("TREND ANALYSIS:")
    if 'total_loss_trend' in analysis:
        trend = analysis['total_loss_trend']
        print(f"  Total Loss: {trend['first']:.4f} → {trend['last']:.4f} "
              f"({trend['change_percent']:+.1f}%) - {trend['trend']}")
    
    if 'policy_loss_trend' in analysis:
        trend = analysis['policy_loss_trend']
        print(f"  Policy Loss: {trend['first']:.4f} → {trend['last']:.4f} "
              f"({trend['change_percent']:+.1f}%) - {trend['trend']}")
    
    if 'win_rate_trend' in analysis:
        trend = analysis['win_rate_trend']
        print(f"  Win Rate: {trend['first']:.1f}% → {trend['last']:.1f}% "
              f"({trend['change']:+.1f}%) - {trend['trend']}")
    
    if 'loss_volatility' in analysis:
        volatility = analysis['loss_volatility']
        stability = "stable" if volatility < 0.1 else "volatile" if volatility < 0.3 else "very volatile"
        print(f"  Loss Stability: {volatility:.3f} ({stability})")
    
    # Provide recommendations
    print("\nRECOMMENDATIONS:")
    if 'total_loss_trend' in analysis:
        trend = analysis['total_loss_trend']
        if trend['trend'] == 'degrading':
            print("  ⚠ Loss is increasing - consider:")
            print("    - Reducing learning rate")
            print("    - Checking data quality")
            print("    - Adjusting loss weights")
        elif trend['change_percent'] < -50:
            print("  ✓ Excellent loss improvement")
        elif trend['change_percent'] < -10:
            print("  ✓ Good loss improvement")
        else:
            print("  ⚠ Minimal loss improvement - consider longer training")
    
    if 'win_rate_trend' in analysis:
        trend = analysis['win_rate_trend']
        if trend['trend'] == 'degrading':
            print("  ⚠ Win rate decreasing - model may be overfitting")
        elif trend['change'] > 10:
            print("  ✓ Strong performance improvement")


def plot_loss_curves(loss_data: Dict[str, List[float]], output_path: Optional[str] = None):
    """Plot loss curves if matplotlib is available."""
    if not HAS_PLOTTING:
        logger.warning("Cannot plot curves - matplotlib not available")
        return
    
    fig, ((ax1, ax2), (ax3, ax4)) = plt.subplots(2, 2, figsize=(12, 8))
    
    iterations = loss_data['iteration']
    
    # Total loss
    total_losses = [x for x in loss_data['total_loss'] if x is not None]
    if total_losses:
        ax1.plot(iterations[:len(total_losses)], total_losses, 'b-o', linewidth=2)
        ax1.set_title('Total Loss')
        ax1.set_xlabel('Iteration')
        ax1.set_ylabel('Loss')
        ax1.grid(True, alpha=0.3)
    
    # Policy vs Value loss
    policy_losses = [x for x in loss_data['policy_loss'] if x is not None]
    value_losses = [x for x in loss_data['value_loss'] if x is not None]
    
    if policy_losses:
        ax2.plot(iterations[:len(policy_losses)], policy_losses, 'r-o', label='Policy', linewidth=2)
    if value_losses:
        ax2.plot(iterations[:len(value_losses)], value_losses, 'g-o', label='Value', linewidth=2)
    ax2.set_title('Policy vs Value Loss')
    ax2.set_xlabel('Iteration')
    ax2.set_ylabel('Loss')
    ax2.legend()
    ax2.grid(True, alpha=0.3)
    
    # Win rate progression
    win_rates = [x for x in loss_data['win_rate'] if x is not None]
    if win_rates:
        ax3.plot(iterations[:len(win_rates)], win_rates, 'm-o', linewidth=2)
        ax3.set_title('Win Rate Progression')
        ax3.set_xlabel('Iteration')
        ax3.set_ylabel('Win Rate (%)')
        ax3.grid(True, alpha=0.3)
    
    # Training time per iteration
    times = [x for x in loss_data['time_minutes'] if x is not None]
    if times:
        ax4.bar(iterations[:len(times)], times, alpha=0.7, color='orange')
        ax4.set_title('Training Time per Iteration')
        ax4.set_xlabel('Iteration')
        ax4.set_ylabel('Time (minutes)')
        ax4.grid(True, alpha=0.3)
    
    plt.tight_layout()
    
    if output_path:
        plt.savefig(output_path, dpi=150, bbox_inches='tight')
        logger.info(f"Loss curves saved to: {output_path}")
    else:
        plt.show()


def main():
    parser = argparse.ArgumentParser(description='Analyze Katamill training loss progression')
    parser.add_argument('--report', type=str, 
                       default='output/katamill_quick/training_report.json',
                       help='Path to training report JSON file')
    parser.add_argument('--plot', action='store_true', help='Generate loss curve plots')
    parser.add_argument('--output', type=str, help='Output path for plots')
    
    args = parser.parse_args()
    
    try:
        # Load and analyze training data
        report = load_training_report(args.report)
        loss_data = extract_loss_data(report)
        analysis = analyze_loss_trends(loss_data)
        
        # Print text analysis
        print_text_analysis(loss_data, analysis)
        
        # Generate plots if requested
        if args.plot:
            plot_output = args.output or 'loss_curves.png'
            plot_loss_curves(loss_data, plot_output)
    
    except Exception as e:
        logger.error(f"Analysis failed: {e}")
        import traceback
        traceback.print_exc()


if __name__ == '__main__':
    main()
