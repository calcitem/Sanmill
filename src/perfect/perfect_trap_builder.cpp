// SPDX-License-Identifier: GPL-3.0-or-later

// This prevents windows.h from defining min/max macros, which would interfere
// with std::min/max. Must be defined before any header that might include it.
#if defined(_WIN32) && !defined(NOMINMAX)
#define NOMINMAX
#endif

#include "perfect_trap_db.h"

#include "perfect_api.h"
#include "perfect_common.h"
#include "perfect_errors.h"
#include "perfect_player.h"
#include "perfect_sector.h"
#include "perfect_wrappers.h"
#include "perfect_rules.h"
#include "perfect_game_state.h"

#include <cstdio>
#include <cstring>
#include <map>
#include <string>
#include <unordered_map>
#include <vector>
#include <chrono>
#include <iostream>
#include <numeric>
#include <thread>
#include <mutex>
#include <atomic>
#include <future>
#include <queue>
#include <algorithm>
#include <iterator>
#ifdef _MSC_VER
#include <intrin.h>
#endif
#include <filesystem>
#include <csignal>
#include <cstdlib>
#include <fstream>
#include <unordered_set>

namespace {

constexpr const char *kMagic = "TRAPDB2\0"; // 8 bytes including NUL

// Simple signal handler to log fatal signals
void trapdb_signal_handler(int sig)
{
    const char *name = "unknown";
    switch (sig) {
    case SIGSEGV:
        name = "SIGSEGV";
        break;
    case SIGABRT:
        name = "SIGABRT";
        break;
    case SIGFPE:
        name = "SIGFPE";
        break;
    case SIGILL:
        name = "SIGILL";
        break;
    case SIGTERM:
        name = "SIGTERM";
        break;
    default:
        break;
    }
    std::cerr << "Fatal signal received: " << name << " (" << sig << ")"
              << std::endl;
    std::cerr.flush();
    std::fflush(stdout);
}

void install_signal_handlers()
{
    std::signal(SIGSEGV, trapdb_signal_handler);
    std::signal(SIGABRT, trapdb_signal_handler);
    std::signal(SIGFPE, trapdb_signal_handler);
    std::signal(SIGILL, trapdb_signal_handler);
    std::signal(SIGTERM, trapdb_signal_handler);
}

// Cross-platform popcount function
inline int popcount(uint32_t x)
{
#ifdef _MSC_VER
    return static_cast<int>(__popcnt(x));
#else
    return __builtin_popcount(x);
#endif
}

struct TrapRecDisk
{
    uint32_t wBits;
    uint32_t bBits;
    uint8_t side;
    uint8_t WF;
    uint8_t BF;
    uint8_t mask;
};

inline bool fwrite_exact(const void *src, size_t size, FILE *f)
{
    return std::fwrite(src, 1, size, f) == size;
}

// Robust periodic checkpoint writer to persist partial results safely.
// Writes a complete snapshot to a temp file and atomically replaces target.
struct CheckpointWriter
{
    std::string out_path;
    std::chrono::steady_clock::time_point last_write;
    int min_interval_seconds = 15;
    std::mutex write_mutex;

    explicit CheckpointWriter(const std::string &path)
        : out_path(path)
        , last_write(std::chrono::steady_clock::now())
    { }

    bool should_write_now(bool force) const
    {
        if (force)
            return true;
        auto now = std::chrono::steady_clock::now();
        auto secs = std::chrono::duration_cast<std::chrono::seconds>(now -
                                                                     last_write)
                        .count();
        return secs >= min_interval_seconds;
    }

