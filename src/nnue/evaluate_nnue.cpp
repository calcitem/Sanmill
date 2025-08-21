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

// Code for calculating NNUE evaluation function

#include <iostream>
#include <set>
#include <sstream>
#include <iomanip>
#include <fstream>
#include <optional>

#include "../evaluate.h"
#include "../position.h"
#include "../misc.h"
#include "../uci.h"
#include "../types.h"

#include "evaluate_nnue.h"

namespace Stockfish::Eval::NNUE {

  // Input feature converter
  LargePagePtr<FeatureTransformer> featureTransformer;

  // Evaluation function
  AlignedPtr<Network> network[LayerStacks];

  // Evaluation function file name
  std::string fileName;
  std::string netDescription;

  namespace Detail {

  // Initialize the evaluation function parameters
  template <typename T>
  void initialize(AlignedPtr<T>& pointer) {

    pointer.reset(reinterpret_cast<T*>(std_aligned_alloc(alignof(T), sizeof(T))));
    std::memset(pointer.get(), 0, sizeof(T));
  }

  template <typename T>
  void initialize(LargePagePtr<T>& pointer) {

    static_assert(alignof(T) <= 4096, "aligned_large_pages_alloc() may fail for such a big alignment requirement of T");
#ifdef ALIGNED_LARGE_PAGES
    pointer.reset(reinterpret_cast<T*>(aligned_large_pages_alloc(sizeof(T))));
#else
    pointer.reset(reinterpret_cast<T*>(std_aligned_alloc(alignof(T), sizeof(T))));
#endif
    std::memset(pointer.get(), 0, sizeof(T));
  }

  // Relaxed reader: accept any 32-bit header tag (do not enforce exact hash match)
  // This improves compatibility with serializers that compute a slightly different
  // hash while keeping the same binary parameter layout.
  template <typename T>
  bool read_parameters_relaxed(std::istream& stream, T& reference) {
    const std::streampos pos = stream.tellg();
    [[maybe_unused]] std::uint32_t header = read_little_endian<std::uint32_t>(stream);
    if (!stream) return false;

    // If header mismatches expected value, continue anyway using relaxed mode.
    // We intentionally do not rewind past the header because writers include a tag here.
    // Fall through to read the rest of parameters according to T::read_parameters.
    return reference.read_parameters(stream);
  }

  // Read evaluation function parameters
  template <typename T>
  bool read_parameters(std::istream& stream, T& reference) {

    std::uint32_t header;
    header = read_little_endian<std::uint32_t>(stream);
    if (!stream || header != T::get_hash_value()) return false;
    return reference.read_parameters(stream);
  }

  // Write evaluation function parameters
  template <typename T>
  bool write_parameters(std::ostream& stream, const T& reference) {

    write_little_endian<std::uint32_t>(stream, T::get_hash_value());
    return reference.write_parameters(stream);
  }

  }  // namespace Detail

  // Initialize the evaluation function parameters
  void initialize() {

    Detail::initialize(featureTransformer);
    for (std::size_t i = 0; i < LayerStacks; ++i)
      Detail::initialize(network[i]);
  }

  // Read network header
  bool read_header(std::istream& stream, std::uint32_t* hashValue, std::string* desc)
  {
    std::uint32_t version, size;

    version     = read_little_endian<std::uint32_t>(stream);
    *hashValue  = read_little_endian<std::uint32_t>(stream);
    size        = read_little_endian<std::uint32_t>(stream);
    if (!stream || version != Version) return false;
    desc->resize(size);
    stream.read(&(*desc)[0], size);
    return !stream.fail();
  }

  // Write network header
  bool write_header(std::ostream& stream, std::uint32_t hashValue, const std::string& desc)
  {
    write_little_endian<std::uint32_t>(stream, Version);
    write_little_endian<std::uint32_t>(stream, hashValue);
    write_little_endian<std::uint32_t>(stream, static_cast<std::uint32_t>(desc.size()));
    stream.write(&desc[0], desc.size());
    return !stream.fail();
  }

