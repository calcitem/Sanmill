#!/usr/bin/env python3
"""
Move sequence validation tool for AlphaZero-generated games.

This tool validates move sequences from training logs or self-play to identify
illegal moves, particularly invalid capture moves that don't follow mill formation rules.
"""

import logging
import sys
import os
import re
from game.Game import Game
from game.engine_adapter import move_to_engine_token, engine_token_to_move

log = logging.getLogger(__name__)
logging.basicConfig(level=logging.INFO, format='%(asctime)s %(levelname)s %(message)s')


def validate_move_sequence(move_list_str, verbose=False):
    """
    Validate a space-separated move sequence string.
    
    Args:
        move_list_str: String like "c3 g7 a4 e4 ... f4-f2 xg7"
        verbose: Whether to print detailed validation info
        
    Returns:
        dict with validation results:
        {
            'is_valid': bool,
            'total_moves': int,
            'valid_moves': int,
            'first_invalid_move': str or None,
            'invalid_index': int or None,
            'error_message': str or None
        }
    """
    
    moves = move_list_str.strip().split()
    if not moves:
        return {
            'is_valid': False,
            'total_moves': 0,
            'valid_moves': 0,
            'first_invalid_move': None,
            'invalid_index': None,
            'error_message': 'Empty move list'
        }
    
    game = Game()
    board = game.getInitBoard()
    current_player = 1
    
    if verbose:
        log.info(f"Validating sequence with {len(moves)} moves...")
        log.info("Board before moves:")
        log.info(board.display_board())
    
    for i, move_token in enumerate(moves):
        if verbose:
            log.info(f"\nMove {i+1}: {move_token} (Player {current_player})")
            log.info(f"Period: {board.period}, Pieces: W={board.count(1)}, B={board.count(-1)}")
        
        try:
            # Convert engine token to Python move format
            py_move = engine_token_to_move(move_token)
            action = board.get_action_from_move(py_move)
            
            # Check if move is legal
            valids = game.getValidMoves(board, current_player)
            if valids[action] == 0:
                error_msg = f"Illegal move: {move_token} for player {current_player} in period {board.period}"
                
                # For capture moves, provide more specific error info
                if move_token.startswith('x'):
                    if board.period != 3:
                        error_msg += f" (not in capture phase, period={board.period})"
                    else:
                        error_msg += " (capture move not allowed at this position)"
                        
                return {
                    'is_valid': False,
                    'total_moves': len(moves),
                    'valid_moves': i,
                    'first_invalid_move': move_token,
                    'invalid_index': i,
                    'error_message': error_msg
                }
            
            # Execute the move
            board, current_player = game.getNextState(board, current_player, action)
            
            if verbose:
                log.info(f"After move - Period: {board.period}, Next player: {current_player}")
                
        except Exception as e:
            return {
                'is_valid': False,
                'total_moves': len(moves),
                'valid_moves': i,
                'first_invalid_move': move_token,
                'invalid_index': i,
                'error_message': f"Move parsing error: {e}"
            }
    
    if verbose:
        log.info(f"\n✓ All {len(moves)} moves are valid!")
        log.info("Final board:")
        log.info(board.display_board())
    
    return {
        'is_valid': True,
        'total_moves': len(moves),
        'valid_moves': len(moves),
        'first_invalid_move': None,
        'invalid_index': None,
        'error_message': None
    }


