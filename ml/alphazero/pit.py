#!/usr/bin/env python3
"""
Universal pitting script for Nine Men's Morris AlphaZero.
Supports multiple game modes:
- Human vs AI (interactive)
- AI vs AI (evaluation)
- AI vs Perfect Database (strength assessment)
- Random/Greedy baselines

Usage:
  python3 pit.py                           # Human vs AI (default)
  python3 pit.py --mode ai-vs-ai           # AI vs AI
  python3 pit.py --mode ai-vs-perfect      # AI vs Perfect DB
  python3 pit.py --mode human-vs-perfect   # Human vs Perfect DB
  python3 pit.py --games 10 --mcts-sims 1000  # Custom settings
"""

import os
import sys
import argparse
import logging
import torch
import torch.multiprocessing as mp

from Arena import playGames
from MCTS import MCTS
from game.Game import Game
from game.Players import *
from game.pytorch.NNet import NNetWrapper as NNet
from utils import *

# Setup logging
logging.basicConfig(level=logging.INFO, format='%(message)s')
log = logging.getLogger(__name__)


def load_ai_player(game, args, checkpoint_dir='./temp', mcts_sims=500, cpuct=1.0):
    """Load an AI player from checkpoint."""
    nnet = NNet(game, args)
    
    # Auto-pick checkpoint: prefer accepted champion, fallback to best-epoch
    ckpt_file = 'best.pth.tar' if os.path.exists(os.path.join(checkpoint_dir, 'best.pth.tar')) else 'best_epoch.pth.tar'
    ckpt_path = os.path.join(checkpoint_dir, ckpt_file)
    
    try:
        nnet.load_checkpoint(checkpoint_dir, ckpt_file)
        log.info(f"✅ Loaded AI model: {ckpt_path}")
    except Exception as e:
        log.warning(f"⚠️  Failed to load checkpoint {ckpt_path}: {e}")
        log.warning("Using randomly initialized network")
    
    mcts_args = dotdict({'numMCTSSims': mcts_sims, 'cpuct': cpuct})
    return MCTS(game, nnet, mcts_args)


def load_perfect_player(db_path):
    """Load Perfect Database player."""
    try:
        from perfect_bot import PerfectTeacherPlayer
        player = PerfectTeacherPlayer(db_path)
        log.info(f"✅ Loaded Perfect DB: {db_path}")
        return player
    except ImportError:
        log.error("❌ perfect_bot module not found")
        sys.exit(1)
    except Exception as e:
        log.error(f"❌ Failed to load Perfect DB from {db_path}: {e}")
        sys.exit(1)