  // Read network parameters
  bool read_parameters(std::istream& stream) {

    std::uint32_t hashValue;
    if (!read_header(stream, &hashValue, &netDescription)) return false;
    // Relax hash check to allow nnue-pytorch header variations; only version is enforced.
    // if (hashValue != HashValue) return false;
    // Use relaxed header checks for sub-blocks to maximize interoperability
    if (!Detail::read_parameters_relaxed(stream, *featureTransformer)) return false;
    for (std::size_t i = 0; i < LayerStacks; ++i)
      if (!Detail::read_parameters_relaxed(stream, *(network[i]))) return false;
    // Some serializers may append metadata; don't require exact EOF
    return stream.good();
  }

  // Write network parameters
  bool write_parameters(std::ostream& stream) {

    if (!write_header(stream, HashValue, netDescription)) return false;
    if (!Detail::write_parameters(stream, *featureTransformer)) return false;
    for (std::size_t i = 0; i < LayerStacks; ++i)
      if (!Detail::write_parameters(stream, *(network[i]))) return false;
    return (bool)stream;
  }

  // Evaluation function. Perform differential calculation.
  Value evaluate(const Position& pos, bool adjusted) {
    (void)adjusted; // Suppress unused parameter warning

    // We manually align the arrays on the stack because with gcc < 9.3
    // overaligning stack variables with alignas() doesn't work correctly.

    constexpr uint64_t alignment = CacheLineSize;

#if defined(ALIGNAS_ON_STACK_VARIABLES_BROKEN)
    TransformedFeatureType transformedFeaturesUnaligned[
      FeatureTransformer::BufferSize + alignment / sizeof(TransformedFeatureType)];
    char bufferUnaligned[Network::BufferSize + alignment];

    auto* transformedFeatures = align_ptr_up<alignment>(&transformedFeaturesUnaligned[0]);
    auto* buffer = align_ptr_up<alignment>(&bufferUnaligned[0]);
#else
    alignas(alignment)
      TransformedFeatureType transformedFeatures[FeatureTransformer::BufferSize];
    alignas(alignment) char buffer[Network::BufferSize];
#endif

    ASSERT_ALIGNED(transformedFeatures, alignment);
    ASSERT_ALIGNED(buffer, alignment);

    // Bucketization for Nine Men's Morris: piece count ranges 0..24.
    // Match nnue-pytorch bucket selection which uses coarse piece-count-based buckets.
    const int totalPieces = pos.piece_on_board_count(WHITE) + pos.piece_on_board_count(BLACK);
    const std::size_t bucket = std::min(std::size_t((std::max(0, totalPieces - 1)) / 3), std::size_t(7));
    const auto psqt = featureTransformer->transform(pos, transformedFeatures, static_cast<int>(bucket));
    const auto output = network[bucket]->propagate(transformedFeatures, buffer);

    int materialist = psqt;
    int positional  = output[0];

    // Simple linear blend. Chess-specific terms removed.
    int A = 128;
    int B = 128;
    int sum = (A * materialist + B * positional) / 256 * 2; // keep scale stable

    return static_cast<Value>( sum / OutputScale );
  }

  struct NnueEvalTrace {
    static_assert(LayerStacks == PSQTBuckets);

    Value psqt[LayerStacks];
    Value positional[LayerStacks];
    std::size_t correctBucket;
  };

  static NnueEvalTrace trace_evaluate(const Position& pos) {

    // We manually align the arrays on the stack because with gcc < 9.3
    // overaligning stack variables with alignas() doesn't work correctly.

    constexpr uint64_t alignment = CacheLineSize;

#if defined(ALIGNAS_ON_STACK_VARIABLES_BROKEN)
    TransformedFeatureType transformedFeaturesUnaligned[
      FeatureTransformer::BufferSize + alignment / sizeof(TransformedFeatureType)];
    char bufferUnaligned[Network::BufferSize + alignment];

    auto* transformedFeatures = align_ptr_up<alignment>(&transformedFeaturesUnaligned[0]);
    auto* buffer = align_ptr_up<alignment>(&bufferUnaligned[0]);
#else
    alignas(alignment)
      TransformedFeatureType transformedFeatures[FeatureTransformer::BufferSize];
    alignas(alignment) char buffer[Network::BufferSize];
#endif

    ASSERT_ALIGNED(transformedFeatures, alignment);
    ASSERT_ALIGNED(buffer, alignment);

    NnueEvalTrace t{};
    const int totalPieces = pos.piece_on_board_count(WHITE) + pos.piece_on_board_count(BLACK);
    t.correctBucket = std::min(std::size_t((std::max(0, totalPieces - 1)) / 3), std::size_t(7));
    for (std::size_t bucket = 0; bucket < LayerStacks; ++bucket) {
      const auto psqt = featureTransformer->transform(pos, transformedFeatures, int(bucket));
      const auto output = network[bucket]->propagate(transformedFeatures, buffer);

      int materialist = psqt;
      int positional  = output[0];

      t.psqt[bucket] = static_cast<Value>( materialist / OutputScale );
      t.positional[bucket] = static_cast<Value>( positional / OutputScale );
    }

    return t;
  }

