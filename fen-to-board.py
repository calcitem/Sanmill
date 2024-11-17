# Define the initial board as a list of strings
original_board = [
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

# Build mappings between position names and their ring and index
positions_index = {}  # Map position name to (ring, index)
index_to_position = {}  # Map (ring, index) to position name

# Assign indices to positions in each ring
for idx, pos_name in enumerate(outer_ring_positions):
    ring = 3  # Outer ring
    index = idx
    positions_index[pos_name] = (ring, index)
    index_to_position[(ring, index)] = pos_name

for idx, pos_name in enumerate(middle_ring_positions):
    ring = 2  # Middle ring
    index = idx
    positions_index[pos_name] = (ring, index)
    index_to_position[(ring, index)] = pos_name

for idx, pos_name in enumerate(inner_ring_positions):
    ring = 1  # Inner ring
    index = idx
    positions_index[pos_name] = (ring, index)
    index_to_position[(ring, index)] = pos_name

# Function to parse the FEN string and build the board state
def parse_fen(fen_string):
    parts = fen_string.strip().split(' ', 1)
    positions_fen = parts[0]
    rest_of_fen = parts[1] if len(parts) > 1 else ''

    fen_parts = positions_fen.split('/')

    if len(fen_parts) != 3:
        raise ValueError("Invalid FEN string: expected 3 parts separated by '/'")

    inner_fen, middle_fen, outer_fen = fen_parts

    board_state = {}

    # Process inner ring
    for i, fen_char in enumerate(inner_fen):
        if fen_char != '*':
            pos_name = inner_ring_positions[i]
            board_state[pos_name] = fen_char

    # Process middle ring
    for i, fen_char in enumerate(middle_fen):
        if fen_char != '*':
            pos_name = middle_ring_positions[i]
            board_state[pos_name] = fen_char

    # Process outer ring
    for i, fen_char in enumerate(outer_fen):
        if fen_char != '*':
            pos_name = outer_ring_positions[i]
            board_state[pos_name] = fen_char

    return board_state, rest_of_fen

# Function to update the board display based on the board state
def update_board(board_state, board):
    for pos_name, piece in board_state.items():
        if pos_name in positions_coords:
            line_idx, col_idx = positions_coords[pos_name]
            # Replace the first character with a space and the second with the piece symbol
            line = list(board[line_idx])
            line[col_idx] = ' '
            line[col_idx + 1] = piece
            board[line_idx] = ''.join(line)

# Function to apply transformations to the board state
def apply_transformation(board_state, transformation):
    rotation_steps, flip_v, flip_h, flip_io = transformation
    transformed_board_state = {}

    for pos_name, piece in board_state.items():
        ring, index = positions_index[pos_name]

        # Apply inner/outer flip
        if flip_io:
            if ring == 1:
                ring = 3
            elif ring == 3:
                ring = 1
            # Middle ring remains the same

        # Apply vertical flip (reflection over horizontal axis)
        if flip_v:
            index = (8 - index) % 8

        # Apply horizontal flip (reflection over vertical axis)
        if flip_h:
            index = (4 - index) % 8

        # Apply rotation (in 45-degree increments)
        index = (index + rotation_steps) % 8

        # Map back to position name
        new_pos_name = index_to_position[(ring, index)]
        transformed_board_state[new_pos_name] = piece

    return transformed_board_state

# Function to transform a single position
def transform_position(pos_name, transformation):
    rotation_steps, flip_v, flip_h, flip_io = transformation
    if pos_name not in positions_index:
        raise ValueError(f"Invalid position name: {pos_name}")
    ring, index = positions_index[pos_name]

    # Apply inner/outer flip
    if flip_io:
        if ring == 1:
            ring = 3
        elif ring == 3:
            ring = 1
        # Middle ring remains the same

    # Apply vertical flip (reflection over horizontal axis)
    if flip_v:
        index = (8 - index) % 8

    # Apply horizontal flip (reflection over vertical axis)
    if flip_h:
        index = (4 - index) % 8

    # Apply rotation (in 45-degree increments)
    index = (index + rotation_steps) % 8

    # Map back to position name
    new_pos_name = index_to_position[(ring, index)]
    return new_pos_name

# Function to represent the board state in a canonical form for comparison
def board_state_to_canonical(board_state):
    items = sorted(board_state.items())
    return tuple(items)

# Function to generate the FEN string from the board state
def board_state_to_fen(board_state, rest_of_fen=''):
    # Inner ring
    inner_fen_list = []
    for pos_name in inner_ring_positions:
        piece = board_state.get(pos_name, '*')
        inner_fen_list.append(piece)
    inner_fen = ''.join(inner_fen_list)

    # Middle ring
    middle_fen_list = []
    for pos_name in middle_ring_positions:
        piece = board_state.get(pos_name, '*')
        middle_fen_list.append(piece)
    middle_fen = ''.join(middle_fen_list)

    # Outer ring
    outer_fen_list = []
    for pos_name in outer_ring_positions:
        piece = board_state.get(pos_name, '*')
        outer_fen_list.append(piece)
    outer_fen = ''.join(outer_fen_list)

    # Combine the FEN parts
    positions_fen = '/'.join([inner_fen, middle_fen, outer_fen])

    if rest_of_fen:
        fen_string = positions_fen + ' ' + rest_of_fen
    else:
        fen_string = positions_fen

    return fen_string

# Main code for processing user input
import re

# Read the multi-line input
print("Enter the input (end with an empty line):")
input_lines = []
while True:
    try:
        line = input()
        if not line.strip():
            break
        input_lines.append(line)
    except EOFError:
        break  # End of input

# Combine the lines into a single string
input_text = '\n'.join(input_lines)

# Pattern to match the FEN string inside quotes
fen_pattern = r'"([^"]+)"'

fen_match = re.search(fen_pattern, input_text)
if fen_match:
    fen_string = fen_match.group(1)
else:
    raise ValueError("FEN string not found in the input.")

# Pattern to match the positions inside <String>[ ... ]
positions_pattern = r'<String>\[\s*(.*?)\s*\]'
positions_match = re.search(positions_pattern, input_text, re.DOTALL)
if positions_match:
    positions_text = positions_match.group(1)
    # Now split the positions by commas
    positions_list = [pos.strip().strip('"') for pos in positions_text.split(',') if pos.strip()]
else:
    raise ValueError("Positions not found in the input.")

try:
    # Parse the FEN string to get the board state
    board_state, rest_of_fen = parse_fen(fen_string)

    # Prepare to generate transformations
    rotation_steps_list = [0, 2, 4, 6]  # Corresponds to 0°, 90°, 180°, 270°
    flip_v_options = [False, True]      # Vertical flip
    flip_h_options = [False, True]      # Horizontal flip
    flip_io_options = [False, True]     # Inner/outer flip

    from itertools import product

    # Generate all combinations of transformations
    transformations = list(product(rotation_steps_list, flip_v_options, flip_h_options, flip_io_options))

    unique_board_states = set()
    board_states_list = []

    # Apply each transformation and collect unique board states
    for transformation in transformations:
        transformed_board_state = apply_transformation(board_state, transformation)
        canonical_state = board_state_to_canonical(transformed_board_state)
        if canonical_state not in unique_board_states:
            unique_board_states.add(canonical_state)
            board_states_list.append((transformation, transformed_board_state))

    # Output the transformed boards
    print("  //////////////////////////////////////////////////////////////////////////////")
    print("")
    for idx, (transformation, transformed_board_state) in enumerate(board_states_list):
        rotation_steps, flip_v, flip_h, flip_io = transformation
        # Reset the board to the original state for each transformation
        board = original_board[:]
        update_board(transformed_board_state, board)
        # Print the board drawing
        print("  /*")
        for line in board[1:-1]:  # Skip the first and last line (the /* and */ comments)
            print(line)
        print("  */")
        # Transform the positions_list
        transformed_positions_list = [transform_position(pos, transformation) for pos in positions_list]
        # Generate the transformed FEN string
        transformed_fen_string = board_state_to_fen(transformed_board_state, rest_of_fen)
        # Output the Dart code snippet
        print(f'  "{transformed_fen_string}": <String>[')
        for pos in transformed_positions_list:
            print(f'    "{pos}",')
        print('  ],\n')
except Exception as e:
    print("Invalid input. Please provide a valid FEN string or positions.")