    bool write_snapshot(
        const std::vector<
            std::pair<uint64_t, std::tuple<uint8_t, int8_t, int16_t>>> &snapshot)
    {
        if (snapshot.empty())
            return false; // avoid overwriting with empty DB unless forced
                          // elsewhere

        std::lock_guard<std::mutex> lock(write_mutex);

        const std::string tmp_path = out_path + ".tmp";

        FILE *f = nullptr;
        if (FOPEN(&f, tmp_path.c_str(), "wb") != 0 || !f) {
            std::cerr << "Error: unable to open checkpoint temp file: "
                      << tmp_path << std::endl;
            return false;
        }

        // Header
        if (!fwrite_exact(kMagic, 8, f)) {
            fclose(f);
            return false;
        }
        uint32_t count = static_cast<uint32_t>(snapshot.size());
        if (!fwrite_exact(&count, sizeof(count), f)) {
            fclose(f);
            return false;
        }

        for (const auto &kvp : snapshot) {
            TrapRecDisk rec;
            rec.wBits = (uint32_t)(kvp.first & (uint64_t)mask24);
            rec.bBits = (uint32_t)((kvp.first >> 24) & (uint64_t)mask24);
            rec.side = (uint8_t)((kvp.first >> 48) & 1);
            rec.WF = (uint8_t)((kvp.first >> 49) & 31);
            rec.BF = (uint8_t)((kvp.first >> 54) & 31);
            rec.mask = std::get<0>(kvp.second);

            if (!fwrite_exact(&rec, sizeof(rec), f)) {
                fclose(f);
                return false;
            }
            int8_t wdl = std::get<1>(kvp.second);
            int16_t steps = std::get<2>(kvp.second);
            if (!fwrite_exact(&wdl, sizeof(wdl), f) ||
                !fwrite_exact(&steps, sizeof(steps), f)) {
                fclose(f);
                return false;
            }
        }

        std::fflush(f);
        fclose(f);

        std::error_code ec;
        std::filesystem::path dst(out_path);
        std::filesystem::path src(tmp_path);
        std::filesystem::remove(dst, ec); // ignore if missing
        ec.clear();
        std::filesystem::rename(src, dst, ec);
        if (ec) {
            std::cerr << "Warning: failed to rename checkpoint file: "
                      << ec.message() << std::endl;
            return false;
        }

        last_write = std::chrono::steady_clock::now();
        std::cout << "Checkpoint saved: " << count << " records" << std::endl;
        std::cout.flush();
        return true;
    }
};

// Load existing traps from a given output file path (if present) to support
// resume. Returns true if loaded successfully, false otherwise.
bool load_existing_traps(
    const std::string &file_path,
    std::unordered_map<uint64_t, std::tuple<uint8_t, int8_t, int16_t>> &out)
{
    FILE *f = nullptr;
    if (FOPEN(&f, file_path.c_str(), "rb") != 0 || !f)
        return false;

    char magic[8];
    if (!std::fread(magic, 1, sizeof(magic), f) ||
        std::memcmp(magic, kMagic, sizeof(magic)) != 0) {
        fclose(f);
        return false;
    }
    uint32_t count = 0;
    if (!std::fread(&count, 1, sizeof(count), f)) {
        fclose(f);
        return false;
    }

    for (uint32_t i = 0; i < count; ++i) {
        TrapRecDisk rec {};
        if (std::fread(&rec, 1, sizeof(rec), f) != sizeof(rec)) {
            fclose(f);
            return false;
        }
        int8_t wdl = 0;
        int16_t steps = -1;
        if (std::fread(&wdl, 1, sizeof(wdl), f) != sizeof(wdl) ||
            std::fread(&steps, 1, sizeof(steps), f) != sizeof(steps)) {
            fclose(f);
            return false;
        }
        const uint64_t key = TrapDB::trap_make_key(rec.wBits, rec.bBits,
                                                   rec.side, rec.WF, rec.BF);
        auto it = out.find(key);
        if (it == out.end()) {
            out.emplace(key, std::make_tuple(rec.mask, wdl, steps));
        } else {
            std::get<0>(it->second) |= rec.mask;
            if (wdl > std::get<1>(it->second)) {
                std::get<1>(it->second) = wdl;
                std::get<2>(it->second) = steps;
            }
        }
    }

    fclose(f);
    return true;
}

// Minimal resume tracker that records completed sectors to a progress file
// (one sector filename per line). This allows skipping processed sectors
// across runs.
struct ResumeTracker
{
    std::string progress_path;
    std::unordered_set<std::string> completed;
    std::mutex mutex;

    explicit ResumeTracker(const std::string &out_file)
    {
        progress_path = out_file + ".progress";
    }

    void load()
    {
        std::lock_guard<std::mutex> lock(mutex);
        std::ifstream in(progress_path);
        if (!in.is_open())
            return;
        std::string line;
        while (std::getline(in, line)) {
            if (!line.empty())
                completed.insert(line);
        }
    }

    bool is_completed(const std::string &sector_name)
    {
        std::lock_guard<std::mutex> lock(mutex);
        return completed.find(sector_name) != completed.end();
    }