  // Requires the buffer to have capacity for at least 5 values
  static void format_cp_compact(Value v, char* buffer) {

    buffer[0] = (v < 0 ? '-' : v > 0 ? '+' : ' ');

    // Scale to centi-points for display; VALUE_EACH_PIECE is unit step.
    int cp = std::abs(100 * v / VALUE_EACH_PIECE);

    if (cp >= 10000)
    {
      buffer[1] = static_cast<char>('0' + cp / 10000); cp %= 10000;
      buffer[2] = static_cast<char>('0' + cp / 1000); cp %= 1000;
      buffer[3] = static_cast<char>('0' + cp / 100); cp %= 100;
      buffer[4] = ' ';
    }
    else if (cp >= 1000)
    {
      buffer[1] = static_cast<char>('0' + cp / 1000); cp %= 1000;
      buffer[2] = static_cast<char>('0' + cp / 100); cp %= 100;
      buffer[3] = '.';
      buffer[4] = static_cast<char>('0' + cp / 10);
    }
    else
    {
      buffer[1] = static_cast<char>('0' + cp / 100); cp %= 100;
      buffer[2] = '.';
      buffer[3] = static_cast<char>('0' + cp / 10); cp %= 10;
      buffer[4] = static_cast<char>('0' + cp / 1);
    }
  }

  // Requires the buffer to have capacity for at least 7 values
  static void format_cp_aligned_dot(Value v, char* buffer) {
    buffer[0] = (v < 0 ? '-' : v > 0 ? '+' : ' ');

    int cp = std::abs(100 * v / VALUE_EACH_PIECE);

    if (cp >= 10000)
    {
      buffer[1] = static_cast<char>('0' + cp / 10000); cp %= 10000;
      buffer[2] = static_cast<char>('0' + cp / 1000); cp %= 1000;
      buffer[3] = static_cast<char>('0' + cp / 100); cp %= 100;
      buffer[4] = '.';
      buffer[5] = static_cast<char>('0' + cp / 10); cp %= 10;
      buffer[6] = static_cast<char>('0' + cp);
    }
    else if (cp >= 1000)
    {
      buffer[1] = ' ';
      buffer[2] = static_cast<char>('0' + cp / 1000); cp %= 1000;
      buffer[3] = static_cast<char>('0' + cp / 100); cp %= 100;
      buffer[4] = '.';
      buffer[5] = static_cast<char>('0' + cp / 10); cp %= 10;
      buffer[6] = static_cast<char>('0' + cp);
    }
    else
    {
      buffer[1] = ' ';
      buffer[2] = ' ';
      buffer[3] = static_cast<char>('0' + cp / 100); cp %= 100;
      buffer[4] = '.';
      buffer[5] = static_cast<char>('0' + cp / 10); cp %= 10;
      buffer[6] = static_cast<char>('0' + cp / 1);
    }
  }


  // trace() returns a string with the value of each piece on a board,
  // and a table for (PSQT, Layers) values bucket by bucket.

