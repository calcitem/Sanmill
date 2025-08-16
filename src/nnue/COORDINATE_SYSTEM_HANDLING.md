# NNUE Coordinate System Handling

## Overview
The NNUE system correctly handles the dual coordinate systems used by the main engine and perfect database while maintaining consistency for both internal training and external usage.

## Coordinate Systems

### 1. Main Engine Coordinate System
- **Range**: SQ_8 to SQ_31 (24 squares)
- **Usage**: All public APIs, position representation, move generation
- **Example**: SQ_8, SQ_9, ..., SQ_31

### 2. Perfect Database Coordinate System  
- **Range**: 0 to 23 (24 indices)
- **Usage**: Internal perfect database operations, symmetry transformations
- **Example**: 0, 1, 2, ..., 23

### 3. NNUE Feature Index System
- **Range**: 0 to 23 (24 indices) 
- **Usage**: Internal NNUE feature arrays
- **Mapping**: feature_index = engine_square - SQ_BEGIN

## Implementation Strategy

### 1. Feature Extraction (`nnue_features.cpp`)
```cpp
// Extract engine square from position
const Square sq = extract_lsb(pieces);

// Convert to NNUE feature index (0-23 range)
const int feature_idx = sq - SQ_BEGIN;

// Use feature index in NNUE feature array
features[FeatureIndices::WHITE_PIECES_START + feature_idx] = true;
```

**Key Points:**
- Input: Engine coordinates (SQ_8 to SQ_31)
- Internal: NNUE feature indices (0-23)
- Maintains engine coordinate semantics for external consistency

### 2. Symmetry Transformations (`nnue_symmetries.cpp`)
```cpp
// Convert feature index to engine square
const Square original_sq = static_cast<Square>(feature_idx + SQ_BEGIN);

// Apply transformation using perfect database coordinate system
const Square transformed_sq = transform_square(original_sq, op);

// Convert back to feature index
const int transformed_feature_idx = transformed_sq - SQ_BEGIN;
```

**Key Points:**
- Transforms engine squares using perfect database functions
- Perfect database coordinate conversion happens internally
- Feature arrays remain in engine coordinate semantics

### 3. Perfect Database Integration (`apply_perfect_transform`)
```cpp
static Square apply_perfect_transform(Square sq, int (*transform_func)(int)) {
    // Convert engine square to perfect database coordinate
    const int perfect_idx = to_perfect_square(sq);
    
    // Apply perfect database transformation
    const int input_bitboard = 1 << perfect_idx;
    const int output_bitboard = transform_func(input_bitboard);
    
    // Convert result back to engine coordinate
    for (int i = 0; i < 24; ++i) {
        if (output_bitboard & (1 << i)) {
            return from_perfect_square(i);
        }
    }
}
```

**Key Points:**
- Encapsulates perfect database coordinate conversion
- Input/output always in engine coordinates
- Internal transformation uses perfect database system

## Data Flow

### Training Phase
1. **Position Input**: Engine coordinates (SQ_8 to SQ_31)
2. **Feature Extraction**: Convert to NNUE indices (0-23)
3. **Symmetry Generation**: 
   - Convert indices back to engine coordinates
   - Apply perfect database transformations
   - Convert results back to indices
4. **Training Data**: Consistent NNUE feature format

### Evaluation Phase
1. **Position Input**: Engine coordinates (SQ_8 to SQ_31)
2. **Feature Extraction**: Convert to NNUE indices (0-23)
3. **Canonical Form**: Find optimal symmetry using perfect database
4. **Network Evaluation**: Process NNUE features
5. **Result Output**: Standard evaluation value

## Consistency Guarantees

### For Internal Training
- All symmetry transformations use proven perfect database algorithms
- Training data includes all valid symmetries
- Feature representations are mathematically consistent

### For External Usage
- All public APIs use engine coordinate system
- Position representations match main engine expectations
- Evaluation results integrate seamlessly with search

## Benefits

1. **Correctness**: Leverages proven perfect database symmetry logic
2. **Consistency**: Maintains engine coordinate semantics throughout
3. **Performance**: Efficient coordinate conversion only when needed
4. **Maintainability**: Clear separation between coordinate systems

## Testing

The coordinate system handling is verified through:

1. **Round-trip Tests**: Engine → Perfect → Engine conversions
2. **Symmetry Tests**: Four 90° rotations return to original
3. **Feature Tests**: Consistent feature extraction and transformation
4. **Integration Tests**: NNUE evaluation with real positions

## Example Usage

```cpp
// External API - uses engine coordinates
Position pos;
Value eval = g_nnue_evaluator.evaluate(pos);  // SQ_8 to SQ_31

// Internal feature extraction - converts to indices
bool features[115];
FeatureExtractor::extract_features(pos, features);  // indices 0-23

// Internal symmetry - uses perfect database transformations
SymmetryOp canonical = SymmetryAwareNNUE::find_canonical_symmetry(pos);

// Result - back to engine evaluation scale
return eval;  // Standard Value type
```

## Conclusion

The NNUE system successfully bridges the two coordinate systems:
- **Internal operations** leverage perfect database transformations for correctness
- **External interfaces** maintain engine coordinate consistency for integration
- **Training data** benefits from proven symmetry algorithms
- **Evaluation results** integrate seamlessly with the main engine

This design ensures that NNUE training uses the robust perfect database framework while presenting a consistent interface to the rest of the engine.