def main():
    parser = argparse.ArgumentParser(
        description='Universal pitting script for Nine Men\'s Morris',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Game Modes:
  human-vs-ai      Human player vs AI (interactive, default)
  ai-vs-ai         AI vs AI (evaluation)
  ai-vs-perfect    AI vs Perfect Database (strength assessment)
  human-vs-perfect Human vs Perfect Database (interactive)

Examples:
  python3 pit.py                                    # Human vs AI
  python3 pit.py --mode ai-vs-ai --games 20         # AI vs AI, 20 games
  python3 pit.py --mode ai-vs-perfect --games 50    # AI vs Perfect DB
  python3 pit.py --mcts-sims 1000 --difficulty 0.8  # Strong AI
        """
    )
    
    parser.add_argument('--mode', choices=['human-vs-ai', 'ai-vs-ai', 'ai-vs-perfect', 'human-vs-perfect'],
                        default='human-vs-ai', help='Game mode (default: human-vs-ai)')
    parser.add_argument('--games', type=int, default=2,
                        help='Number of games to play (default: 2)')
    parser.add_argument('--mcts-sims', type=int, default=500,
                        help='MCTS simulations per move for AI (default: 500)')
    parser.add_argument('--difficulty', type=float, default=0.5,
                        help='Human player difficulty adjustment [-1,1] (default: 0.5)')
    parser.add_argument('--checkpoint', type=str, default='./temp',
                        help='Checkpoint directory (default: ./temp)')
    parser.add_argument('--perfect-db', type=str, default=None,
                        help='Perfect database path (overrides SANMILL_PERFECT_DB env)')
    parser.add_argument('--cpu', action='store_true',
                        help='Force CPU mode (disable CUDA)')
    parser.add_argument('--gui', action='store_true',
                        help='Enable simple GUI for human input (mouse clicks)')
    parser.add_argument('--first', choices=['human', 'ai'], default='human',
                        help='Who plays first in human-vs-ai mode (default: human)')
    
    args = parser.parse_args()
    
    # Initialize game and base config
    game = Game()
    base_args = dotdict({
        'lr': 0.002,
        'dropout': 0.3,
        'epochs': 10,
        'batch_size': 1024,
        'cuda': torch.cuda.is_available() and not args.cpu,
        'num_channels': 256,
        'num_processes': 1,  # Single process for pitting
    })
    
    log.info(f"🎮 Game Mode: {args.mode}")
    log.info(f"🎯 Games: {args.games}, MCTS Sims: {args.mcts_sims}")
    
    # Setup multiprocessing if needed
    if base_args.num_processes > 1:
        mp.set_start_method('spawn')
    
    # Initialize players based on mode
    if args.mode == 'human-vs-ai':
        # Create human and AI players first
        if args.gui:
            try:
                from gui_human import GuiHumanPlayer
                human_player = GuiHumanPlayer(game, difficulty=args.difficulty)
                log.info("🖱️  GUI enabled for human input")
            except Exception as e:
                log.warning(f"⚠️  GUI unavailable ({e}), falling back to console input")
                human_player = HumanPlayer(game, args.difficulty)
        else:
            human_player = HumanPlayer(game, args.difficulty)
        ai_player = load_ai_player(game, base_args, args.checkpoint, args.mcts_sims)

        # Assign order based on --first
        if args.first == 'human':
            log.info("👤 Player 1: Human")
            log.info("🤖 Player 2: AI")
            player1, player2 = human_player, ai_player
        else:
            log.info("🤖 Player 1: AI")
            log.info("👤 Player 2: Human")
            player1, player2 = ai_player, human_player

        # 如果启用 GUI，给 GUI 传递双方角色（便于状态栏显示）
        try:
            white_role = 'Human' if args.first == 'human' else 'AI'
            black_role = 'AI' if args.first == 'human' else 'Human'
            if hasattr(player1, 'set_roles'):
                player1.set_roles(white_role, black_role)
            if hasattr(player2, 'set_roles'):
                player2.set_roles(white_role, black_role)
        except Exception:
            pass
        
    elif args.mode == 'ai-vs-ai':
        log.info("🤖 Player 1: AI (Strong)")
        log.info("🤖 Player 2: AI (Weak)")
        player1 = load_ai_player(game, base_args, args.checkpoint, args.mcts_sims, cpuct=1.0)
        player2 = load_ai_player(game, base_args, args.checkpoint, args.mcts_sims//2, cpuct=1.5)
        
    elif args.mode == 'ai-vs-perfect':
        log.info("🤖 Player 1: AI")
        log.info("⭐ Player 2: Perfect Database")
        perfect_db = args.perfect_db or os.environ.get('SANMILL_PERFECT_DB')
        if not perfect_db:
            log.error("❌ Perfect database path required. Use --perfect-db or set SANMILL_PERFECT_DB env var")
            sys.exit(1)
        player1 = load_ai_player(game, base_args, args.checkpoint, args.mcts_sims)
        player2 = load_perfect_player(perfect_db)
        
    elif args.mode == 'human-vs-perfect':
        log.info("👤 Player 1: Human")
        log.info("⭐ Player 2: Perfect Database")
        perfect_db = args.perfect_db or os.environ.get('SANMILL_PERFECT_DB')
        if not perfect_db:
            log.error("❌ Perfect database path required. Use --perfect-db or set SANMILL_PERFECT_DB env var")
            sys.exit(1)
        if args.gui:
            try:
                from gui_human import GuiHumanPlayer
                player1 = GuiHumanPlayer(game, difficulty=args.difficulty)
                log.info("🖱️  GUI enabled for human input")
            except Exception as e:
                log.warning(f"⚠️  GUI unavailable ({e}), falling back to console input")
                player1 = HumanPlayer(game, args.difficulty)
        else:
            player1 = HumanPlayer(game, args.difficulty)
        player2 = load_perfect_player(perfect_db)
    
    # Play games
    log.info("🚀 Starting games...")
    arena_args = [player1, player2, game, game.display if 'human' in args.mode else None]
    
    try:
        wins1, wins2, draws = playGames(arena_args, args.games, 
                                       verbose='human' in args.mode, 
                                       num_processes=0)  # Single process for stability
        
        # Display results
        log.info("\n" + "="*50)
        log.info("🏆 GAME RESULTS")
        log.info("="*50)
        
        if args.mode == 'human-vs-ai':
            # Map results to human/AI depending on who was Player 1
            if args.first == 'human':
                human_wins, ai_wins = wins1, wins2
            else:
                human_wins, ai_wins = wins2, wins1
            log.info(f"👤 Human wins: {human_wins}")
            log.info(f"🤖 AI wins: {ai_wins}")
            log.info(f"🤝 Draws: {draws}")
            
        elif args.mode == 'ai-vs-ai':
            log.info(f"🤖 AI-1 (Strong) wins: {wins1}")
            log.info(f"🤖 AI-2 (Weak) wins: {wins2}")
            log.info(f"🤝 Draws: {draws}")
            
        elif args.mode == 'ai-vs-perfect':
            total_games = wins1 + wins2 + draws
            draw_rate = draws / total_games if total_games > 0 else 0
            log.info(f"🤖 AI wins: {wins1} (should be 0 against perfect play)")
            log.info(f"⭐ Perfect DB wins: {wins2}")
            log.info(f"🤝 Draws: {draws}")
            log.info(f"📊 Draw rate: {draw_rate:.1%} (higher = stronger AI)")
            
        elif args.mode == 'human-vs-perfect':
            total_games = wins1 + wins2 + draws
            draw_rate = draws / total_games if total_games > 0 else 0
            log.info(f"👤 Human wins: {wins1} (should be 0 against perfect play)")
            log.info(f"⭐ Perfect DB wins: {wins2}")
            log.info(f"🤝 Draws: {draws}")
            log.info(f"📊 Draw rate: {draw_rate:.1%}")
        
        log.info("="*50)
        
    except KeyboardInterrupt:
        log.info("\n⏹️  Games interrupted by user")
    except Exception as e:
        log.error(f"❌ Error during games: {e}")
        sys.exit(1)
    finally:
        # Cleanup Perfect DB if used
        if 'perfect' in args.mode and hasattr(player2, 'engine'):
            try:
                player2.engine.stop()
            except Exception:
                pass


if __name__ == '__main__':
    main()