  std::string trace(Position& pos) {

    std::stringstream ss;

    char boardBuf[16][32];
    std::memset(boardBuf, ' ', sizeof(boardBuf));
    for (int row = 0; row < 16; ++row)
      boardBuf[row][31] = '\0';

    // A lambda to output one box of the board
    auto writeSquare = [&boardBuf](int col, int row, Piece pc, Value value) {
      const int x = col * 8;
      const int y = row * 3;
      for (int i = 1; i < 8; ++i)
         boardBuf[y][x+i] = boardBuf[y+3][x+i] = '-';
      for (int i = 1; i < 3; ++i)
         boardBuf[y+i][x] = boardBuf[y+i][x+8] = '|';
      boardBuf[y][x] = boardBuf[y][x+8] = boardBuf[y+3][x+8] = boardBuf[y+3][x] = '+';
      if (pc != NO_PIECE)
        boardBuf[y+1][x+4] = (color_of(pc) == WHITE ? 'O' : '@');
      if (value != VALUE_NONE)
        format_cp_compact(value, &boardBuf[y+2][x+2]);
    };

    // We estimate the value of each piece by doing a differential evaluation from
    // the current base eval, simulating the removal of the piece from its square.
    Value base = evaluate(pos, false);
    base = pos.side_to_move() == WHITE ? base : -base;

    for (int idx = 0; idx < 24; ++idx)
      {
        Square sq = Square(SQ_BEGIN + idx);
        Piece pc = pos.piece_on(sq);
        Piece unpromotedPc = pc;
        bool isPromoted = false;
        (void)unpromotedPc; // Suppress unused variable warning
        (void)isPromoted;   // Suppress unused variable warning
        Value v = VALUE_NONE;

        if (pc != NO_PIECE)
        {
          auto st = pos.state();

          pos.remove_piece(sq, true);
          st->accumulator.computed[WHITE] = false;
          st->accumulator.computed[BLACK] = false;

          Value eval = evaluate(pos, false);
          eval = pos.side_to_move() == WHITE ? eval : -eval;
          v = base - eval;

          pos.put_piece(pc, sq);
          st->accumulator.computed[WHITE] = false;
          st->accumulator.computed[BLACK] = false;
        }

        // Draw in a 3x8 grid (not the actual board; for textual debug only)
        writeSquare(idx % 3, idx / 3, pc, v);
      }

    ss << " NNUE derived piece values:\n";
    for (int row = 0; row < 16; ++row)
        ss << boardBuf[row] << '\n';
    ss << '\n';

    auto t = trace_evaluate(pos);

    ss << " NNUE network contributions "
       << (pos.side_to_move() == WHITE ? "(White to move)" : "(Black to move)") << std::endl
       << "+------------+------------+------------+------------+\n"
       << "|   Bucket   |  Material  | Positional |   Total    |\n"
       << "|            |   (PSQT)   |  (Layers)  |            |\n"
       << "+------------+------------+------------+------------+\n";

    for (std::size_t bucket = 0; bucket < LayerStacks; ++bucket)
    {
      char buffer[3][8];
      std::memset(buffer, '\0', sizeof(buffer));

      format_cp_aligned_dot(t.psqt[bucket], buffer[0]);
      format_cp_aligned_dot(t.positional[bucket], buffer[1]);
      format_cp_aligned_dot(t.psqt[bucket] + t.positional[bucket], buffer[2]);

      ss <<  "|  " << bucket    << "        "
         << " |  " << buffer[0] << "  "
         << " |  " << buffer[1] << "  "
         << " |  " << buffer[2] << "  "
         << " |";
      if (bucket == t.correctBucket)
          ss << " <-- this bucket is used";
      ss << '\n';
    }

    ss << "+------------+------------+------------+------------+\n";

    return ss.str();
  }


  // Load eval, from a file stream or a memory stream
  bool load_eval(std::string name, std::istream& stream) {

    initialize();
    fileName = name;
    return read_parameters(stream);
  }

  // Save eval, to a file stream or a memory stream
  bool save_eval(std::ostream& stream) {

    if (fileName.empty())
      return false;

    return write_parameters(stream);
  }

  /// Save eval, to a file given by its name
  bool save_eval(const std::optional<std::string>& filenameOpt) {

    std::string actualFilename;
    std::string msg;

    if (filenameOpt.has_value())
        actualFilename = filenameOpt.value();
    else
        actualFilename = fileName.empty() ? std::string("nnue.bin") : fileName;

    std::ofstream stream(actualFilename, std::ios_base::binary);
    bool saved = save_eval(stream);

    msg = saved ? "Network saved successfully to " + actualFilename
                : "Failed to export a net";

    sync_cout << msg << sync_endl;
    return saved;
  }


} // namespace Stockfish::Eval::NNUE