    void mark_completed(const std::string &sector_name)
    {
        {
            std::lock_guard<std::mutex> lock(mutex);
            if (completed.find(sector_name) != completed.end())
                return;
            completed.insert(sector_name);
        }
        // Append to file (best-effort; ignore IO errors)
        std::ofstream out(progress_path, std::ios::app);
        if (out.is_open()) {
            out << sector_name << "\n";
            out.flush();
        }
    }
};

static bool blocks_opponent_mill_local(PerfectPlayer &pl, const GameState &s,
                                       const AdvancedMove &m)
{
    if (m.onlyTaking)
        return false; // Pure taking is not considered a block here

    GameState before = s;
    AdvancedMove mCopy = m; // Make a non-const copy
    GameState after = pl.make_move_in_state(s, mCopy);
    if (PerfectErrors::hasError()) {
        PerfectErrors::clearError();
        return false;
    }

    // Count opponent immediate mill-making moves before
    GameState sOpp = before;
    sOpp.sideToMove = 1 - before.sideToMove;
    int cntBefore = 0;
    for (auto &mm : pl.get_move_list(sOpp)) {
        if (mm.withTaking)
            cntBefore++;
    }
    if (cntBefore == 0)
        return false; // No threat to block

    GameState sOppAfter = after;
    sOppAfter.sideToMove = 1 - after.sideToMove;
    int cntAfter = 0;
    for (auto &mm : pl.get_move_list(sOppAfter)) {
        if (mm.withTaking)
            cntAfter++;
    }

    return cntAfter < cntBefore;
}

// Smart position pre-filter to skip unlikely trap candidates
struct PositionPreFilter
{
    // Fast heuristics to determine if a position could potentially be a trap
    static bool could_be_trap(const GameState &s)
    {
        // Quick checks to eliminate obvious non-traps

        // 1. Skip positions with too few pieces (unlikely to have complex
        // traps)
        int totalPieces = s.stoneCount[0] + s.stoneCount[1];
        if (totalPieces < 4)
            return false;

        // 2. Skip if current player has too few options (likely already
        // determined)
        if (s.phase == 2 && totalPieces < 6)
            return false;

        // 3. Quick mill detection - if no mills are possible, likely no mill
        // traps
        if (!has_potential_mill_threats(s))
            return false;

        return true;
    }

private:
    // Fast check for potential mill threats using bitboard operations
    static bool has_potential_mill_threats(const GameState &s)
    {
        // Convert board to bitboards for fast mill checking
        uint32_t whiteBits = 0, blackBits = 0, emptyBits = 0;

        for (int i = 0; i < 24; ++i) {
            if (s.board[i] == 0)
                whiteBits |= (1u << i);
            else if (s.board[i] == 1)
                blackBits |= (1u << i);
            else
                emptyBits |= (1u << i);
        }

        // Check if any mill lines have 2 pieces and 1 empty (potential mill
        // threat) Mill positions for standard Nine Men's Morris
        static const uint32_t millLines[] = {
            0x000007, 0x000038, 0x0001C0, 0x000E00,
            0x007000, 0x038000, 0x1C0000, 0xE00000, // rows
            0x010101, 0x020202, 0x040404, 0x080808,
            0x101010, 0x202020, 0x404040, 0x808080 // columns & diagonals
        };

        for (uint32_t line : millLines) {
            uint32_t whiteOnLine = whiteBits & line;
            uint32_t blackOnLine = blackBits & line;
            uint32_t emptyOnLine = emptyBits & line;

            // Check for 2-pieces-1-empty patterns (potential mill threats)
            if (popcount(whiteOnLine) == 2 && popcount(emptyOnLine) == 1)
                return true;
            if (popcount(blackOnLine) == 2 && popcount(emptyOnLine) == 1)
                return true;
        }

        return false;
    }
};

// Fast evaluation cache to avoid repeated Perfect DB calls
struct EvalCache
{
    std::unordered_map<uint64_t, char> cache; // position_key -> first_char of
                                              // evaluation

