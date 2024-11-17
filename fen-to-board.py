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
    positions_fen = fen_string.split(' ')[0]
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

    return board_state

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

# Function to represent the board state in a canonical form for comparison
def board_state_to_canonical(board_state):
    items = sorted(board_state.items())
    return tuple(items)

# Main loop for processing user input
while True:
    # Read the FEN string from input
    fen_string = input("Enter FEN string (or 'q'/'quit' to exit): ").strip()

    # Check if the user wants to quit
    if fen_string.lower() in ['q', 'quit']:
        print("Exiting the program.")
        break

    try:
        # Parse the FEN string to get the board state
        board_state = parse_fen(fen_string)

        # Reset the board to the original state
        board = original_board[:]

        # Update the board with the initial state and print it
        update_board(board_state, board)
        print("Original Board:")
        for line in board:
            print(line)

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
        for idx, (transformation, transformed_board_state) in enumerate(board_states_list):
            rotation_steps, flip_v, flip_h, flip_io = transformation
            # Reset the board to the original state for each transformation
            board = original_board[:]
            update_board(transformed_board_state, board)
            print(f"\nTransformed Board {idx + 1}:")
            print(f"Rotation steps: {rotation_steps * 45}°, Vertical flip: {flip_v}, Horizontal flip: {flip_h}, Inner/Outer flip: {flip_io}")
            for line in board:
                print(line)
    except Exception as e:
        print("Invalid input. Please provide a valid FEN string.")
