# Define the initial board as a list of strings
board = [
    "  /*",
    "    a7 ----- d7 ----- g7",
    "    |         |        |",
    "    |  b6 -- d6 -- f6  |",
    "    |  |      |     |  |",
    "    |  |  c5-d5-e5  |  |",
    "    a4-b4-c4    e4-f4-g4",
    "    |  |  c3-d3-e3  |  |",
    "    |  |      |     |  |",
    "    |  b2 -- d2 -- f2  |",
    "    |         |        |",
    "    a1 ----- d1 ----- g1",
    "  */",
]

# Map positions to their coordinates (line index, column index)
positions_coords = {
    # Outer ring positions
    'a7': (1, 4), 'd7': (1, 13), 'g7': (1, 22),
    'a4': (6, 4), 'g4': (6, 22),
    'a1': (11, 4), 'd1': (11, 13), 'g1': (11, 22),
    # Middle ring positions
    'b6': (3, 7), 'd6': (3, 13), 'f6': (3, 19),
    'b4': (6, 7), 'f4': (6, 19),
    'b2': (9, 7), 'd2': (9, 13), 'f2': (9, 19),
    # Inner ring positions
    'c5': (5, 10), 'd5': (5, 13), 'e5': (5, 16),
    'c4': (6, 10), 'e4': (6, 16),
    'c3': (7, 10), 'd3': (7, 13), 'e3': (7, 16),
}

# Positions in the order they appear in the FEN string
inner_ring_positions = ['d5', 'e5', 'e4', 'e3', 'd3', 'c3', 'c4', 'c5']
middle_ring_positions = ['d6', 'f6', 'f4', 'f2', 'd2', 'b2', 'b4', 'b6']
outer_ring_positions = ['d7', 'g7', 'g4', 'g1', 'd1', 'a1', 'a4', 'a7']

# Read the FEN string from input
fen_string = input().strip()

# Split the FEN string into parts
positions_fen = fen_string.split(' ')[0]
fen_parts = positions_fen.split('/')

# Extract FEN strings for each ring
inner_fen = fen_parts[0]
middle_fen = fen_parts[1]
outer_fen = fen_parts[2]

# Function to update the board
def update_board(fen, positions):
    for i in range(8):
        fen_char = fen[i]
        if fen_char != '*':
            pos = positions[i]
            line_idx, col_idx = positions_coords[pos]
            # Replace the first character with a space and the second with the piece symbol
            line = list(board[line_idx])
            line[col_idx] = ' '
            line[col_idx + 1] = fen_char
            board[line_idx] = ''.join(line)

# Update the board for each ring
update_board(inner_fen, inner_ring_positions)
update_board(middle_fen, middle_ring_positions)
update_board(outer_fen, outer_ring_positions)

# Print the modified board
for line in board:
    print(line)

