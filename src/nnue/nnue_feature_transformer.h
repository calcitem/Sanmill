/*
  Stockfish, a UCI chess playing engine derived from Glaurung 2.1
  Copyright (C) 2004-2022 The Stockfish developers (see AUTHORS file)

  Stockfish is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  Stockfish is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

// A class that converts the input features of the NNUE evaluation function

#ifndef NNUE_FEATURE_TRANSFORMER_H_INCLUDED
#define NNUE_FEATURE_TRANSFORMER_H_INCLUDED

#include "nnue_common.h"
#include "nnue_architecture.h"
#include "../debug.h"  // for debugPrintf

#include <cstring> // std::memset()
#include <vector>

namespace Stockfish::Eval::NNUE {

  using BiasType       = std::int16_t;
  using WeightType     = std::int16_t;
  using PSQTWeightType = std::int32_t;
  // Helper: read tensor possibly encoded with COMPRESSED_LEB128, otherwise raw little-endian array
  template <typename IntType>
  inline bool read_array_maybe_compressed(std::istream& stream, IntType* out, std::size_t count) {
    static constexpr char kMagic[] = "COMPRESSED_LEB128";
    static constexpr std::size_t kMagicLen = sizeof(kMagic) - 1; // no terminating null in file

    // Remember current position and probe for magic header
    const std::streampos pos = stream.tellg();
    char header[kMagicLen];
    stream.read(header, static_cast<std::streamsize>(kMagicLen));
    const bool canProbe = static_cast<std::size_t>(stream.gcount()) == kMagicLen;
    const bool isCompressed = canProbe && std::memcmp(header, kMagic, kMagicLen) == 0;

    // Reset stream to the beginning of this tensor block
    stream.clear();
    stream.seekg(pos);

    if (!isCompressed) {
      // Raw little-endian array
      read_little_endian<IntType>(stream, out, count);
      return !stream.fail();
    }

    // Skip magic and read compressed byte-count
    stream.seekg(pos + static_cast<std::streamoff>(kMagicLen));
    const std::uint32_t byteLen = read_little_endian<std::uint32_t>(stream);
    std::vector<unsigned char> buf;
    buf.resize(byteLen);
    stream.read(reinterpret_cast<char*>(buf.data()), static_cast<std::streamsize>(byteLen));
    if (stream.fail()) return false;

    // Decode signed LEB128 into int32 then cast to target type
    std::size_t k = 0;
    for (std::size_t i = 0; i < count; ++i) {
      std::int32_t r = 0;
      int shift = 0;
      while (true) {
        if (k >= buf.size()) return false; // truncated
        const unsigned char byte = buf[k++];
        r |= static_cast<std::int32_t>(byte & 0x7F) << shift;
        shift += 7;
        if ((byte & 0x80) == 0) {
          // Sign extend if needed (top bit of last byte indicates negative)
          if (byte & 0x40)
            r |= ~((1 << shift) - 1);
          break;
        }
      }
      out[i] = static_cast<IntType>(r);
    }
    return true;
  }

  // If vector instructions are enabled, we update and refresh the
  // accumulator tile by tile such that each tile fits in the CPU's
  // vector registers.
  #define VECTOR

  static_assert(PSQTBuckets % 8 == 0,
    "Per feature PSQT values cannot be processed at granularity lower than 8 at a time.");

  #ifdef USE_AVX512
  typedef __m512i vec_t;
  typedef __m256i psqt_vec_t;
  #define vec_load(a) _mm512_load_si512(a)
  #define vec_store(a,b) _mm512_store_si512(a,b)
  #define vec_add_16(a,b) _mm512_add_epi16(a,b)
  #define vec_sub_16(a,b) _mm512_sub_epi16(a,b)
  #define vec_load_psqt(a) _mm256_load_si256(a)
  #define vec_store_psqt(a,b) _mm256_store_si256(a,b)
  #define vec_add_psqt_32(a,b) _mm256_add_epi32(a,b)
  #define vec_sub_psqt_32(a,b) _mm256_sub_epi32(a,b)
  #define vec_zero_psqt() _mm256_setzero_si256()
  #define NumRegistersSIMD 32

  #elif USE_AVX2
  typedef __m256i vec_t;
  typedef __m256i psqt_vec_t;
  #define vec_load(a) _mm256_load_si256(a)
  #define vec_store(a,b) _mm256_store_si256(a,b)
  #define vec_add_16(a,b) _mm256_add_epi16(a,b)
  #define vec_sub_16(a,b) _mm256_sub_epi16(a,b)
  #define vec_load_psqt(a) _mm256_load_si256(a)
  #define vec_store_psqt(a,b) _mm256_store_si256(a,b)
  #define vec_add_psqt_32(a,b) _mm256_add_epi32(a,b)
  #define vec_sub_psqt_32(a,b) _mm256_sub_epi32(a,b)
  #define vec_zero_psqt() _mm256_setzero_si256()
  #define NumRegistersSIMD 16

  #elif USE_SSE2
  typedef __m128i vec_t;
  typedef __m128i psqt_vec_t;
  #define vec_load(a) (*(a))
  #define vec_store(a,b) *(a)=(b)
  #define vec_add_16(a,b) _mm_add_epi16(a,b)
  #define vec_sub_16(a,b) _mm_sub_epi16(a,b)
  #define vec_load_psqt(a) (*(a))
  #define vec_store_psqt(a,b) *(a)=(b)
  #define vec_add_psqt_32(a,b) _mm_add_epi32(a,b)
  #define vec_sub_psqt_32(a,b) _mm_sub_epi32(a,b)
  #define vec_zero_psqt() _mm_setzero_si128()
  #define NumRegistersSIMD (Is64Bit ? 16 : 8)

  #elif USE_MMX
  typedef __m64 vec_t;
  typedef __m64 psqt_vec_t;
  #define vec_load(a) (*(a))
  #define vec_store(a,b) *(a)=(b)
  #define vec_add_16(a,b) _mm_add_pi16(a,b)
  #define vec_sub_16(a,b) _mm_sub_pi16(a,b)
  #define vec_load_psqt(a) (*(a))
  #define vec_store_psqt(a,b) *(a)=(b)
  #define vec_add_psqt_32(a,b) _mm_add_pi32(a,b)
  #define vec_sub_psqt_32(a,b) _mm_sub_pi32(a,b)
  #define vec_zero_psqt() _mm_setzero_si64()
  #define NumRegistersSIMD 8

  #elif USE_NEON
  typedef int16x8_t vec_t;
  typedef int32x4_t psqt_vec_t;
  #define vec_load(a) (*(a))
  #define vec_store(a,b) *(a)=(b)
  #define vec_add_16(a,b) vaddq_s16(a,b)
  #define vec_sub_16(a,b) vsubq_s16(a,b)
  #define vec_load_psqt(a) (*(a))
  #define vec_store_psqt(a,b) *(a)=(b)
  #define vec_add_psqt_32(a,b) vaddq_s32(a,b)
  #define vec_sub_psqt_32(a,b) vsubq_s32(a,b)
  #define vec_zero_psqt() psqt_vec_t{0}
  #define NumRegistersSIMD 16

  #else
  #undef VECTOR

  #endif


  #ifdef VECTOR

      // Compute optimal SIMD register count for feature transformer accumulation.

      // We use __m* types as template arguments, which causes GCC to emit warnings
      // about losing some attribute information. This is irrelevant to us as we
      // only take their size, so the following pragma are harmless.
      #pragma GCC diagnostic push
      #pragma GCC diagnostic ignored "-Wignored-attributes"

      template <typename SIMDRegisterType,
                typename LaneType,
                int      NumLanes,
                int      MaxRegisters>
      static constexpr int BestRegisterCount()
      {
          #define RegisterSize  sizeof(SIMDRegisterType)
          #define LaneSize      sizeof(LaneType)

          static_assert(RegisterSize >= LaneSize);
          static_assert(MaxRegisters <= NumRegistersSIMD);
          static_assert(MaxRegisters > 0);
          static_assert(NumRegistersSIMD > 0);
          static_assert(RegisterSize % LaneSize == 0);
          static_assert((NumLanes * LaneSize) % RegisterSize == 0);

          const int ideal = (NumLanes * LaneSize) / RegisterSize;
          if (ideal <= MaxRegisters)
            return ideal;

          // Look for the largest divisor of the ideal register count that is smaller than MaxRegisters
          for (int divisor = MaxRegisters; divisor > 1; --divisor)
            if (ideal % divisor == 0)
              return divisor;

          return 1;
      }

      static constexpr int NumRegs     = BestRegisterCount<vec_t, WeightType, TransformedFeatureDimensions, NumRegistersSIMD>();
      static constexpr int NumPsqtRegs = BestRegisterCount<psqt_vec_t, PSQTWeightType, PSQTBuckets, NumRegistersSIMD>();

      #pragma GCC diagnostic pop

  #endif



  // Input feature converter
  class FeatureTransformer {

   private:
    // Number of output dimensions for one side
    static constexpr IndexType HalfDimensions = TransformedFeatureDimensions;

    #ifdef VECTOR
    static constexpr IndexType TileHeight = NumRegs * sizeof(vec_t) / 2;
    static constexpr IndexType PsqtTileHeight = NumPsqtRegs * sizeof(psqt_vec_t) / 4;
    static_assert(HalfDimensions % TileHeight == 0, "TileHeight must divide HalfDimensions");
    static_assert(PSQTBuckets % PsqtTileHeight == 0, "PsqtTileHeight must divide PSQTBuckets");
    #endif

   public:
    // Output type
    using OutputType = TransformedFeatureType;

    // Number of input/output dimensions
    static constexpr IndexType InputDimensions = FeatureSet::Dimensions;
    static constexpr IndexType OutputDimensions = HalfDimensions * 2;

    // Size of forward propagation buffer
    static constexpr std::size_t BufferSize =
        OutputDimensions * sizeof(OutputType);

    // Hash value embedded in the evaluation file
    static constexpr std::uint32_t get_hash_value() {
      return FeatureSet::HashValue ^ OutputDimensions;
    }

    // Read network parameters
    bool read_parameters(std::istream& stream) {

      // Support both raw and LEB128-compressed tensors written by nnue-pytorch serializer
      if (!read_array_maybe_compressed<BiasType>(stream, biases, HalfDimensions)) return false;
      if (!read_array_maybe_compressed<WeightType>(stream, weights, HalfDimensions * FeatureSet::get_dimensions())) return false;
      if (!read_array_maybe_compressed<PSQTWeightType>(stream, psqtWeights, PSQTBuckets * FeatureSet::get_dimensions())) return false;

      return !stream.fail();
    }

    // Write network parameters
    bool write_parameters(std::ostream& stream) const {

      write_little_endian<BiasType      >(stream, biases     , HalfDimensions                  );
      write_little_endian<WeightType    >(stream, weights    , HalfDimensions * FeatureSet::get_dimensions());
      write_little_endian<PSQTWeightType>(stream, psqtWeights, PSQTBuckets    * FeatureSet::get_dimensions());

      return !stream.fail();
    }

    // Convert input features
    std::int32_t transform(const Position& pos, OutputType* output, int bucket) const {
      // Debug: Track transform function calls
      static thread_local int transformCallCount = 0;
      if (++transformCallCount <= 5) {
        debugPrintf("NNUE transform call #%d\n", transformCallCount);
      }
      
      // Validate position state before processing
      Color sideToMove = pos.side_to_move();
      if (sideToMove != WHITE && sideToMove != BLACK) {
        debugPrintf("ERROR: Invalid sideToMove %d in NNUE transform\n", static_cast<int>(sideToMove));
        sideToMove = WHITE;  // Default to WHITE
      }
      
      update_accumulator(pos, WHITE);
      update_accumulator(pos, BLACK);

      // Ensure perspectives are valid colors for NNUE
      Color perspective0 = (sideToMove == WHITE || sideToMove == BLACK) ? sideToMove : WHITE;
      Color perspective1 = (perspective0 == WHITE) ? BLACK : WHITE;
      
      // Map to NNUE array indices (0 and 1)
      const int nnueIndex0 = (perspective0 == WHITE) ? 0 : 1;
      const int nnueIndex1 = (perspective1 == WHITE) ? 0 : 1;
      const int nnueIndices[2] = {nnueIndex0, nnueIndex1};
      
      const auto& accumulation = pos.state()->accumulator.accumulation;
      const auto& psqtAccumulation = pos.state()->accumulator.psqtAccumulation;

      const auto psqt = (
            psqtAccumulation[nnueIndex0][bucket]
          - psqtAccumulation[nnueIndex1][bucket]
        ) / 2;


  #if defined(USE_AVX512)

      constexpr IndexType NumChunks = HalfDimensions / (SimdWidth * 2);
      static_assert(HalfDimensions % (SimdWidth * 2) == 0);
      const __m512i Control = _mm512_setr_epi64(0, 2, 4, 6, 1, 3, 5, 7);
      const __m512i Zero = _mm512_setzero_si512();

      for (IndexType p = 0; p < 2; ++p)
      {
          const IndexType offset = HalfDimensions * p;
          auto out = reinterpret_cast<__m512i*>(&output[offset]);
          for (IndexType j = 0; j < NumChunks; ++j)
          {
              __m512i sum0 = _mm512_load_si512(&reinterpret_cast<const __m512i*>
                                              (accumulation[nnueIndices[p]])[j * 2 + 0]);
              __m512i sum1 = _mm512_load_si512(&reinterpret_cast<const __m512i*>
                                              (accumulation[nnueIndices[p]])[j * 2 + 1]);

              _mm512_store_si512(&out[j], _mm512_permutexvar_epi64(Control,
                                 _mm512_max_epi8(_mm512_packs_epi16(sum0, sum1), Zero)));
          }
      }
      return psqt;

  #elif defined(USE_AVX2)

      constexpr IndexType NumChunks = HalfDimensions / SimdWidth;
      constexpr int Control = 0b11011000;
      const __m256i Zero = _mm256_setzero_si256();

      for (IndexType p = 0; p < 2; ++p)
      {
          const IndexType offset = HalfDimensions * p;
          auto out = reinterpret_cast<__m256i*>(&output[offset]);
          for (IndexType j = 0; j < NumChunks; ++j)
          {
              __m256i sum0 = _mm256_load_si256(&reinterpret_cast<const __m256i*>
                                              (accumulation[nnueIndices[p]])[j * 2 + 0]);
              __m256i sum1 = _mm256_load_si256(&reinterpret_cast<const __m256i*>
                                              (accumulation[nnueIndices[p]])[j * 2 + 1]);

              _mm256_store_si256(&out[j], _mm256_permute4x64_epi64(
                                 _mm256_max_epi8(_mm256_packs_epi16(sum0, sum1), Zero), Control));
          }
      }
      return psqt;

  #elif defined(USE_SSE2)

      #ifdef USE_SSE41
      constexpr IndexType NumChunks = HalfDimensions / SimdWidth;
      const __m128i Zero = _mm_setzero_si128();
      #else
      constexpr IndexType NumChunks = HalfDimensions / SimdWidth;
      const __m128i k0x80s = _mm_set1_epi8(-128);
      #endif

      for (IndexType p = 0; p < 2; ++p)
      {
          const IndexType offset = HalfDimensions * p;
          auto out = reinterpret_cast<__m128i*>(&output[offset]);
          for (IndexType j = 0; j < NumChunks; ++j)
          {
              __m128i sum0 = _mm_load_si128(&reinterpret_cast<const __m128i*>
                                           (accumulation[nnueIndices[p]])[j * 2 + 0]);
              __m128i sum1 = _mm_load_si128(&reinterpret_cast<const __m128i*>
                                           (accumulation[nnueIndices[p]])[j * 2 + 1]);
              const __m128i packedbytes = _mm_packs_epi16(sum0, sum1);

              #ifdef USE_SSE41
              _mm_store_si128(&out[j], _mm_max_epi8(packedbytes, Zero));
              #else
              _mm_store_si128(&out[j], _mm_subs_epi8(_mm_adds_epi8(packedbytes, k0x80s), k0x80s));
              #endif
          }
      }
      return psqt;

  #elif defined(USE_MMX)

      constexpr IndexType NumChunks = HalfDimensions / SimdWidth;
      const __m64 k0x80s = _mm_set1_pi8(-128);

      for (IndexType p = 0; p < 2; ++p)
      {
          const IndexType offset = HalfDimensions * p;
          auto out = reinterpret_cast<__m64*>(&output[offset]);
          for (IndexType j = 0; j < NumChunks; ++j)
          {
              __m64 sum0 = *(&reinterpret_cast<const __m64*>(accumulation[nnueIndices[p]])[j * 2 + 0]);
              __m64 sum1 = *(&reinterpret_cast<const __m64*>(accumulation[nnueIndices[p]])[j * 2 + 1]);
              const __m64 packedbytes = _mm_packs_pi16(sum0, sum1);
              out[j] = _mm_subs_pi8(_mm_adds_pi8(packedbytes, k0x80s), k0x80s);
          }
      }
      _mm_empty();
      return psqt;

  #elif defined(USE_NEON)

      constexpr IndexType NumChunks = HalfDimensions / (SimdWidth / 2);
      const int8x8_t Zero = {0};

      for (IndexType p = 0; p < 2; ++p)
      {
          const IndexType offset = HalfDimensions * p;
          const auto out = reinterpret_cast<int8x8_t*>(&output[offset]);
          for (IndexType j = 0; j < NumChunks; ++j)
          {
              int16x8_t sum = reinterpret_cast<const int16x8_t*>(accumulation[nnueIndices[p]])[j];
              out[j] = vmax_s8(vqmovn_s16(sum), Zero);
          }
      }
      return psqt;

  #else

      for (IndexType p = 0; p < 2; ++p)
      {
          const IndexType offset = HalfDimensions * p;
          for (IndexType j = 0; j < HalfDimensions; ++j)
          {
              BiasType sum = accumulation[nnueIndices[p]][j];
              output[offset + j] = static_cast<OutputType>(std::max<int>(0, std::min<int>(127, sum)));
          }
      }
      return psqt;

  #endif

   } // end of function transform()



   private:
    void update_accumulator(const Position& pos, const Color perspective) const {
      // Validate perspective - NNUE only supports WHITE(1) and BLACK(2) in Sanmill
      if (perspective != WHITE && perspective != BLACK) {
        debugPrintf("ERROR: Invalid NNUE perspective %d, skipping accumulator update\n", static_cast<int>(perspective));
        return;
      }
      
      // Map Sanmill Color values to NNUE array indices
      // Sanmill: WHITE=1, BLACK=2 -> NNUE: WHITE=0, BLACK=1
      const int nnuePerspective = (perspective == WHITE) ? 0 : 1;
      
      // We'll manually replace perspective with nnuePerspective in array accesses
      
      // Get state pointer for debugging
      StateInfo *currentState = pos.state();
      
      // Debug: Show initial state for first few calls
      static thread_local int callCount = 0;
      if (++callCount <= 5) {
        debugPrintf("NNUE call #%d: perspective=%d, computed[%d]=%s\n",
                   callCount, static_cast<int>(perspective), 
                   nnuePerspective, currentState->accumulator.computed[nnuePerspective] ? "true" : "false");
      }
      
      // Debug: track accumulator updates to detect infinite loops
      static thread_local int updateCount = 0;
      if (++updateCount % 50000 == 0) {
        debugPrintf("NNUE accumulator update count: %d (sanmill_perspective=%d, nnue_index=%d)\n", 
                   updateCount, static_cast<int>(perspective), nnuePerspective);
      }

      // The size must be enough to contain the largest possible update.
      // That might depend on the feature set and generally relies on the
      // feature set's update cost calculation to be correct and never
      // allow updates with more added/removed features than MaxActiveDimensions.
      using IndexList = ValueList<IndexType, FeatureSet::MaxActiveDimensions>;

  #ifdef VECTOR
      // Gcc-10.2 unnecessarily spills AVX2 registers if this array
      // is defined in the VECTOR code below, once in each branch
      vec_t acc[NumRegs];
      psqt_vec_t psqt[NumPsqtRegs];
  #endif

      // Look for a usable accumulator of an earlier position. We keep track
      // of the estimated gain in terms of features to be added/subtracted.
      StateInfo *st = pos.state(), *next = nullptr;
      int gain = FeatureSet::refresh_cost(pos);
      int chainDepth = 0;
      const int MAX_CHAIN_DEPTH = 64;  // Prevent infinite loops
      
      while (st->previous && !st->accumulator.computed[nnuePerspective] && chainDepth < MAX_CHAIN_DEPTH)
      {
        if (chainDepth < 5) {  // Print first 5 iterations to see what's happening
          debugPrintf("NNUE: Chain traversal depth=%d, computed[%d]=%s, st=%p, previous=%p\n", 
                     chainDepth, nnuePerspective, 
                     st->accumulator.computed[nnuePerspective] ? "true" : "false",
                     st, st->previous);
        }
        // This governs when a full feature refresh is needed and how many
        // updates are better than just one full refresh.
        if (   FeatureSet::requires_refresh(st, perspective, pos)
            || (gain -= FeatureSet::update_cost(st) + 1) < 0)
          break;
        next = st;
        st = st->previous;
        ++chainDepth;
      }
      
      if (chainDepth >= MAX_CHAIN_DEPTH) {
        debugPrintf("NNUE: Chain depth limit reached, forcing refresh\n");
        st = pos.state();  // Force refresh from current position
        next = nullptr;
      }

      if (st->accumulator.computed[nnuePerspective])
      {
        debugPrintf("NNUE: Accumulator already computed[%d]=true, next=%p\n", nnuePerspective, next);
        if (next == nullptr)
          return;

        // Update incrementally in two steps. First, we update the "next"
        // accumulator. Then, we update the current accumulator (pos.state()).

        // Gather all features to be updated.
        const Square ksq = SQ_A1; // Unused anchor for Nine Men's Morris
        IndexList removed[2], added[2];
        ValueListInserter<IndexType> removed_inserter0(removed[0]);
        ValueListInserter<IndexType> added_inserter0(added[0]);
        ValueListInserter<IndexType> removed_inserter1(removed[1]);
        ValueListInserter<IndexType> added_inserter1(added[1]);
        
        FeatureSet::append_changed_indices(
          ksq, next, perspective, removed_inserter0, added_inserter0, pos);
        for (StateInfo *st2 = pos.state(); st2 != next; st2 = st2->previous)
          FeatureSet::append_changed_indices(
            ksq, st2, perspective, removed_inserter1, added_inserter1, pos);

        // Mark the accumulators as computed.
        next->accumulator.computed[nnuePerspective] = true;
        pos.state()->accumulator.computed[nnuePerspective] = true;
        debugPrintf("NNUE: Set computed[%d]=true for incremental update (next=%p, current=%p)\n", 
                   nnuePerspective, next, pos.state());

        // Now update the accumulators listed in states_to_update[], where the last element is a sentinel.
        StateInfo *states_to_update[3] =
          { next, next == pos.state() ? nullptr : pos.state(), nullptr };
  #ifdef VECTOR
        for (IndexType j = 0; j < HalfDimensions / TileHeight; ++j)
        {
          // Load accumulator
          auto accTile = reinterpret_cast<vec_t*>(
            &st->accumulator.accumulation[nnuePerspective][j * TileHeight]);
          for (IndexType k = 0; k < NumRegs; ++k)
            acc[k] = vec_load(&accTile[k]);

          for (IndexType i = 0; states_to_update[i]; ++i)
          {
            // Difference calculation for the deactivated features
            for (const auto index : removed[i])
            {
              const IndexType offset = HalfDimensions * index + j * TileHeight;
              auto column = reinterpret_cast<const vec_t*>(&weights[offset]);
              for (IndexType k = 0; k < NumRegs; ++k)
                acc[k] = vec_sub_16(acc[k], column[k]);
            }

            // Difference calculation for the activated features
            for (const auto index : added[i])
            {
              const IndexType offset = HalfDimensions * index + j * TileHeight;
              auto column = reinterpret_cast<const vec_t*>(&weights[offset]);
              for (IndexType k = 0; k < NumRegs; ++k)
                acc[k] = vec_add_16(acc[k], column[k]);
            }

            // Store accumulator
            accTile = reinterpret_cast<vec_t*>(
              &states_to_update[i]->accumulator.accumulation[nnuePerspective][j * TileHeight]);
            for (IndexType k = 0; k < NumRegs; ++k)
              vec_store(&accTile[k], acc[k]);
          }
        }

        for (IndexType j = 0; j < PSQTBuckets / PsqtTileHeight; ++j)
        {
          // Load accumulator
          auto accTilePsqt = reinterpret_cast<psqt_vec_t*>(
            &st->accumulator.psqtAccumulation[nnuePerspective][j * PsqtTileHeight]);
          for (std::size_t k = 0; k < NumPsqtRegs; ++k)
            psqt[k] = vec_load_psqt(&accTilePsqt[k]);

          for (IndexType i = 0; states_to_update[i]; ++i)
          {
            // Difference calculation for the deactivated features
            for (const auto index : removed[i])
            {
              const IndexType offset = PSQTBuckets * index + j * PsqtTileHeight;
              auto columnPsqt = reinterpret_cast<const psqt_vec_t*>(&psqtWeights[offset]);
              for (std::size_t k = 0; k < NumPsqtRegs; ++k)
                psqt[k] = vec_sub_psqt_32(psqt[k], columnPsqt[k]);
            }

            // Difference calculation for the activated features
            for (const auto index : added[i])
            {
              const IndexType offset = PSQTBuckets * index + j * PsqtTileHeight;
              auto columnPsqt = reinterpret_cast<const psqt_vec_t*>(&psqtWeights[offset]);
              for (std::size_t k = 0; k < NumPsqtRegs; ++k)
                psqt[k] = vec_add_psqt_32(psqt[k], columnPsqt[k]);
            }

            // Store accumulator
            accTilePsqt = reinterpret_cast<psqt_vec_t*>(
              &states_to_update[i]->accumulator.psqtAccumulation[nnuePerspective][j * PsqtTileHeight]);
            for (std::size_t k = 0; k < NumPsqtRegs; ++k)
              vec_store_psqt(&accTilePsqt[k], psqt[k]);
          }
        }

  #else
        for (IndexType i = 0; states_to_update[i]; ++i)
        {
          std::memcpy(states_to_update[i]->accumulator.accumulation[nnuePerspective],
              st->accumulator.accumulation[nnuePerspective],
              HalfDimensions * sizeof(BiasType));

          for (std::size_t k = 0; k < PSQTBuckets; ++k)
            states_to_update[i]->accumulator.psqtAccumulation[nnuePerspective][k] = st->accumulator.psqtAccumulation[nnuePerspective][k];

          st = states_to_update[i];

          // Difference calculation for the deactivated features
          for (const auto index : removed[i])
          {
            const IndexType offset = HalfDimensions * index;

            for (IndexType j = 0; j < HalfDimensions; ++j)
              st->accumulator.accumulation[nnuePerspective][j] -= weights[offset + j];

            for (std::size_t k = 0; k < PSQTBuckets; ++k)
              st->accumulator.psqtAccumulation[nnuePerspective][k] -= psqtWeights[index * PSQTBuckets + k];
          }

          // Difference calculation for the activated features
          for (const auto index : added[i])
          {
            const IndexType offset = HalfDimensions * index;

            for (IndexType j = 0; j < HalfDimensions; ++j)
              st->accumulator.accumulation[nnuePerspective][j] += weights[offset + j];

            for (std::size_t k = 0; k < PSQTBuckets; ++k)
              st->accumulator.psqtAccumulation[nnuePerspective][k] += psqtWeights[index * PSQTBuckets + k];
          }
        }
  #endif
      }
      else
      {
        debugPrintf("NNUE: Starting full refresh for perspective=%d, nnuePerspective=%d\n", 
                   static_cast<int>(perspective), nnuePerspective);
        // Refresh the accumulator
        auto& accumulator = pos.state()->accumulator;
        accumulator.computed[nnuePerspective] = true;
        debugPrintf("NNUE: Set computed[%d]=true for full refresh (st=%p)\n", 
                   nnuePerspective, pos.state());
        IndexList active;
        ValueListInserter<IndexType> active_inserter(active);
        FeatureSet::append_active_indices(pos, perspective, active_inserter);

  #ifdef VECTOR
        for (IndexType j = 0; j < HalfDimensions / TileHeight; ++j)
        {
          auto biasesTile = reinterpret_cast<const vec_t*>(
              &biases[j * TileHeight]);
          for (IndexType k = 0; k < NumRegs; ++k)
            acc[k] = biasesTile[k];

          for (const auto index : active)
          {
            const IndexType offset = HalfDimensions * index + j * TileHeight;
            auto column = reinterpret_cast<const vec_t*>(&weights[offset]);

            for (unsigned k = 0; k < NumRegs; ++k)
              acc[k] = vec_add_16(acc[k], column[k]);
          }

          auto accTile = reinterpret_cast<vec_t*>(
              &accumulator.accumulation[nnuePerspective][j * TileHeight]);
          for (unsigned k = 0; k < NumRegs; k++)
            vec_store(&accTile[k], acc[k]);
        }

        for (IndexType j = 0; j < PSQTBuckets / PsqtTileHeight; ++j)
        {
          for (std::size_t k = 0; k < NumPsqtRegs; ++k)
            psqt[k] = vec_zero_psqt();

          for (const auto index : active)
          {
            const IndexType offset = PSQTBuckets * index + j * PsqtTileHeight;
            auto columnPsqt = reinterpret_cast<const psqt_vec_t*>(&psqtWeights[offset]);

            for (std::size_t k = 0; k < NumPsqtRegs; ++k)
              psqt[k] = vec_add_psqt_32(psqt[k], columnPsqt[k]);
          }

          auto accTilePsqt = reinterpret_cast<psqt_vec_t*>(
            &accumulator.psqtAccumulation[nnuePerspective][j * PsqtTileHeight]);
          for (std::size_t k = 0; k < NumPsqtRegs; ++k)
            vec_store_psqt(&accTilePsqt[k], psqt[k]);
        }

  #else
        std::memcpy(accumulator.accumulation[nnuePerspective], biases,
            HalfDimensions * sizeof(BiasType));

        for (std::size_t k = 0; k < PSQTBuckets; ++k)
          accumulator.psqtAccumulation[nnuePerspective][k] = 0;

        for (const auto index : active)
        {
          const IndexType offset = HalfDimensions * index;

          for (IndexType j = 0; j < HalfDimensions; ++j)
            accumulator.accumulation[nnuePerspective][j] += weights[offset + j];

          for (std::size_t k = 0; k < PSQTBuckets; ++k)
            accumulator.psqtAccumulation[nnuePerspective][k] += psqtWeights[index * PSQTBuckets + k];
        }
  #endif
      }

  #if defined(USE_MMX)
      _mm_empty();
  #endif
      
      // No need to undef since we didn't use macro
    }

    alignas(CacheLineSize) BiasType biases[HalfDimensions];
    alignas(CacheLineSize) WeightType weights[HalfDimensions * InputDimensions];
    alignas(CacheLineSize) PSQTWeightType psqtWeights[InputDimensions * PSQTBuckets];
  };

}  // namespace Stockfish::Eval::NNUE

#endif // #ifndef NNUE_FEATURE_TRANSFORMER_H_INCLUDED