    char get_eval_first_char(PerfectPlayer &pl, const GameState &s,
                             const AdvancedMove &m)
    {
        // Create a simple key from the move result
        AdvancedMove moveCopy = m;
        GameState s2 = pl.make_move_in_state(s, moveCopy);
        if (PerfectErrors::hasError()) {
            PerfectErrors::clearError();
            return 'L'; // Assume loss for invalid moves
        }

        uint64_t key = compute_position_key(s2);
        auto it = cache.find(key);
        if (it != cache.end()) {
            return it->second;
        }

        // Only call Perfect DB if not cached
        AdvancedMove moveCopyEval = m;
        auto eval = pl.move_value(s, moveCopyEval);
        std::string evalStr = eval.to_string();
        char result = (evalStr.empty()) ? 'L' : evalStr[0];
        cache[key] = result;
        return result;
    }

private:
    uint64_t compute_position_key(const GameState &s)
    {
        uint64_t key = 0;
        for (int i = 0; i < 24; ++i) {
            if (s.board[i] >= 0) {
                key |= ((uint64_t)(s.board[i] + 1)) << (i * 2);
            }
        }
        key ^= ((uint64_t)s.sideToMove) << 48;
        key ^= ((uint64_t)s.setStoneCount[0]) << 52;
        key ^= ((uint64_t)s.setStoneCount[1]) << 56;
        return key;
    }
};

static bool is_self_mill_loss_trap_fast(PerfectPlayer &pl, const GameState &s,
                                        const std::vector<AdvancedMove> &moves,
                                        EvalCache &cache)
{
    bool hasForm = false;
    bool allFormLose = true;
    bool existsOtherNonLose = false;

    // First pass: check all mill-forming moves
    for (const auto &m : moves) {
        if (m.withTaking) {
            hasForm = true;
            char evalChar = cache.get_eval_first_char(pl, s, m);
            if (evalChar != 'L') {
                allFormLose = false;
                break; // Early exit optimization
            }
        }
    }

    if (!hasForm || !allFormLose)
        return false;

    // Second pass: check non-mill moves for better alternatives
    for (const auto &m : moves) {
        if (!m.withTaking) {
            char evalChar = cache.get_eval_first_char(pl, s, m);
            if (evalChar != 'L') {
                existsOtherNonLose = true;
                break; // Early exit optimization
            }
        }
    }

    return existsOtherNonLose;
}

static bool is_block_mill_loss_trap_fast(PerfectPlayer &pl, const GameState &s,
                                         const std::vector<AdvancedMove> &moves,
                                         EvalCache &cache)
{
    bool anyBlock = false;
    bool allBlockLose = true;
    bool existsOtherNonLose = false;

    // First pass: check all mill-blocking moves
    for (const auto &m : moves) {
        if (!m.withTaking && blocks_opponent_mill_local(pl, s, m)) {
            anyBlock = true;
            char evalChar = cache.get_eval_first_char(pl, s, m);
            if (evalChar != 'L') {
                allBlockLose = false;
                break; // Early exit optimization
            }
        }
    }

    if (!anyBlock || !allBlockLose)
        return false;

    // Second pass: check non-blocking moves for better alternatives
    for (const auto &m : moves) {
        if (!(!m.withTaking && blocks_opponent_mill_local(pl, s, m))) {
            char evalChar = cache.get_eval_first_char(pl, s, m);
            if (evalChar != 'L') {
                existsOtherNonLose = true;
                break; // Early exit optimization
            }
        }
    }

    return existsOtherNonLose;
}

// Progress tracking for detailed reporting
struct ProgressTracker
{
    std::mutex mutex;
    std::atomic<int> completed_sectors {0};
    std::atomic<int> total_sectors {0};
    std::chrono::steady_clock::time_point start_time;
    std::vector<std::string> sector_names;
    std::vector<long> sector_sizes;
    long total_size = 0;
    long processed_size = 0;

    void initialize(const std::map<Wrappers::WID, Wrappers::WSector> &sectorMap)
    {
        total_sectors = static_cast<int>(sectorMap.size());
        start_time = std::chrono::steady_clock::now();

        // Get sector information for progress estimation
        for (const auto &kv : sectorMap) {
            sector_names.push_back(kv.second.s->id.file_name());

            std::string sector_path = secValPath + "/" +
                                      kv.second.s->id.file_name();
            FILE *f = fopen(sector_path.c_str(), "rb");
            if (f) {
                fseek(f, 0, SEEK_END);
                long size = ftell(f);
                sector_sizes.push_back(size);
                total_size += size;
                fclose(f);
            } else {
                sector_sizes.push_back(0);
            }
        }
    }

    void report_sector_completed(const std::string &sector_name, int self_mill,
                                 int block_mill, int positions)
    {
        std::lock_guard<std::mutex> lock(mutex);
        int current = completed_sectors.fetch_add(1) + 1;

        // Find sector size for progress calculation
        auto it = std::find(sector_names.begin(), sector_names.end(),
                            sector_name);
        if (it != sector_names.end()) {
            int index = static_cast<int>(
                std::distance(sector_names.begin(), it));
            if (index < static_cast<int>(sector_sizes.size())) {
                processed_size += sector_sizes[index];
            }
        }

        auto now = std::chrono::steady_clock::now();
        auto elapsed = std::chrono::duration_cast<std::chrono::seconds>(
                           now - start_time)
                           .count();

        // Calculate remaining time based on processed data size
        double time_per_byte = (processed_size > 0) ?
                                   static_cast<double>(elapsed) /
                                       processed_size :
                                   0;
        double remaining_time = time_per_byte * (total_size - processed_size);

        std::cout << "[" << current << "/" << total_sectors.load()
                  << "] Processing " << sector_name << " | Elapsed: " << elapsed
                  << "s, Remaining: " << static_cast<int>(remaining_time) << "s"
                  << std::endl;

        // Print sector statistics
        int sector_total_traps = self_mill + block_mill;
        std::cout << "  Found " << sector_total_traps << " trap positions in "
                  << positions << " scanned (including symmetries)"
                  << std::endl;
        std::cout << "    Self-mill-loss traps: " << self_mill << std::endl;
        std::cout << "    Block-mill-loss traps: " << block_mill << std::endl;
    }
};

// Thread-safe result collector for parallel processing
struct ThreadSafeCollector
{
    std::mutex mutex;
    std::unordered_map<uint64_t, std::tuple<uint8_t, int8_t, int16_t>>
        collected_traps;
    std::atomic<int> total_self_mill_traps {0};
    std::atomic<int> total_block_mill_traps {0};
    std::atomic<int> total_positions_scanned {0};
    ProgressTracker *progress_tracker = nullptr;
    CheckpointWriter *checkpoint_writer = nullptr;
    int sectors_since_last_checkpoint = 0;
    ResumeTracker *resume_tracker = nullptr;

