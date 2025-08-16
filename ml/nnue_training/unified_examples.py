#!/usr/bin/env python3
"""
Examples demonstrating the unified NNUE training system
Shows both training-only mode and pipeline mode usage
"""

import os
import sys
from pathlib import Path

def show_example(title, description, command, note=""):
    """Display a formatted example"""
    print(f"\n{'='*60}")
    print(f"📚 {title}")
    print('='*60)
    print(f"Description: {description}")
    print(f"\nCommand:")
    print(f"  {command}")
    if note:
        print(f"\nNote: {note}")
    print()

def main():
    """Show examples of the unified training system"""
    
    print("🎯 NNUE Training System Examples")
    print("="*50)
    print("Simple, unified system with one script for everything:")
    print("• Training Mode: Train from existing data files")
    print("• Pipeline Mode: Complete data generation + training")
    
    # Training-Only Mode Examples
    print(f"\n{'🎓 TRAINING-ONLY MODE EXAMPLES':=^60}")
    
    show_example(
        "Basic Training with Configuration",
        "Train using a pre-configured setup with existing data",
        "python train_nnue.py --config configs/default.json --data training_data.txt",
        "Most recommended approach for regular training"
    )
    
    show_example(
        "Quick Experimentation",
        "Fast training for testing hyperparameters or debugging",
        "python train_nnue.py --config configs/fast.json --data training_data.txt",
        "Completes in 30-60 minutes"
    )
    
    show_example(
        "High-Quality Production Training",
        "Best quality training for production models",
        "python train_nnue.py --config configs/high_quality.json --data training_data.txt",
        "Takes 6-12 hours but produces best results"
    )
    
    show_example(
        "CPU-Only Training", 
        "Training on systems without GPU",
        "python train_nnue.py --config configs/cpu_only.json --data training_data.txt",
        "Optimized for CPU-only environments"
    )
    
    show_example(
        "Training with Parameter Overrides",
        "Use config as base but override specific parameters",
        "python train_nnue.py --config configs/default.json --data training_data.txt --epochs 500 --lr 0.001",
        "Config provides defaults, command line overrides specific values"
    )
    
    show_example(
        "Manual Training (No Config)",
        "Traditional command-line approach",
        "python train_nnue.py --data training_data.txt --epochs 300 --batch-size 8192 --lr 0.002 --plot",
        "Works exactly like the old train_nnue.py"
    )
    
    # Pipeline Mode Examples
    print(f"\n{'🚀 PIPELINE MODE EXAMPLES':=^60}")
    
    show_example(
        "Complete Pipeline with Configuration",
        "Full end-to-end training from data generation to model",
        "python train_nnue.py --config configs/pipeline.json --perfect-db /path/to/database",
        "Generates data, trains model, validates everything"
    )
    
    show_example(
        "Fast Pipeline for Testing",
        "Quick end-to-end validation of the entire workflow",
        "python train_nnue.py --config configs/pipeline_fast.json --perfect-db /path/to/database",
        "Completes in 1-2 hours including data generation"
    )
    
    show_example(
        "Pipeline with Parameter Overrides",
        "Use pipeline config but customize training parameters",
        "python train_nnue.py --config configs/pipeline.json --perfect-db /path/to/db --epochs 500 --threads 32",
        "Useful for adjusting to different hardware"
    )
    
    show_example(
        "Environment Validation Only",
        "Check if engine and database are properly set up",
        "python train_nnue.py --config configs/pipeline.json --perfect-db /path/to/db --validate-only",
        "Validates environment without starting training"
    )
    
    show_example(
        "Manual Pipeline (No Config)",
        "Traditional command-line pipeline approach",
        """python train_nnue.py \\
    --pipeline \\
    --engine ../../sanmill \\
    --perfect-db /path/to/database \\
    --positions 500000 \\
    --epochs 300 \\
    --plot""",
        "Equivalent to old train_pipeline_parallel.py"
    )
    
    # Configuration Examples
    print(f"\n{'⚙️ CONFIGURATION EXAMPLES':=^60}")
    
    show_example(
        "Generate Custom Configuration Template",
        "Create a template with all available options",
        "python train_nnue.py --save-config my_custom_config.json",
        "Edit the generated file to customize your training"
    )
    
    show_example(
        "List Available Configurations",
        "See what pre-made configurations are available",
        "ls configs/*.json",
        "Each config is optimized for different use cases"
    )
    
    # Simple Usage Summary
    print(f"\n{'📝 USAGE SUMMARY':=^60}")
    
    print("Training with existing data:")
    print("  python train_nnue.py --config configs/default.json --data training_data.txt")
    
    print("\nComplete pipeline (data generation + training):")
    print("  python train_nnue.py --config configs/pipeline.json --perfect-db /path/to/db")
    
    print("\nCustom parameters:")
    print("  python train_nnue.py --config configs/fast.json --data training_data.txt --epochs 500")
    
    # Best Practices
    print(f"\n{'💡 BEST PRACTICES':=^60}")
    
    practices = [
        "🎯 Use configuration files instead of long command lines",
        "🚀 Start with configs/fast.json for experimentation",
        "📊 Enable --plot to monitor training progress",
        "💾 Use --save-csv to export metrics for analysis",
        "🔧 Test with --validate-only before long training runs",
        "📁 Organize outputs with custom --output-dir",
        "⚡ Use pipeline mode for reproducible end-to-end workflows",
        "🎚️ Override specific parameters while keeping config defaults"
    ]
    
    for practice in practices:
        print(f"  {practice}")
    
    # Available Configurations Summary
    print(f"\n{'📁 AVAILABLE CONFIGURATIONS':=^60}")
    
    configs = [
        ("default.json", "General purpose training", "Training-only"),
        ("fast.json", "Quick experimentation", "Training-only"),
        ("high_quality.json", "Production models", "Training-only"),
        ("cpu_only.json", "CPU-only systems", "Training-only"),
        ("large_dataset.json", "Massive datasets", "Training-only"),
        ("debug.json", "Development/testing", "Training-only"),
        ("pipeline.json", "Complete pipeline", "Pipeline mode"),
        ("pipeline_fast.json", "Quick pipeline test", "Pipeline mode")
    ]
    
    for config, description, mode in configs:
        print(f"  📄 {config:20} - {description:25} [{mode}]")
    
    print(f"\n{'🎉 GET STARTED':=^60}")
    print("1. Choose your use case:")
    print("   • Have training data? Use training-only mode")
    print("   • Need complete workflow? Use pipeline mode")
    print()
    print("2. Pick a configuration:")
    print("   • Beginner: configs/fast.json")
    print("   • Regular use: configs/default.json") 
    print("   • Production: configs/high_quality.json")
    print()
    print("3. Run your command:")
    print("   python train_nnue.py --config configs/[chosen].json [additional args]")
    print()
    print("4. Monitor progress with built-in visualization!")
    
    return 0

if __name__ == "__main__":
    sys.exit(main())