def validate_log_file(log_file_path, output_file=None):
    """
    Scan a training log file for move sequences and validate them.
    
    Args:
        log_file_path: Path to training log file
        output_file: Optional path to write validation results
    """
    
    log.info(f"Scanning log file: {log_file_path}")
    
    move_pattern = re.compile(r'Engine move list: (.+)')
    results = []
    total_sequences = 0
    invalid_sequences = 0
    
    try:
        with open(log_file_path, 'r', encoding='utf-8') as f:
            for line_num, line in enumerate(f, 1):
                match = move_pattern.search(line)
                if match:
                    total_sequences += 1
                    move_sequence = match.group(1).strip()
                    
                    result = validate_move_sequence(move_sequence, verbose=False)
                    result['line_number'] = line_num
                    result['sequence'] = move_sequence
                    
                    if not result['is_valid']:
                        invalid_sequences += 1
                        log.warning(f"Line {line_num}: Invalid sequence - {result['error_message']}")
                        log.warning(f"  Sequence: {move_sequence}")
                        log.warning(f"  First invalid move: {result['first_invalid_move']} at position {result['invalid_index'] + 1}")
                    
                    results.append(result)
                    
                    if total_sequences % 100 == 0:
                        log.info(f"Processed {total_sequences} sequences, {invalid_sequences} invalid")
    
    except Exception as e:
        log.error(f"Error reading log file: {e}")
        return
    
    log.info(f"\nValidation complete:")
    log.info(f"  Total sequences: {total_sequences}")
    log.info(f"  Valid sequences: {total_sequences - invalid_sequences}")
    log.info(f"  Invalid sequences: {invalid_sequences}")
    if total_sequences > 0:
        log.info(f"  Success rate: {(total_sequences - invalid_sequences) / total_sequences * 100:.1f}%")
    
    if output_file:
        log.info(f"Writing detailed results to: {output_file}")
        with open(output_file, 'w', encoding='utf-8') as f:
            f.write("Move Sequence Validation Results\n")
            f.write("=" * 50 + "\n\n")
            f.write(f"Total sequences: {total_sequences}\n")
            f.write(f"Valid sequences: {total_sequences - invalid_sequences}\n")
            f.write(f"Invalid sequences: {invalid_sequences}\n")
            f.write(f"Success rate: {(total_sequences - invalid_sequences) / total_sequences * 100:.1f}%\n\n")
            
            if invalid_sequences > 0:
                f.write("Invalid Sequences:\n")
                f.write("-" * 30 + "\n")
                for result in results:
                    if not result['is_valid']:
                        f.write(f"Line {result['line_number']}:\n")
                        f.write(f"  Error: {result['error_message']}\n")
                        f.write(f"  Invalid move: {result['first_invalid_move']} (position {result['invalid_index'] + 1})\n")
                        f.write(f"  Sequence: {result['sequence']}\n\n")


def main():
    """Main entry point for command-line usage."""
    if len(sys.argv) < 2:
        print("Usage:")
        print("  python validate_moves.py <move_sequence>")
        print("  python validate_moves.py --log-file <log_file_path> [--output <output_file>]")
        print("\nExamples:")
        print("  python validate_moves.py 'c3 g7 a4 e4 d2 a7 d7 f2 d5 c4 f4 g1 c5 a1 e5 xg7'")
        print("  python validate_moves.py --log-file train.log --output validation_results.txt")
        sys.exit(1)
    
    if sys.argv[1] == '--log-file':
        if len(sys.argv) < 3:
            print("Error: --log-file requires a file path")
            sys.exit(1)
        
        log_file = sys.argv[2]
        output_file = None
        
        if len(sys.argv) >= 5 and sys.argv[3] == '--output':
            output_file = sys.argv[4]
        
        validate_log_file(log_file, output_file)
    
    else:
        # Validate single sequence
        move_sequence = sys.argv[1]
        result = validate_move_sequence(move_sequence, verbose=True)
        
        if result['is_valid']:
            print(f"\n✓ Move sequence is VALID ({result['total_moves']} moves)")
        else:
            print(f"\n✗ Move sequence is INVALID")
            print(f"  Error: {result['error_message']}")
            print(f"  Failed at move {result['invalid_index'] + 1}: {result['first_invalid_move']}")
            print(f"  Valid moves: {result['valid_moves']}/{result['total_moves']}")


if __name__ == "__main__":
    main()