    void merge_results(
        const std::unordered_map<uint64_t, std::tuple<uint8_t, int8_t, int16_t>>
            &batch_traps,
        int self_mill_count, int block_mill_count, int positions_count,
        const std::string &sector_name = "")
    {
        bool do_checkpoint = false;
        std::vector<std::pair<uint64_t, std::tuple<uint8_t, int8_t, int16_t>>>
            snapshot;

        {
            std::lock_guard<std::mutex> lock(mutex);

            // Merge trap data
            for (const auto &kvp : batch_traps) {
                auto it = collected_traps.find(kvp.first);
                if (it == collected_traps.end()) {
                    collected_traps[kvp.first] = kvp.second;
                } else {
                    // Merge masks and prefer stronger WDL
                    std::get<0>(it->second) |= std::get<0>(kvp.second);
                    if (std::get<1>(kvp.second) > std::get<1>(it->second)) {
                        std::get<1>(it->second) = std::get<1>(kvp.second);
                        std::get<2>(it->second) = std::get<2>(kvp.second);
                    }
                }
            }

            // Update statistics
            total_self_mill_traps += self_mill_count;
            total_block_mill_traps += block_mill_count;
            total_positions_scanned += positions_count;

            // Report progress if tracker is available
            if (progress_tracker && !sector_name.empty()) {
                progress_tracker->report_sector_completed(sector_name,
                                                          self_mill_count,
                                                          block_mill_count,
                                                          positions_count);

                // Print cumulative statistics
                int total_traps_found = total_self_mill_traps.load() +
                                        total_block_mill_traps.load();
                std::cout << "  Cumulative: " << total_traps_found
                          << " traps from " << total_positions_scanned.load()
                          << " positions scanned" << std::endl;
                std::cout.flush(); // Ensure immediate output
            } else {
                // Fallback: simple progress reporting if detailed tracking
                // fails
                static std::atomic<int> simple_counter {0};
                int current = simple_counter.fetch_add(1) + 1;
                if (current % 1 == 0) { // Report every sector for debugging
                    std::cout << "DEBUG: Processed sector " << current << " ("
                              << sector_name << ")"
                              << " - found "
                              << (self_mill_count + block_mill_count)
                              << " traps" << std::endl;
                    std::cout.flush();
                }
            }

            // Mark sector completion for resume
            if (resume_tracker && !sector_name.empty()) {
                resume_tracker->mark_completed(sector_name);
            }

            // Decide whether to checkpoint now
            if (checkpoint_writer) {
                sectors_since_last_checkpoint += 1;
                if (!collected_traps.empty() &&
                    sectors_since_last_checkpoint >= 1 &&
                    checkpoint_writer->should_write_now(false)) {
                    snapshot.reserve(collected_traps.size());
                    for (const auto &kv : collected_traps) {
                        snapshot.emplace_back(kv.first, kv.second);
                    }
                    do_checkpoint = true;
                    sectors_since_last_checkpoint = 0;
                }
            }
        }

        // Perform checkpoint outside the collector lock
        if (do_checkpoint && checkpoint_writer) {
            checkpoint_writer->write_snapshot(snapshot);
        }
    }
};

// Parallel sector processor
class ParallelSectorProcessor
{
    ThreadSafeCollector &collector;

public:
    ParallelSectorProcessor(ThreadSafeCollector &c)
        : collector(c)
    { }

    void process_sector(const std::pair<Wrappers::WID, Wrappers::WSector> &kv,
                        int sector_index)
    {
        try {
            const Wrappers::WSector &wsec = kv.second;
            Sector *sec = wsec.s;
            const std::string sector_name = sec->id.file_name();

            sec->allocate_hash();
            if (!sec->hash || sec->hash->hash_count == 0) {
                sec->release_hash();
                collector.merge_results({}, 0, 0, 0, sector_name);
                return;
            }

            int intra_threads = 1;
            if (const char *env_intra_threads = std::getenv("SANMILL_INTRA_"
                                                            "SECTOR_THREADS")) {
                int t = std::atoi(env_intra_threads);
                if (t > 1)
                    intra_threads = t;
            }

            // If intra-parallelism is disabled or sector is too small, run
            // sequentially
            if (intra_threads <= 1 || sec->hash->hash_count < 10000) {
                process_positions(0, sec->hash->hash_count, sec);
            } else {
                // Intra-sector parallel processing
                std::vector<std::future<void>> futures;
                const int total_positions = sec->hash->hash_count;
                const int positions_per_thread = (total_positions +
                                                  intra_threads - 1) /
                                                 intra_threads;

                for (int t = 0; t < intra_threads; ++t) {
                    int start = t * positions_per_thread;
                    int end = std::min(start + positions_per_thread,
                                       total_positions);
                    if (start < end) {
                        futures.emplace_back(std::async(
                            std::launch::async, [this, start, end, sec] {
                                this->process_positions(start, end, sec);
                            }));
                    }
                }
                for (auto &f : futures) {
                    f.get(); // Wait and propagate exceptions
                }
            }

            sec->release_hash();

        } catch (const std::exception &e) {
            std::cerr << "Error processing sector " << sector_index << ": "
                      << e.what() << std::endl;
        } catch (...) {
            std::cerr << "Unknown error processing sector " << sector_index
                      << std::endl;
        }
    }

    // This function processes a range of positions within a single sector
    void process_positions(int start_idx, int end_idx, Sector *sec)
    {
        const std::string sector_name = sec->id.file_name();

        // Create thread-local resources for this task
        PerfectPlayer pl;
        EvalCache eval_cache;
        size_t cache_size = 5000;
        size_t cache_cleanup_thresh = 3000;
        if (const char *env_cache = std::getenv("SANMILL_TRAP_CACHE_SIZE")) {
            long long c = std::atoll(env_cache);
            if (c > 0) {
                cache_size = static_cast<size_t>(c);
                cache_cleanup_thresh = cache_size * 3 / 5;
            }
        }
        eval_cache.cache.reserve(cache_size);

        std::unordered_map<uint64_t, std::tuple<uint8_t, int8_t, int16_t>>
            local_traps;
        int local_self_mill = 0, local_block_mill = 0, local_positions = 0;

        const int cleanup_interval = 1000;
        for (int i = start_idx; i < end_idx; ++i) {
            if (i > start_idx && (i - start_idx) % cleanup_interval == 0) {
                if (eval_cache.cache.size() > cache_cleanup_thresh) {
                    eval_cache.cache.clear();
                    eval_cache.cache.reserve(cache_size);
                }
            }

            const board raw = sec->hash->inverse_hash(i);
            const uint32_t whiteBits = (uint32_t)(raw & mask24);
            const uint32_t blackBits = (uint32_t)((raw >> 24) & mask24);

            auto make_state = [&](int sideToMove) {
                GameState s;
                for (int sq = 0; sq < 24; ++sq) {
                    uint32_t m = 1u << sq;
                    if (whiteBits & m)
                        s.board[sq] = 0;
                    else if (blackBits & m)
                        s.board[sq] = 1;
                    else
                        s.board[sq] = -1;
                }
                s.stoneCount[0] = sec->W;
                s.stoneCount[1] = sec->B;
                const int maxK = 9;
                s.setStoneCount[0] = maxK - sec->WF;
                s.setStoneCount[1] = maxK - sec->BF;
                s.kle = false;
                s.sideToMove = sideToMove;
                s.moveCount = 10;
                s.lastIrrev = 0;
                s.phase = ((sec->WF == 0 && sec->BF == 0) ? 2 : 1);
                return s;
            };

            for (int stm = 0; stm <= 1; ++stm) {
                GameState s = make_state(stm);
                local_positions++;

                if (!PositionPreFilter::could_be_trap(s)) {
                    continue;
                }

                std::vector<AdvancedMove> moves = pl.get_move_list(s);
                if (moves.empty())
                    continue;

                bool isSelfTrap = is_self_mill_loss_trap_fast(pl, s, moves,
                                                              eval_cache);
                bool isBlockTrap = is_block_mill_loss_trap_fast(pl, s, moves,
                                                                eval_cache);

                uint8_t mask = 0;
                if (isSelfTrap) {
                    mask |= TrapDB::Trap_SelfMillLoss;
                    local_self_mill++;
                }
                if (isBlockTrap) {
                    mask |= TrapDB::Trap_BlockMillLoss;
                    local_block_mill++;
                }

                if (mask) {
                    int8_t wdl = 0;
                    int16_t steps = -1;
                    auto e2 = pl.evaluate(s);
                    std::string str = e2.to_string();
                    if (!str.empty()) {
                        char c = str[0];
                        if (c == 'W')
                            wdl = +1;
                        else if (c == 'L')
                            wdl = -1;
                        else
                            wdl = 0;
                        const char *cstr = str.c_str();
                        const char *lastParen = strrchr(cstr, '(');
                        if (lastParen) {
                            const char *commaPos = strchr(lastParen, ',');
                            const char *closePos = strchr(lastParen, ')');
                            if (commaPos && closePos && commaPos < closePos) {
                                const char *numStart = commaPos + 1;
                                while (*numStart == ' ' || *numStart == '\t')
                                    numStart++;
                                int parsedSteps = 0;
                                bool negative = (*numStart == '-');
                                if (negative)
                                    numStart++;
                                while (*numStart >= '0' && *numStart <= '9' &&
                                       numStart < closePos) {
                                    parsedSteps = parsedSteps * 10 +
                                                  (*numStart - '0');
                                    numStart++;
                                }
                                if (parsedSteps > 0) {
                                    if (negative)
                                        parsedSteps = -parsedSteps;
                                    // Clamp to int16_t range to prevent data
                                    // loss
                                    parsedSteps = (std::max)(
                                        -32768, (std::min)(32767, parsedSteps));
                                    steps = static_cast<int16_t>(parsedSteps);
                                }
                            }
                        }
                    }

                    uint64_t key = TrapDB::trap_make_key(whiteBits, blackBits,
                                                         (uint8_t)stm,
                                                         (uint8_t)sec->WF,
                                                         (uint8_t)sec->BF);
                    auto it = local_traps.find(key);
                    if (it == local_traps.end()) {
                        local_traps.emplace(key,
                                            std::make_tuple(mask, wdl, steps));
                    } else {
                        std::get<0>(it->second) |= mask;
                        if (wdl > std::get<1>(it->second)) {
                            std::get<1>(it->second) = wdl;
                            std::get<2>(it->second) = steps;
                        }
                    }
                }
            }
        }

        collector.merge_results(local_traps, local_self_mill, local_block_mill,
                                local_positions, sector_name);
    }
};

} // namespace

// Build trap DB from full perfect DB located at secValPath directory
// Returns true on success
bool build_trap_db_to_file(const std::string &outFile)
{
    using namespace PerfectErrors;

    clearError();
    install_signal_handlers();

    auto sectorMap = Sectors::get_sectors();
    if (sectorMap.empty()) {
        return false;
    }

    // Determine optimal thread count (conservative for memory management)
    const int hardware_threads = static_cast<int>(
        std::thread::hardware_concurrency());
    const int sector_count = static_cast<int>(sectorMap.size());
    // Use fewer threads to reduce memory pressure (each thread allocates
    // ~100MB+)
    int max_safe_threads = (std::min)(8, hardware_threads / 2); // Conservative
                                                                // limit
    // Allow override via environment variable SANMILL_TRAP_THREADS
    if (const char *env_threads = std::getenv("SANMILL_TRAP_THREADS")) {
        int t = std::atoi(env_threads);
        if (t > 0) {
            max_safe_threads = t;
        }
    }
    const int worker_threads = (std::max)(1, (std::min)(max_safe_threads,
                                                        sector_count));

    std::cout << "Using " << worker_threads
              << " threads for parallel processing" << std::endl;

    // Intra-sector parallelism config
    int intra_sector_threads = 1;
    if (const char *env_intra_threads = std::getenv("SANMILL_INTRA_SECTOR_"
                                                    "THREADS")) {
        int t = std::atoi(env_intra_threads);
        if (t > 1) {
            intra_sector_threads = t;
        }
    }
    if (intra_sector_threads > 1) {
        std::cout << "Using " << intra_sector_threads
                  << " sub-threads for intra-sector processing" << std::endl;
    }

    std::cout << "Expected memory usage: ~" << (worker_threads * 100)
              << "MB for lookup tables" << std::endl;

    // Initialize progress tracker
    ProgressTracker progress_tracker;
    progress_tracker.initialize(sectorMap);

    // Thread-safe collector for results
    ThreadSafeCollector collector;
    collector.progress_tracker = &progress_tracker;
    // Prepare checkpoint writer (atomic persistence of partial progress)
    CheckpointWriter checkpoint_writer(outFile);
    collector.checkpoint_writer = &checkpoint_writer;

    // Resume tracker for sector-level progress across runs
    ResumeTracker resume(outFile);
    resume.load();
    collector.resume_tracker = &resume;

    // Preload existing traps from previous run (if any)
    if (load_existing_traps(outFile, collector.collected_traps)) {
        std::cout << "Resume: loaded " << collector.collected_traps.size()
                  << " existing trap records" << std::endl;
    }

    // Convert sector map to vector for parallel processing
    std::vector<std::pair<Wrappers::WID, Wrappers::WSector>> sector_vector;
    sector_vector.reserve(sectorMap.size());
    for (const auto &kv : sectorMap) {
        sector_vector.push_back(kv);
    }

    std::cout << "Processing " << sector_vector.size() << " sectors..."
              << std::endl;

    auto startTime = std::chrono::steady_clock::now();

    // Create thread pool and process sectors in parallel
    std::vector<std::future<void>> futures;
    futures.reserve(worker_threads);

    // Create a thread pool using futures for better resource management
    auto process_sector_range = [&](int start_idx, int end_idx) {
        ParallelSectorProcessor processor(collector);
        for (int i = start_idx; i < end_idx; ++i) {
            const std::string sector_name = sector_vector[i]
                                                .second.s->id.file_name();
            if (collector.resume_tracker &&
                collector.resume_tracker->is_completed(sector_name)) {
                // Already completed in previous run: still report progress to
                // keep counters consistent
                static const std::unordered_map<
                    uint64_t, std::tuple<uint8_t, int8_t, int16_t>>
                    empty;
                collector.merge_results(empty, 0, 0, 0, sector_name);
                continue;
            }
            processor.process_sector(sector_vector[i], i);
        }
    };

    // Distribute sectors among threads
    const int sectors_per_thread = (sector_vector.size() + worker_threads - 1) /
                                   worker_threads;

    for (int t = 0; t < worker_threads; ++t) {
        int start_idx = t * sectors_per_thread;
        int end_idx = (std::min)(start_idx + sectors_per_thread,
                                 static_cast<int>(sector_vector.size()));

        if (start_idx < end_idx) {
            futures.emplace_back(std::async(
                std::launch::async, process_sector_range, start_idx, end_idx));
        }
    }

    // Wait for all threads to complete with timeout and error checking
    std::cout << "Waiting for all threads to complete..." << std::endl;
    bool all_completed = true;

    for (size_t i = 0; i < futures.size(); ++i) {
        try {
            // Wait with timeout to detect hanging threads
            auto status = futures[i].wait_for(
                std::chrono::seconds(300)); // 5-minute timeout per thread
            if (status == std::future_status::timeout) {
                std::cerr << "Warning: Thread " << i
                          << " timed out after 300 seconds" << std::endl;
                all_completed = false;
            } else {
                futures[i].get(); // This will throw if the thread had an
                                  // exception
            }
        } catch (const std::exception &e) {
            std::cerr << "Thread " << i
                      << " failed with exception: " << e.what() << std::endl;
            all_completed = false;
        } catch (...) {
            std::cerr << "Thread " << i << " failed with unknown exception"
                      << std::endl;
            all_completed = false;
        }
    }

    if (!all_completed) {
        std::cerr << "Warning: Not all threads completed successfully"
                  << std::endl;
    }

    auto endTime = std::chrono::steady_clock::now();
    auto elapsed = std::chrono::duration_cast<std::chrono::seconds>(endTime -
                                                                    startTime)
                       .count();

    std::cout << "\nParallel processing completed in " << elapsed << " seconds"
              << std::endl;

    // Final forced checkpoint to persist all collected records
    {
        std::vector<std::pair<uint64_t, std::tuple<uint8_t, int8_t, int16_t>>>
            snapshot;
        snapshot.reserve(collector.collected_traps.size());
        for (const auto &kv : collector.collected_traps) {
            snapshot.emplace_back(kv.first, kv.second);
        }
        if (!snapshot.empty()) {
            checkpoint_writer.write_snapshot(snapshot);
        }
    }

    // Print final statistics using atomic counters
    std::cout << "\n=== Final Statistics ===" << std::endl;
    std::cout << "Total positions scanned: "
              << collector.total_positions_scanned.load()
              << " (including 16 symmetries per unique position)" << std::endl;
    std::cout << "Self-mill-loss traps found: "
              << collector.total_self_mill_traps.load() << std::endl;
    std::cout << "Block-mill-loss traps found: "
              << collector.total_block_mill_traps.load() << std::endl;
    std::cout << "Total trap positions: "
              << (collector.total_self_mill_traps.load() +
                  collector.total_block_mill_traps.load())
              << std::endl;
    std::cout << "Unique trap records written to file: "
              << collector.collected_traps.size() << " (deduplicated)"
              << std::endl;
    std::cout << "Processing time: " << elapsed << " seconds" << std::endl;

    return true;
}
