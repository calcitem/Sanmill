// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// benchmark.cpp
//
// Benchmark module for comparing Traditional Search algorithms vs Perfect
// Database Features:
// - Thread-safe parallel game execution (2 threads with opposite colors)
// - Comprehensive error handling and recovery
// - Enhanced statistics tracking (errors, timeouts, repetitions, move counts)
// - Automatic detection of stalemates and excessive game lengths
// - Detailed performance and quality metrics reporting
// - Robust move validation before execution
// - Signal handling for graceful Ctrl+C interruption

#include "benchmark.h"

#include "config.h"
#include "engine_commands.h"
#include "engine_controller.h"
#include "mills.h"
#include "option.h"
#include "rule.h"
#include "perfect/perfect_adaptor.h"
#include "perfect/perfect_api.h"
#include "perfect/perfect_errors.h"
#include "position.h"
#include "search.h"
#include "search_engine.h"
#include "stack.h"
#include "thread.h"
#include "thread_pool.h"
#include "uci.h"

#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <chrono>
#include <iomanip>
#include <iostream>
#include <climits>
#include <condition_variable>
#include <mutex>
#include <sstream>
#include <string>
#include <thread>
#include <memory>
#include <csignal>
#include <atomic>
#include <cctype>
#include <vector>
#include <fstream>

namespace Benchmark {

// Global flag for Ctrl+C handling - use sig_atomic_t for async signal safety
static volatile std::sig_atomic_t g_interrupted = 0;

// Global flag for critical errors - stop benchmark immediately when any error
// occurs
static std::atomic<bool> g_critical_error(false);
static std::string g_error_details;
static std::mutex g_error_mutex;

// Thread-safe logging to prevent output interleaving
static std::mutex g_log_mutex;

// Thread-safe file writing to prevent concurrent file access
static std::mutex g_file_mutex;

// Macro for thread-safe logging
#define SAFE_LOG(stream, msg) \
    do { \
        std::ostringstream oss; \
        oss << msg; \
        std::lock_guard<std::mutex> log_lock(g_log_mutex); \
        stream << oss.str(); \
    } while (0)

// Function to set critical error and stop benchmark immediately
static void set_critical_error(const std::string &error_msg)
{
    std::lock_guard<std::mutex> error_lock(g_error_mutex);
    if (!g_critical_error.load()) {
        g_error_details = error_msg;
        g_critical_error.store(true);

        // Log error immediately
        SAFE_LOG(std::cerr, "\n" << std::string(80, '=') << "\n");
        SAFE_LOG(std::cerr, "CRITICAL ERROR DETECTED - STOPPING BENCHMARK "
                            "IMMEDIATELY\n");
        SAFE_LOG(std::cerr, std::string(80, '=') << "\n");
        SAFE_LOG(std::cerr, error_msg << "\n");
        SAFE_LOG(std::cerr, std::string(80, '=') << "\n");
    }
}

static void signal_handler(int signal)
{
    if (signal == SIGINT) {
        // Only use async-signal-safe operations in signal handler
        // No I/O operations here - they're not async-signal-safe
        g_interrupted = 1;
    }
}

static void apply_config(const BenchmarkConfig &cfg)
{
    // Apply to global gameOptions
    gameOptions.setSkillLevel(cfg.skillLevel);
    gameOptions.setMoveTime(cfg.moveTimeSec);
    gameOptions.setAlgorithm(cfg.algorithm);
    gameOptions.setIDSEnabled(cfg.idsEnabled);
    gameOptions.setDepthExtension(cfg.depthExtension);
    gameOptions.setOpeningBook(cfg.openingBook);
    gameOptions.setShufflingEnabled(cfg.shuffling);
    // For benchmark, force AiIsLazy=false for both sides to ensure fair
    // comparison Both Traditional AI and Perfect DB should use non-lazy mode
    // for consistent evaluation
    gameOptions.setAiIsLazy(false);
    // For benchmark, disable Perfect DB in traditional search engine to ensure
    // pure comparison. Traditional side: pure traditional search algorithms
    // (Alpha-Beta, PVS, MTD(f), MCTS, etc.) Perfect DB side: pure database
    // lookup via direct perfect_search() calls This ensures we're truly
    // comparing "Traditional Search vs Perfect DB" not "Hybrid vs Pure DB"
    gameOptions.setUsePerfectDatabase(false);
    gameOptions.setPerfectDatabasePath(cfg.perfectDbPath);

    // Apply N-move rule configuration to global rule
    // This is essential for 50-move rule to work properly in benchmark
    rule.nMoveRule = cfg.nMoveRule;

    // Ensure threefold repetition rule is active for benchmark games.
    // Some front-ends may toggle this, but benchmark should always enforce it
    // to avoid endless oscillations in the moving phase.
    rule.threefoldRepetitionRule = true;

    // CRITICAL: Force AutoRestart=false for benchmark
    // We handle game loops manually in benchmark, AutoRestart would interfere
    gameOptions.setAutoRestart(false);
}

// Read INI if available.
// We implement a minimal parser to reuse existing keys.
static int parse_int_safe(const std::string &s, int def)
{
    const char *c = s.c_str();
    char *end = nullptr;
    long v = std::strtol(c, &end, 10);
    if (end == c)
        return def;
    const long kIntMin = -2147483647L - 1L;
    const long kIntMax = 2147483647L;
    if (v < kIntMin)
        return static_cast<int>(kIntMin);
    if (v > kIntMax)
        return static_cast<int>(kIntMax);
    return static_cast<int>(v);
}

static int clamp_min(int v, int mn)
{
    return v < mn ? mn : v;
}

static int clamp_range(int v, int mn, int mx)
{
    if (v < mn)
        return mn;
    if (v > mx)
        return mx;
    return v;
}

static void create_default_settings_ini(const std::string &path)
{
    FILE *fp = nullptr;
#ifdef _WIN32
    if (fopen_s(&fp, path.c_str(), "w") != 0) {
        fp = nullptr;
    }
#else
    fp = fopen(path.c_str(), "w");
#endif
    if (!fp) {
        SAFE_LOG(std::cout, "WARNING: Cannot create default settings.ini at: "
                                << path << "\n");
        return;
    }

    // Write default configuration with English comments
    // Use actual C++ code defaults from option.h
    fprintf(fp, "; Sanmill Settings File - Auto-generated\n");
    fprintf(fp, "; Edit these values to customize engine behavior\n");
    fprintf(fp, "; Values match C++ GameOptions defaults from option.h\n");
    fprintf(fp, "\n[Options]\n");
    fprintf(fp, "; === Benchmark Configuration ===\n");
    fprintf(fp, "; Total games to play (0 = infinite until Ctrl+C)\n");
    fprintf(fp, "; Games are split between two threads:\n");
    fprintf(fp, "; Thread A: Traditional=White vs Perfect=Black\n");
    fprintf(fp, "; Thread B: Traditional=Black vs Perfect=White\n");
    fprintf(fp, "; For odd numbers, Thread A gets the extra game (White moves "
                "first)\n");
    fprintf(fp, "; Example: TotalGames=100 means 50+50, TotalGames=101 means "
                "51+50\n");
    fprintf(fp, "TotalGames=100\n");
    fprintf(fp, "; === Flutter App Configurable Options ===\n");
    fprintf(fp, "; Skill Level: 1-30 (higher = stronger, slower)\n");
    fprintf(fp, "SkillLevel=15\n");
    fprintf(fp, "; Move Time: seconds per move (0 = infinite)\n");
    fprintf(fp, "MoveTime=0\n");
    fprintf(fp, "; Algorithm: 0=AlphaBeta, 1=PVS, 2=MTDf, 3=MCTS, 4=Random\n");
    fprintf(fp, "Algorithm=2\n");
    fprintf(fp, "; AI is lazy (reduce search when winning): true/false\n");
    fprintf(fp, "AiIsLazy=false\n");
    fprintf(fp, "; Auto restart games: true/false (false for benchmark - we "
                "handle game loops internally)\n");
    fprintf(fp, "AutoRestart=false\n");
    fprintf(fp, "; Auto change first move: true/false\n");
    fprintf(fp, "AutoChangeFirstMove=false\n");
    fprintf(fp, "; Resign when losing badly: true/false\n");
    fprintf(fp, "ResignIfMostLose=false\n");
    fprintf(fp, "; Shuffle moves with equal evaluation: true/false\n");
    fprintf(fp, "Shuffling=true\n");
    fprintf(fp, "; Learn endgame: true/false\n");
    fprintf(fp, "LearnEndgameEnabled=false\n");
    fprintf(fp, "; Use Perfect Database: true/false (REQUIRED for "
                "benchmark)\n");
    fprintf(fp, "UsePerfectDatabase=true\n");
    fprintf(fp, "; Perfect Database Path: directory containing DB files\n");
    fprintf(fp, "; Windows example: C:\\\\DB\\\\Std or C:/DB/Std\n");
    fprintf(fp, "; Linux example: /home/user/db/std\n");
    fprintf(fp, "PerfectDatabasePath=D:\\user\\Documents\\strong\n");
    fprintf(fp, "; Draw on human experience: true/false\n");
    fprintf(fp, "DrawOnHumanExperience=true\n");
    fprintf(fp, "; Consider mobility: true/false\n");
    fprintf(fp, "ConsiderMobility=true\n");
    fprintf(fp, "; Focus on blocking paths: true/false\n");
    fprintf(fp, "FocusOnBlockingPaths=false\n");
    fprintf(fp, "; Opening Book: true/false\n");
    fprintf(fp, "OpeningBook=false\n");
    fprintf(fp, "; Trap awareness analysis: true/false\n");
    fprintf(fp, "TrapAwareness=false\n");
    fprintf(fp, "; N-Move Rule: maximum moves without capture/mill for draw "
                "(10-200, default: 100)\n");
    fprintf(fp, "NMoveRule=100\n");
    fprintf(fp, "; === CLI/Engine Only Options (not in Flutter UI) ===\n");
    fprintf(fp, "; Iterative Deepening Search: true/false (C++ default: "
                "false)\n");
    fprintf(fp, "IDS=false\n");
    fprintf(fp, "; Depth Extension on single reply: true/false (C++ default: "
                "true)\n");
    fprintf(fp, "DepthExtension=true\n");
    fprintf(fp, "; Developer Mode: true/false (C++ default: false)\n");
    fprintf(fp, "DeveloperMode=false\n");

    fclose(fp);
    SAFE_LOG(std::cout,
             "INFO: settings.ini not found, auto-generated default file at: "
                 << path << "\n"
                 << "INFO: You can edit this file to customize engine "
                    "parameters.\n");
}

static bool load_settings_ini(const std::string &path, BenchmarkConfig &cfg)
{
    // Minimal .ini parser for keys under [Options]
    // Keys: SkillLevel, MoveTime, Algorithm, UsePerfectDatabase,
    // PerfectDatabasePath, IDS, DepthExtension, OpeningBook, Shuffling
    FILE *fp = nullptr;
#ifdef _WIN32
    if (fopen_s(&fp, path.c_str(), "rb") != 0) {
        fp = nullptr;
    }
#else
    fp = fopen(path.c_str(), "rb");
#endif
    if (!fp) {
        // Auto-generate default settings.ini if it doesn't exist
        create_default_settings_ini(path);
        return false; // Indicate that file was just created
    }
    char line[1024];
    bool inOptions = false;
    while (fgets(line, sizeof(line), fp)) {
        std::string s(line);
        // Trim CR/LF
        while (!s.empty() && (s.back() == '\r' || s.back() == '\n'))
            s.pop_back();
        if (s.empty() || s[0] == ';' || s[0] == '#')
            continue;
        if (s.front() == '[' && s.back() == ']') {
            std::string sec = s.substr(1, s.size() - 2);
            inOptions = (sec == "Options");
            continue;
        }
        if (!inOptions)
            continue;
        auto pos = s.find('=');
        if (pos == std::string::npos)
            continue;
        std::string key = s.substr(0, pos);
        std::string val = s.substr(pos + 1);
        auto to_bool = [](const std::string &x) {
            return x == "1" || x == "true" || x == "True" || x == "TRUE";
        };
        if (key == "TotalGames")
            cfg.totalGames = clamp_min(parse_int_safe(val, cfg.totalGames), 0);
        else if (key == "SkillLevel")
            // Clamp skill level to valid range (1-30)
            cfg.skillLevel = clamp_range(parse_int_safe(val, cfg.skillLevel), 1,
                                         30);
        else if (key == "MoveTime")
            cfg.moveTimeSec = clamp_min(parse_int_safe(val, cfg.moveTimeSec),
                                        0);
        else if (key == "Algorithm")
            // Fix: Clamp algorithm to valid range (0-4)
            cfg.algorithm = clamp_range(parse_int_safe(val, cfg.algorithm), 0,
                                        4);
        else if (key == "UsePerfectDatabase")
            cfg.usePerfectDb = to_bool(val);
        else if (key == "PerfectDatabasePath")
            cfg.perfectDbPath = val;
        else if (key == "Shuffling")
            cfg.shuffling = to_bool(val);
        else if (key == "IDS")
            cfg.idsEnabled = to_bool(val);
        else if (key == "DepthExtension")
            cfg.depthExtension = to_bool(val);
        else if (key == "OpeningBook")
            cfg.openingBook = to_bool(val);
        else if (key == "NMoveRule")
            // Clamp N-move rule to valid range (10-200)
            cfg.nMoveRule = clamp_range(parse_int_safe(val, cfg.nMoveRule), 10,
                                        200);
        // Additional options that may not be in Flutter UI
        else if (key == "AiIsLazy") { /* handled in apply_config via gameOptions
                                       */
        } else if (key == "AutoRestart") { /* handled in apply_config via
                                              gameOptions */
        } else if (key == "AutoChangeFirstMove") { /* handled in apply_config
                                                      via gameOptions */
        } else if (key == "ResignIfMostLose") { /* handled in apply_config via
                                                   gameOptions */
        } else if (key == "LearnEndgameEnabled") {   /* handled in apply_config
                                                        via gameOptions */
        } else if (key == "DrawOnHumanExperience") { /* handled in apply_config
                                                        via gameOptions */
        } else if (key == "ConsiderMobility") { /* handled in apply_config via
                                                   gameOptions */
        } else if (key == "FocusOnBlockingPaths") { /* handled in apply_config
                                                       via gameOptions */
        } else if (key == "TrapAwareness") { /* handled in apply_config via
                                                gameOptions */
        } else if (key == "DeveloperMode") { /* handled in apply_config via
                                                gameOptions */
        }
    }
    fclose(fp);
    return true; // Successfully loaded existing file
}

struct MatchResult
{
    // 1 for white wins, -1 for black wins, 0 for draw
    int outcome {0};
};

static int play_game_trad_vs_perfect(Color tradSide, const BenchmarkConfig &cfg,
                                     int gameId, ThreadStats &stats)
{
    (void)gameId; // Suppress unused parameter warning
    (void)cfg;    // Suppress unused parameter warning
    // tradSide indicates which color uses traditional search; the other uses
    // perfect DB.
    //
    // CRITICAL THREAD SAFETY ISSUE: This function is called from multiple
    // threads simultaneously, and there's a potential race condition:
    //
    // PROBLEM: Each thread creates its own SearchEngine, but traditional search
    // algorithms (Alpha-Beta, PVS, MTD(f)) may compete for the SAME global
    // Threads pool. Only MCTS algorithm creates its own threads and is truly
    // thread-safe.
    //
    // MITIGATION: We ensure thread safety by:
    // 1. Using local variables for all game state (pos, localPosKeyHistory,
    // tradEngine)
    // 2. Not accessing global posKeyHistory (using localPosKeyHistory instead)
    // 3. Each thread has its own SearchEngine instance
    // 4. Perfect DB calls are stateless and thread-safe
    // 5. IMPORTANT: For non-MCTS algorithms, there may still be global thread
    // pool contention

    EngineCommands::init_start_fen();
    Position pos;
    pos.set(EngineCommands::StartFEN);

    // Use thread-local position key history to avoid race conditions with
    // global posKeyHistory
    std::vector<Key> localPosKeyHistory;
    localPosKeyHistory.clear();

    SearchEngine tradEngine;
    tradEngine.setRootPosition(&pos);

    int moveCount = 0;
    const int MAX_MOVES_PER_GAME = 500;  // Prevent infinite games
    int consecutiveNonProgressMoves = 0; // Track moves without progress
    Phase lastPhase = pos.get_phase();

    while (pos.get_phase() != Phase::gameOver) {
        // Check for critical errors before each move
        if (g_critical_error.load()) {
            return 0; // Stop game immediately
        }

        // Prevent infinite games - but report the issue
        if (++moveCount > MAX_MOVES_PER_GAME) {
            SAFE_LOG(std::cerr, "WARNING: Game exceeded maximum moves ("
                                    << MAX_MOVES_PER_GAME << "). Game "
                                    << gameId << "\n"
                                    << "Position FEN: " << pos.fen() << "\n"
                                    << "Thread: "
                                    << (tradSide == WHITE ? "A (Trad=White)" :
                                                            "B (Trad=Black)")
                                    << "\n"
                                    << "This may indicate insufficient "
                                       "termination conditions.\n");
            stats.timeouts.fetch_add(1);
            // Treat as draw but expose the long game issue
            return 0;
        }

        const Color toMove = pos.side_to_move();

        if (toMove == tradSide) {
            // Traditional search move

            // CRITICAL: Ensure traditional AI always uses the configured
            // algorithm Perfect DB branch temporarily changes
            // gameOptions.algorithm to Random (4) We must restore the correct
            // algorithm before traditional search to avoid race conditions
            gameOptions.setAlgorithm(cfg.algorithm);

            tradEngine.setRootPosition(&pos); // Update position for engine
            uint64_t sid = tradEngine.beginNewSearch(&pos);
            (void)sid;

            // SOLUTION: Configure single-threaded search to avoid thread pool
            // contention Instead of serializing with mutex (which kills
            // performance), we ensure each SearchEngine uses only 1 thread,
            // eliminating competition for the global pool. This maintains true
            // parallelism while avoiding resource conflicts.

            tradEngine.runSearch();

            // Check results after synchronous completion
            {
                std::unique_lock<std::mutex> engine_lock(
                    tradEngine.bestMoveMutex);

                // Check for interruption
                if (g_interrupted)
                    return 0;

                if (pos.get_phase() == Phase::gameOver)
                    break;

                if (!tradEngine.bestMoveReady) {
                    // Critical error: search engine failed to produce a move
                    // This indicates a serious engine malfunction
                    std::ostringstream error_msg;
                    error_msg << "CRITICAL ENGINE ERROR: Traditional search "
                                 "did not produce a move!\n"
                              << "Game: " << gameId << ", Move: " << moveCount
                              << "\n"
                              << "Position FEN: " << pos.fen() << "\n"
                              << "Thread: "
                              << (tradSide == WHITE ? "A (Trad=White)" :
                                                      "B (Trad=Black)")
                              << "\n"
                              << "This indicates a serious engine malfunction "
                                 "that requires immediate attention.";

                    stats.errors.fetch_add(1);
                    set_critical_error(error_msg.str());
                    return 0; // Stop game immediately
                }

                Move best = tradEngine.bestMove;
                tradEngine.bestMoveReady = false;
                engine_lock.unlock();

                if (best == MOVE_NONE || best == MOVE_NULL) {
                    // Critical error: invalid move returned
                    std::ostringstream error_msg;
                    error_msg
                        << "CRITICAL ENGINE ERROR: Traditional search returned "
                           "invalid move!\n"
                        << "Game: " << gameId << ", Move: " << moveCount << "\n"
                        << "Position FEN: " << pos.fen() << "\n"
                        << "Returned move: "
                        << (best == MOVE_NONE ? "MOVE_NONE" : "MOVE_NULL")
                        << "\n"
                        << "Thread: "
                        << (tradSide == WHITE ? "A (Trad=White)" :
                                                "B (Trad=Black)")
                        << "\n"
                        << "Game phase: " << static_cast<int>(pos.get_phase())
                        << "\n"
                        << "This indicates a serious engine logic error.";

                    stats.errors.fetch_add(1);
                    set_critical_error(error_msg.str());
                    return 0; // Stop game immediately
                }

                // Validate move before executing
                if (!pos.legal(best)) {
                    std::ostringstream error_msg;
                    error_msg << "CRITICAL ENGINE ERROR: Traditional search "
                                 "returned illegal move!\n"
                              << "Game: " << gameId << ", Move: " << moveCount
                              << "\n"
                              << "Position FEN: " << pos.fen() << "\n"
                              << "Illegal move: " << UCI::move(best) << "\n"
                              << "Thread: "
                              << (tradSide == WHITE ? "A (Trad=White)" :
                                                      "B (Trad=Black)")
                              << "\n"
                              << "This indicates a serious move generation or "
                                 "validation error.";

                    stats.errors.fetch_add(1);
                    set_critical_error(error_msg.str());
                    return 0; // Stop game immediately
                }

                pos.do_move(best);

                // CRITICAL: do_move() doesn't call check_if_game_is_over()
                // We must manually check for game termination conditions after
                // each move This is essential because do_move() is a low-level
                // function that only executes the move without checking for
                // game-ending conditions like stalemate, insufficient pieces,
                // etc.
                pos.check_if_game_is_over();

                // Update local position history for repetition detection
                // CRITICAL: Use MoveType directly instead of record string, as
                // record may not be reliable in benchmark context. This aligns
                // with the core logic: only MOVETYPE_MOVE contributes to
                // position history.
                const MoveType mt = type_of(best);

                // Debug: Always log move type and repetition rule status
                SAFE_LOG(std::cout, "DEBUG: Traditional AI branch, moveType="
                                        << static_cast<int>(mt) << " (MOVE="
                                        << static_cast<int>(MOVETYPE_MOVE)
                                        << ") threefoldRule="
                                        << (rule.threefoldRepetitionRule ? "tru"
                                                                           "e" :
                                                                           "fal"
                                                                           "se")
                                        << " (move " << moveCount << ")\n");

                if (mt == MOVETYPE_MOVE) {
                    // This is a MOVETYPE_MOVE - check for threefold repetition
                    if (rule.threefoldRepetitionRule) {
                        const Key currentKey = pos.key();
                        ptrdiff_t count = std::count(localPosKeyHistory.begin(),
                                                     localPosKeyHistory.end(),
                                                     currentKey);
                        // Add 1 for current position to get total count
                        count += 1;

                        // Debug: Log repetition tracking for verification
                        SAFE_LOG(std::cout,
                                 "DEBUG: Traditional AI - Position key "
                                     << std::hex << currentKey << std::dec
                                     << " count=" << count << " historySize="
                                     << localPosKeyHistory.size() << " (move "
                                     << moveCount << ")\n");

                        if (count >= 3) {
                            SAFE_LOG(
                                std::cout,
                                "Threefold repetition detected: position key "
                                    << std::hex << currentKey << std::dec
                                    << " occurred " << count << " times. Game "
                                    << gameId << ", Move " << moveCount << "\n"
                                    << "Position FEN: " << pos.fen() << "\n"
                                    << "Thread: "
                                    << (tradSide == WHITE ? "A (Trad=White)" :
                                                            "B (Trad=Black)")
                                    << "\n");
                            stats.repetitions.fetch_add(1);
                            pos.set_gameover(
                                DRAW, GameOverReason::drawThreefoldRepetition);

                            // Update move statistics before returning (early
                            // exit due to repetition)
                            stats.totalMoves.fetch_add(moveCount);
                            uint64_t oldMax = stats.maxMovesInGame.load();
                            while (static_cast<uint64_t>(moveCount) > oldMax &&
                                   !stats.maxMovesInGame.compare_exchange_weak(
                                       oldMax, moveCount)) {
                            }
                            return 0;
                        }
                    }
                    localPosKeyHistory.push_back(pos.key());
                    consecutiveNonProgressMoves++;
                } else {
                    // This is MOVETYPE_PLACE or MOVETYPE_REMOVE - clear history
                    localPosKeyHistory.clear();
                    consecutiveNonProgressMoves = 0;
                }

                // THREAD-SAFE 50-RULE CHECK: Since
                // Position::check_if_game_is_over() uses global posKeyHistory
                // which is not thread-safe in benchmark, we implement our own
                // 50-rule check using consecutiveNonProgressMoves counter
                if (cfg.nMoveRule > 0 && pos.get_phase() != Phase::gameOver) {
                    // Count consecutive non-capture moves (MOVETYPE_MOVE only)
                    if (consecutiveNonProgressMoves >= cfg.nMoveRule) {
                        SAFE_LOG(std::cout,
                                 "50-move rule triggered: "
                                     << consecutiveNonProgressMoves
                                     << " consecutive moves without capture. "
                                        "Game "
                                     << gameId << "\n"
                                     << "Thread: "
                                     << (tradSide == WHITE ? "A (Trad=White)" :
                                                             "B (Trad=Black)")
                                     << "\n");
                        stats.fiftyMoveRuleDraws.fetch_add(1);
                        pos.set_gameover(DRAW, GameOverReason::drawFiftyMove);

                        // Update move statistics before returning (early exit
                        // due to 50-move rule)
                        stats.totalMoves.fetch_add(moveCount);
                        uint64_t oldMax = stats.maxMovesInGame.load();
                        while (static_cast<uint64_t>(moveCount) > oldMax &&
                               !stats.maxMovesInGame.compare_exchange_weak(
                                   oldMax, moveCount)) {
                        }
                        return 0; // Draw due to 50-move rule
                    }

                    // Check endgame 50-move rule if applicable
                    if (static_cast<int>(rule.endgameNMoveRule) <
                            cfg.nMoveRule &&
                        pos.is_three_endgame() &&
                        consecutiveNonProgressMoves >=
                            static_cast<int>(rule.endgameNMoveRule)) {
                        SAFE_LOG(std::cout,
                                 "Endgame 50-move rule triggered: "
                                     << consecutiveNonProgressMoves
                                     << " consecutive moves in endgame. Game "
                                     << gameId << "\n"
                                     << "Thread: "
                                     << (tradSide == WHITE ? "A (Trad=White)" :
                                                             "B (Trad=Black)")
                                     << "\n");
                        stats.endgameFiftyMoveRuleDraws.fetch_add(1);
                        pos.set_gameover(DRAW,
                                         GameOverReason::drawEndgameFiftyMove);

                        // Update move statistics before returning (early exit
                        // due to endgame 50-move rule)
                        stats.totalMoves.fetch_add(moveCount);
                        uint64_t oldMax = stats.maxMovesInGame.load();
                        while (static_cast<uint64_t>(moveCount) > oldMax &&
                               !stats.maxMovesInGame.compare_exchange_weak(
                                   oldMax, moveCount)) {
                        }
                        return 0; // Draw due to endgame 50-move rule
                    }
                }

                // Check for phase change (game progression)
                if (pos.get_phase() != lastPhase) {
                    lastPhase = pos.get_phase();
                    consecutiveNonProgressMoves = 0; // Reset on phase change
                }
            }

        } else {
            // Perfect DB move - pure database lookup, NO FALLBACK
            Move best = MOVE_NONE;

#ifdef GABOR_MALOM_PERFECT_AI
            // BENCHMARK OPTIMIZATION: Force Perfect DB to use Random algorithm
            // for optimal move selection (fastest win, delayed loss).
            // Traditional AI uses the configured algorithm, but Perfect DB
            // should always use Random algorithm to select the best move based
            // on step count.
            const int originalAlgorithm = gameOptions.getAlgorithm();
            const bool originalAiIsLazy = gameOptions.getAiIsLazy();

            // Temporarily override to Random algorithm with non-lazy mode
            // This ensures Perfect DB considers step count for move selection:
            // - Win: choose fastest victory (minimum steps)
            // - Loss: choose delayed defeat (maximum steps)
            gameOptions.setAlgorithm(4);    // Force Random algorithm
            gameOptions.setAiIsLazy(false); // Ensure step count optimization

            Value v = perfect_search(&pos, best);

            // Restore original algorithm settings for traditional AI
            gameOptions.setAlgorithm(originalAlgorithm);
            gameOptions.setAiIsLazy(originalAiIsLazy);
            if (v == VALUE_UNKNOWN) {
                // Perfect DB failure - this should not happen in benchmark
                std::ostringstream error_msg;
                error_msg << "CRITICAL PERFECT DB ERROR: Perfect DB returned "
                             "VALUE_UNKNOWN!\n"
                          << "Game: " << gameId << ", Move: " << moveCount
                          << "\n"
                          << "Position FEN: " << pos.fen() << "\n"
                          << "Thread: "
                          << (tradSide == WHITE ? "A (Trad=White)" :
                                                  "B (Trad=Black)")
                          << "\n"
                          << "Perfect DB should never return VALUE_UNKNOWN in "
                             "benchmark.\n"
                          << "This indicates database corruption or missing "
                             "positions.";

                stats.errors.fetch_add(1);
                set_critical_error(error_msg.str());
                return 0; // Stop game immediately
            }

            // OPTIMIZATION: Early termination on decisive evaluation
            // Perfect DB returns VALUE_MATE/VALUE_MATE from current player's
            // perspective:
            // - VALUE_MATE means current player (Perfect DB) wins
            // - -VALUE_MATE means current player (Perfect DB) loses
            if (v == VALUE_MATE || v == -VALUE_MATE) {
                // Determine winner: Perfect DB is the current player (toMove)
                const Color perfectDbColor = toMove; // Perfect DB is making
                                                     // this move
                const Color winnerColor = (v == VALUE_MATE) ? perfectDbColor :
                                                              ~perfectDbColor;
                const std::string winnerName = (winnerColor == WHITE) ? "Whit"
                                                                        "e" :
                                                                        "Black";
                const std::string perfectDbColorName = (perfectDbColor ==
                                                        WHITE) ?
                                                           "White" :
                                                           "Black";
                const std::string moveNotation = (best != MOVE_NONE) ?
                                                     UCI::move(best) :
                                                     "NONE";

                // Log concise, source-of-truth details
                SAFE_LOG(std::cout,
                         "Early termination: Perfect DB evaluation is "
                         "decisive. Game "
                             << gameId << ", Move " << moveCount << "\n"
                             << "Winner: " << winnerName << "\n"
                             << "Perfect DB side: " << perfectDbColorName
                             << "\n"
                             << "Perfect DB move: " << moveNotation << "\n"
                             << "Position FEN: " << pos.fen() << "\n"
                             << "Perfect DB evaluation: " << v
                             << (v == VALUE_MATE ? " (VALUE_MATE - Perfect DB "
                                                   "wins)" :
                                                   " (-VALUE_MATE - Perfect DB "
                                                   "loses)")
                             << "\n"
                             << "Thread: "
                             << (tradSide == WHITE ? "A (Trad=White)" :
                                                     "B (Trad=Black)")
                             << "\n");

                // Count early decisive termination (reuse existing counter)
                stats.earlyWinTerminations.fetch_add(1);

                // Update move statistics before returning (since we exit early)
                stats.totalMoves.fetch_add(moveCount);
                uint64_t oldMax = stats.maxMovesInGame.load();
                while (static_cast<uint64_t>(moveCount) > oldMax &&
                       !stats.maxMovesInGame.compare_exchange_weak(oldMax,
                                                                   moveCount)) {
                }

                // Return W/D/L from the actual winner color
                return (winnerColor == WHITE) ? 1 : -1;
            }

            // Early draw termination policy (narrowed):
            // Only consider draw-shortcut in moving phase when the endgame
            // material pattern is typical and database declares a draw.
            // Conditions:
            // - Phase must be moving (not placing)
            // - One side has exactly 3 stones on board
            // - The other side has fewer than 7 stones (i.e. 6,5,4,3)
            // - Perfect DB evaluation for current position is VALUE_DRAW
            if (pos.get_phase() == Phase::moving) {
                const int whitePieces = pos.piece_on_board_count(WHITE);
                const int blackPieces = pos.piece_on_board_count(BLACK);
                const bool threeVsLessSeven = (whitePieces == 3 &&
                                               blackPieces < 7) ||
                                              (blackPieces == 3 &&
                                               whitePieces < 7);

                if (threeVsLessSeven && v == VALUE_DRAW) {
                    SAFE_LOG(std::cout,
                             "Early draw termination: moving phase, one side "
                             "has 3 pieces and the other has <7. Game "
                                 << gameId << ", Move " << moveCount << "\n"
                                 << "White pieces: " << whitePieces
                                 << ", Black pieces: " << blackPieces << "\n"
                                 << "Perfect DB evaluation: VALUE_DRAW\n"
                                 << "Thread: "
                                 << (tradSide == WHITE ? "A (Trad=White)" :
                                                         "B (Trad=Black)")
                                 << "\n");

                    stats.earlyDrawTerminations.fetch_add(1);
                    // Update move statistics before returning (early exit)
                    stats.totalMoves.fetch_add(moveCount);
                    uint64_t oldMax2 = stats.maxMovesInGame.load();
                    while (static_cast<uint64_t>(moveCount) > oldMax2 &&
                           !stats.maxMovesInGame.compare_exchange_weak(
                               oldMax2, moveCount)) {
                    }
                    return 0; // Draw
                }
            }
            if (best == MOVE_NONE) {
                // Perfect DB failed to return a move
                std::ostringstream error_msg;
                error_msg << "CRITICAL PERFECT DB ERROR: Perfect DB returned "
                             "MOVE_NONE!\n"
                          << "Game: " << gameId << ", Move: " << moveCount
                          << "\n"
                          << "Position FEN: " << pos.fen() << "\n"
                          << "Perfect DB Value: " << v << "\n"
                          << "Thread: "
                          << (tradSide == WHITE ? "A (Trad=White)" :
                                                  "B (Trad=Black)")
                          << "\n"
                          << "Perfect DB returned a value but no move - "
                             "database inconsistency.";

                stats.errors.fetch_add(1);
                set_critical_error(error_msg.str());
                return 0; // Stop game immediately
            }
#else
            std::cerr << "CRITICAL: Perfect DB not compiled in! Game " << gameId
                      << ", Move " << moveCount << std::endl;
            std::cerr << "Thread: "
                      << (tradSide == WHITE ? "A (Trad=White)" :
                                              "B (Trad=Black)")
                      << std::endl;
            // Fatal compilation error
            std::abort();
#endif

            // Validate Perfect DB move before executing
            if (!pos.legal(best)) {
                std::ostringstream error_msg;
                error_msg << "CRITICAL PERFECT DB ERROR: Perfect DB returned "
                             "illegal move!\n"
                          << "Game: " << gameId << ", Move: " << moveCount
                          << "\n"
                          << "Position FEN: " << pos.fen() << "\n"
                          << "Illegal move: " << UCI::move(best) << "\n"
                          << "Thread: "
                          << (tradSide == WHITE ? "A (Trad=White)" :
                                                  "B (Trad=Black)")
                          << "\n"
                          << "Perfect DB should never return illegal moves - "
                             "database corruption.";

                stats.errors.fetch_add(1);
                set_critical_error(error_msg.str());
                return 0; // Stop game immediately
            }

            pos.do_move(best);

            // CRITICAL: do_move() doesn't call check_if_game_is_over()
            // We must manually check for game termination conditions after each
            // move This is essential because do_move() is a low-level function
            // that only executes the move without checking for game-ending
            // conditions like stalemate, insufficient pieces, etc.
            pos.check_if_game_is_over();

            // Update local position history for repetition detection
            // CRITICAL: Use MoveType directly instead of record string, as
            // record may not be reliable in benchmark context. This aligns with
            // the core logic: only MOVETYPE_MOVE contributes to position
            // history.
            const MoveType mt = type_of(best);

            // Debug: Always log move type and repetition rule status
            SAFE_LOG(std::cout,
                     "DEBUG: Perfect DB branch, moveType="
                         << static_cast<int>(mt)
                         << " (MOVE=" << static_cast<int>(MOVETYPE_MOVE)
                         << ") threefoldRule="
                         << (rule.threefoldRepetitionRule ? "true" : "false")
                         << " (move " << moveCount << ")\n");

            if (mt == MOVETYPE_MOVE) {
                // This is a MOVETYPE_MOVE - check for threefold repetition
                if (rule.threefoldRepetitionRule) {
                    const Key currentKey = pos.key();
                    ptrdiff_t count = std::count(localPosKeyHistory.begin(),
                                                 localPosKeyHistory.end(),
                                                 currentKey);
                    // Add 1 for current position to get total count
                    count += 1;

                    // Debug: Log repetition tracking for verification
                    SAFE_LOG(std::cout,
                             "DEBUG: Perfect DB - Position key "
                                 << std::hex << currentKey << std::dec
                                 << " count=" << count
                                 << " historySize=" << localPosKeyHistory.size()
                                 << " (move " << moveCount << ")\n");

                    if (count >= 3) {
                        SAFE_LOG(std::cout,
                                 "Threefold repetition detected: position key "
                                     << std::hex << currentKey << std::dec
                                     << " occurred " << count << " times. Game "
                                     << gameId << ", Move " << moveCount << "\n"
                                     << "Position FEN: " << pos.fen() << "\n"
                                     << "Thread: "
                                     << (tradSide == WHITE ? "A (Trad=White)" :
                                                             "B (Trad=Black)")
                                     << "\n");
                        stats.repetitions.fetch_add(1);
                        pos.set_gameover(
                            DRAW, GameOverReason::drawThreefoldRepetition);

                        // Update move statistics before returning (early exit
                        // due to repetition)
                        stats.totalMoves.fetch_add(moveCount);
                        uint64_t oldMax = stats.maxMovesInGame.load();
                        while (static_cast<uint64_t>(moveCount) > oldMax &&
                               !stats.maxMovesInGame.compare_exchange_weak(
                                   oldMax, moveCount)) {
                        }
                        return 0;
                    }
                }
                localPosKeyHistory.push_back(pos.key());
                consecutiveNonProgressMoves++;
            } else {
                // This is MOVETYPE_PLACE or MOVETYPE_REMOVE - clear history
                localPosKeyHistory.clear();
                consecutiveNonProgressMoves = 0;
            }

            // THREAD-SAFE 50-RULE CHECK: Since
            // Position::check_if_game_is_over() uses global posKeyHistory which
            // is not thread-safe in benchmark, we implement our own 50-rule
            // check using consecutiveNonProgressMoves counter
            if (cfg.nMoveRule > 0 && pos.get_phase() != Phase::gameOver) {
                // Count consecutive non-capture moves (MOVETYPE_MOVE only)
                if (consecutiveNonProgressMoves >= cfg.nMoveRule) {
                    SAFE_LOG(std::cout, "50-move rule triggered: "
                                            << consecutiveNonProgressMoves
                                            << " consecutive moves without "
                                               "capture. Game "
                                            << gameId << "\n"
                                            << "Thread: "
                                            << (tradSide == WHITE ? "A "
                                                                    "(Trad="
                                                                    "White)" :
                                                                    "B "
                                                                    "(Trad="
                                                                    "Black)")
                                            << "\n");
                    stats.fiftyMoveRuleDraws.fetch_add(1);
                    pos.set_gameover(DRAW, GameOverReason::drawFiftyMove);

                    // Update move statistics before returning (early exit due
                    // to 50-move rule)
                    stats.totalMoves.fetch_add(moveCount);
                    uint64_t oldMax = stats.maxMovesInGame.load();
                    while (static_cast<uint64_t>(moveCount) > oldMax &&
                           !stats.maxMovesInGame.compare_exchange_weak(
                               oldMax, moveCount)) {
                    }
                    return 0; // Draw due to 50-move rule
                }

                // Check endgame 50-move rule if applicable
                if (static_cast<int>(rule.endgameNMoveRule) < cfg.nMoveRule &&
                    pos.is_three_endgame() &&
                    consecutiveNonProgressMoves >=
                        static_cast<int>(rule.endgameNMoveRule)) {
                    SAFE_LOG(std::cout, "Endgame 50-move rule triggered: "
                                            << consecutiveNonProgressMoves
                                            << " consecutive moves in endgame. "
                                               "Game "
                                            << gameId << "\n"
                                            << "Thread: "
                                            << (tradSide == WHITE ? "A "
                                                                    "(Trad="
                                                                    "White)" :
                                                                    "B "
                                                                    "(Trad="
                                                                    "Black)")
                                            << "\n");
                    stats.endgameFiftyMoveRuleDraws.fetch_add(1);
                    pos.set_gameover(DRAW,
                                     GameOverReason::drawEndgameFiftyMove);

                    // Update move statistics before returning (early exit due
                    // to endgame 50-move rule)
                    stats.totalMoves.fetch_add(moveCount);
                    uint64_t oldMax = stats.maxMovesInGame.load();
                    while (static_cast<uint64_t>(moveCount) > oldMax &&
                           !stats.maxMovesInGame.compare_exchange_weak(
                               oldMax, moveCount)) {
                    }
                    return 0; // Draw due to endgame 50-move rule
                }
            }

            // Check for phase change (game progression)
            if (pos.get_phase() != lastPhase) {
                lastPhase = pos.get_phase();
                consecutiveNonProgressMoves = 0; // Reset on phase change
            }
        }

        // Check for excessive non-progress moves (possible stalemate)
        const int MAX_NON_PROGRESS_MOVES = 100;
        if (consecutiveNonProgressMoves > MAX_NON_PROGRESS_MOVES) {
            std::cerr << "WARNING: Excessive non-progress moves detected ("
                      << consecutiveNonProgressMoves << "). Game " << gameId
                      << std::endl;
            std::cerr << "Position FEN: " << pos.fen() << std::endl;
            stats.timeouts.fetch_add(1);
            return 0; // Treat as draw
        }
    }

    // Track game statistics
    stats.totalMoves.fetch_add(moveCount);
    // Update max moves atomically
    uint64_t oldMax = stats.maxMovesInGame.load();
    while (static_cast<uint64_t>(moveCount) > oldMax &&
           !stats.maxMovesInGame.compare_exchange_weak(oldMax, moveCount)) {
        // Keep trying until successful
    }

    Color winner = pos.get_winner();
    if (winner == WHITE)
        return 1;
    else if (winner == BLACK)
        return -1;
    else
        return 0; // Draw
}

static void print_stats(const char *title, const ThreadStats &st)
{
    const uint64_t w = st.tradWins.load();
    const uint64_t l = st.perfectWins.load();
    const uint64_t d = st.draws.load();
    const uint64_t t = st.total.load();
    const uint64_t e = st.errors.load();
    const uint64_t to = st.timeouts.load();
    const uint64_t rep = st.repetitions.load();
    const uint64_t tm = st.totalMoves.load();
    const uint64_t mm = st.maxMovesInGame.load();
    const uint64_t ewt = st.earlyWinTerminations.load();
    const uint64_t edt = st.earlyDrawTerminations.load();
    const uint64_t fmr = st.fiftyMoveRuleDraws.load();
    const uint64_t efmr = st.endgameFiftyMoveRuleDraws.load();

    double wp = t ? (100.0 * w / t) : 0.0;
    double lp = t ? (100.0 * l / t) : 0.0;
    double dp = t ? (100.0 * d / t) : 0.0;
    double avgMoves = t ? (static_cast<double>(tm) / t) : 0.0;

    std::cout << title << " => TradW:" << w << " PerfW:" << l << " Draw:" << d
              << " | Games:" << t << " | Pct Trad:" << std::fixed
              << std::setprecision(2) << wp << "% Perf:" << lp
              << "% Draw:" << dp << "%";

    // Show additional statistics if any issues occurred
    if (e > 0 || to > 0 || rep > 0 || fmr > 0 || efmr > 0) {
        std::cout << " | Issues: Err:" << e << " TO:" << to << " Rep:" << rep;
        if (fmr > 0 || efmr > 0) {
            std::cout << " 50R:" << fmr << " E50R:" << efmr;
        }
    }

    // Show early termination statistics if any occurred
    if (ewt > 0 || edt > 0) {
        std::cout << " | Early: Win:" << ewt << " Draw:" << edt;
    }

    // Show move statistics
    std::cout << " | Moves: Avg:" << std::fixed << std::setprecision(1)
              << avgMoves << " Max:" << mm << "\n";
}

// Enhanced version that writes to both console and file
static void print_stats_to_file(std::ofstream &file, const char *title,
                                const ThreadStats &st)
{
    const uint64_t w = st.tradWins.load();
    const uint64_t l = st.perfectWins.load();
    const uint64_t d = st.draws.load();
    const uint64_t t = st.total.load();
    const uint64_t e = st.errors.load();
    const uint64_t to = st.timeouts.load();
    const uint64_t rep = st.repetitions.load();
    const uint64_t tm = st.totalMoves.load();
    const uint64_t mm = st.maxMovesInGame.load();
    const uint64_t ewt = st.earlyWinTerminations.load();
    const uint64_t edt = st.earlyDrawTerminations.load();
    const uint64_t fmr = st.fiftyMoveRuleDraws.load();
    const uint64_t efmr = st.endgameFiftyMoveRuleDraws.load();

    double wp = t ? (100.0 * w / t) : 0.0;
    double lp = t ? (100.0 * l / t) : 0.0;
    double dp = t ? (100.0 * d / t) : 0.0;
    double avgMoves = t ? (static_cast<double>(tm) / t) : 0.0;

    // Write to file with same format as console
    file << title << " => TradW:" << w << " PerfW:" << l << " Draw:" << d
         << " | Games:" << t << " | Pct Trad:" << std::fixed
         << std::setprecision(2) << wp << "% Perf:" << lp << "% Draw:" << dp
         << "%";

    // Show additional statistics if any issues occurred
    if (e > 0 || to > 0 || rep > 0 || fmr > 0 || efmr > 0) {
        file << " | Issues: Err:" << e << " TO:" << to << " Rep:" << rep;
        if (fmr > 0 || efmr > 0) {
            file << " 50R:" << fmr << " E50R:" << efmr;
        }
    }

    // Show early termination statistics if any occurred
    if (ewt > 0 || edt > 0) {
        file << " | Early: Win:" << ewt << " Draw:" << edt;
    }

    // Show move statistics
    file << " | Moves: Avg:" << std::fixed << std::setprecision(1) << avgMoves
         << " Max:" << mm << "\n";
}

static void print_overall(const ThreadStats &a, const ThreadStats &b)
{
    // Fix: Use .load() to properly read atomic values
    const uint64_t w = a.tradWins.load() + b.tradWins.load();
    const uint64_t l = a.perfectWins.load() + b.perfectWins.load();
    const uint64_t d = a.draws.load() + b.draws.load();
    const uint64_t t = a.total.load() + b.total.load();
    const uint64_t e = a.errors.load() + b.errors.load();
    const uint64_t to = a.timeouts.load() + b.timeouts.load();
    const uint64_t rep = a.repetitions.load() + b.repetitions.load();
    const uint64_t tm = a.totalMoves.load() + b.totalMoves.load();
    const uint64_t maxA = a.maxMovesInGame.load();
    const uint64_t maxB = b.maxMovesInGame.load();
    const uint64_t mm = maxA > maxB ? maxA : maxB;
    const uint64_t ewt = a.earlyWinTerminations.load() +
                         b.earlyWinTerminations.load();
    const uint64_t edt = a.earlyDrawTerminations.load() +
                         b.earlyDrawTerminations.load();
    const uint64_t fmr = a.fiftyMoveRuleDraws.load() +
                         b.fiftyMoveRuleDraws.load();
    const uint64_t efmr = a.endgameFiftyMoveRuleDraws.load() +
                          b.endgameFiftyMoveRuleDraws.load();

    double wp = t ? (100.0 * w / t) : 0.0;
    double lp = t ? (100.0 * l / t) : 0.0;
    double dp = t ? (100.0 * d / t) : 0.0;
    double avgMoves = t ? (static_cast<double>(tm) / t) : 0.0;

    std::cout << "Overall => TradW:" << w << " PerfW:" << l << " Draw:" << d
              << " | Games:" << t << " | Pct Trad:" << std::fixed
              << std::setprecision(2) << wp << "% Perf:" << lp
              << "% Draw:" << dp << "%";

    // Show additional statistics if any issues occurred
    if (e > 0 || to > 0 || rep > 0 || fmr > 0 || efmr > 0) {
        std::cout << "\n    Issues: Errors:" << e << " Timeouts:" << to
                  << " Repetitions:" << rep;
        if (fmr > 0 || efmr > 0) {
            std::cout << " 50-Rule:" << fmr << " Endgame-50-Rule:" << efmr;
        }
    }

    // Show early termination statistics if any occurred
    if (ewt > 0 || edt > 0) {
        std::cout << "\n    Early Terminations: Win:" << ewt << " Draw:" << edt;
        if (t > 0) {
            double ewtPct = (100.0 * ewt / t);
            double edtPct = (100.0 * edt / t);
            std::cout << " (Win:" << std::fixed << std::setprecision(1)
                      << ewtPct << "% Draw:" << edtPct << "%)";
        }
    }

    // Show move statistics
    std::cout << "\n    Moves: Avg:" << std::fixed << std::setprecision(1)
              << avgMoves << " Max:" << mm << "\n";

    // Show error distribution if errors occurred
    if (e > 0) {
        std::cout << "    Error Distribution: Thread A:" << a.errors.load()
                  << " Thread B:" << b.errors.load() << "\n";
    }

    // Detailed analysis by color
    std::cout << "\n=== Traditional AI Performance by Color ===\n";
    const uint64_t ta = a.total.load();
    const uint64_t tb = b.total.load();

    // Thread A: Traditional=White vs Perfect=Black
    double tradAsWhiteWinRate = ta ? (100.0 * a.tradWins.load() / ta) : 0.0;
    double tradAsWhiteDrawRate = ta ? (100.0 * a.draws.load() / ta) : 0.0;
    std::cout << "Traditional AI as WHITE: " << a.tradWins.load() << "W "
              << a.perfectWins.load() << "L " << a.draws.load() << "D" << " | "
              << ta << " games | WinRate:" << std::fixed << std::setprecision(2)
              << tradAsWhiteWinRate << "% DrawRate:" << tradAsWhiteDrawRate
              << "%\n";

    // Thread B: Traditional=Black vs Perfect=White
    double tradAsBlackWinRate = tb ? (100.0 * b.tradWins.load() / tb) : 0.0;
    double tradAsBlackDrawRate = tb ? (100.0 * b.draws.load() / tb) : 0.0;
    std::cout << "Traditional AI as BLACK: " << b.tradWins.load() << "W "
              << b.perfectWins.load() << "L " << b.draws.load() << "D" << " | "
              << tb << " games | WinRate:" << std::fixed << std::setprecision(2)
              << tradAsBlackWinRate << "% DrawRate:" << tradAsBlackDrawRate
              << "%\n";

    // Color-balanced analysis: Handle unequal game counts properly
    auto safe_pct = [](uint64_t x, uint64_t tot) -> double {
        return tot ?
                   (100.0 * static_cast<double>(x) / static_cast<double>(tot)) :
                   0.0;
    };

    // Check if game counts are significantly imbalanced (>10% difference)
    const uint64_t maxGames = ta > tb ? ta : tb;
    const uint64_t minGames = ta < tb ? ta : tb;
    const bool isImbalanced = (ta > 0 && tb > 0) &&
                              (maxGames > minGames + minGames / 10);

    if (isImbalanced) {
        std::cout << "\n[WARNING] Game Count Imbalance Detected (A:" << ta
                  << ", B:" << tb << ")\n";

        // Show both equal-weight and total-weight averages
        double wp_equal = (safe_pct(a.tradWins.load(), ta) +
                           safe_pct(b.tradWins.load(), tb)) /
                          2.0;
        double lp_equal = (safe_pct(a.perfectWins.load(), ta) +
                           safe_pct(b.perfectWins.load(), tb)) /
                          2.0;
        double dp_equal = (safe_pct(a.draws.load(), ta) +
                           safe_pct(b.draws.load(), tb)) /
                          2.0;

        std::cout << "Equal-Weight Average => Trad:" << std::fixed
                  << std::setprecision(2) << wp_equal << "% Perf:" << lp_equal
                  << "% Draw:" << dp_equal << "%\n";
        std::cout << "(Note: Equal weight given to each color, ignoring game "
                     "count difference)\n";

        // The "Overall" rates above already show the correct weighted average
        std::cout << "Weighted by Game Count => See 'Overall' rates above ("
                  << wp << "% / " << lp << "% / " << dp << "%)\n";
    } else {
        // Game counts are balanced, both methods give same result
        double wp_balanced = (safe_pct(a.tradWins.load(), ta) +
                              safe_pct(b.tradWins.load(), tb)) /
                             2.0;
        double lp_balanced = (safe_pct(a.perfectWins.load(), ta) +
                              safe_pct(b.perfectWins.load(), tb)) /
                             2.0;
        double dp_balanced = (safe_pct(a.draws.load(), ta) +
                              safe_pct(b.draws.load(), tb)) /
                             2.0;

        std::cout << "\n[OK] Balanced Game Counts => Trad:" << std::fixed
                  << std::setprecision(2) << wp_balanced
                  << "% Perf:" << lp_balanced << "% Draw:" << dp_balanced
                  << "%\n";
        std::cout << "(Equal-weight and game-count-weighted averages are "
                     "equivalent)\n";
    }
}

// Enhanced version that writes to file
static void print_overall_to_file(std::ofstream &file, const ThreadStats &a,
                                  const ThreadStats &b)
{
    // Use .load() to properly read atomic values
    const uint64_t w = a.tradWins.load() + b.tradWins.load();
    const uint64_t l = a.perfectWins.load() + b.perfectWins.load();
    const uint64_t d = a.draws.load() + b.draws.load();
    const uint64_t t = a.total.load() + b.total.load();
    const uint64_t e = a.errors.load() + b.errors.load();
    const uint64_t to = a.timeouts.load() + b.timeouts.load();
    const uint64_t rep = a.repetitions.load() + b.repetitions.load();
    const uint64_t tm = a.totalMoves.load() + b.totalMoves.load();
    const uint64_t maxA = a.maxMovesInGame.load();
    const uint64_t maxB = b.maxMovesInGame.load();
    const uint64_t mm = maxA > maxB ? maxA : maxB;
    const uint64_t ewt = a.earlyWinTerminations.load() +
                         b.earlyWinTerminations.load();
    const uint64_t edt = a.earlyDrawTerminations.load() +
                         b.earlyDrawTerminations.load();
    const uint64_t fmr = a.fiftyMoveRuleDraws.load() +
                         b.fiftyMoveRuleDraws.load();
    const uint64_t efmr = a.endgameFiftyMoveRuleDraws.load() +
                          b.endgameFiftyMoveRuleDraws.load();

    double wp = t ? (100.0 * w / t) : 0.0;
    double lp = t ? (100.0 * l / t) : 0.0;
    double dp = t ? (100.0 * d / t) : 0.0;
    double avgMoves = t ? (static_cast<double>(tm) / t) : 0.0;

    file << "Overall => TradW:" << w << " PerfW:" << l << " Draw:" << d
         << " | Games:" << t << " | Pct Trad:" << std::fixed
         << std::setprecision(2) << wp << "% Perf:" << lp << "% Draw:" << dp
         << "%";

    // Show additional statistics if any issues occurred
    if (e > 0 || to > 0 || rep > 0 || fmr > 0 || efmr > 0) {
        file << "\n    Issues: Errors:" << e << " Timeouts:" << to
             << " Repetitions:" << rep;
        if (fmr > 0 || efmr > 0) {
            file << " 50-Rule:" << fmr << " Endgame-50-Rule:" << efmr;
        }
    }

    // Show early termination statistics if any occurred
    if (ewt > 0 || edt > 0) {
        file << "\n    Early Terminations: Win:" << ewt << " Draw:" << edt;
        if (t > 0) {
            double ewtPct = (100.0 * ewt / t);
            double edtPct = (100.0 * edt / t);
            file << " (Win:" << std::fixed << std::setprecision(1) << ewtPct
                 << "% Draw:" << edtPct << "%)";
        }
    }

    // Show move statistics
    file << "\n    Moves: Avg:" << std::fixed << std::setprecision(1)
         << avgMoves << " Max:" << mm << "\n";

    // Show error distribution if errors occurred
    if (e > 0) {
        file << "    Error Distribution: Thread A:" << a.errors.load()
             << " Thread B:" << b.errors.load() << "\n";
    }

    // Detailed analysis by color
    file << "\n=== Traditional AI Performance by Color ===\n";
    const uint64_t ta = a.total.load();
    const uint64_t tb = b.total.load();

    // Thread A: Traditional=White vs Perfect=Black
    double tradAsWhiteWinRate = ta ? (100.0 * a.tradWins.load() / ta) : 0.0;
    double tradAsWhiteDrawRate = ta ? (100.0 * a.draws.load() / ta) : 0.0;
    file << "Traditional AI as WHITE: " << a.tradWins.load() << "W "
         << a.perfectWins.load() << "L " << a.draws.load() << "D" << " | " << ta
         << " games | WinRate:" << std::fixed << std::setprecision(2)
         << tradAsWhiteWinRate << "% DrawRate:" << tradAsWhiteDrawRate << "%\n";

    // Thread B: Traditional=Black vs Perfect=White
    double tradAsBlackWinRate = tb ? (100.0 * b.tradWins.load() / tb) : 0.0;
    double tradAsBlackDrawRate = tb ? (100.0 * b.draws.load() / tb) : 0.0;
    file << "Traditional AI as BLACK: " << b.tradWins.load() << "W "
         << b.perfectWins.load() << "L " << b.draws.load() << "D" << " | " << tb
         << " games | WinRate:" << std::fixed << std::setprecision(2)
         << tradAsBlackWinRate << "% DrawRate:" << tradAsBlackDrawRate << "%\n";

    // Color-balanced analysis: Handle unequal game counts properly
    auto safe_pct = [](uint64_t x, uint64_t tot) -> double {
        return tot ?
                   (100.0 * static_cast<double>(x) / static_cast<double>(tot)) :
                   0.0;
    };

    // Check if game counts are significantly imbalanced (>10% difference)
    const uint64_t maxGames = ta > tb ? ta : tb;
    const uint64_t minGames = ta < tb ? ta : tb;
    const bool isImbalanced = (ta > 0 && tb > 0) &&
                              (maxGames > minGames + minGames / 10);

    if (isImbalanced) {
        file << "\n[WARNING] Game Count Imbalance Detected (A:" << ta
             << ", B:" << tb << ")\n";

        // Show both equal-weight and total-weight averages
        double wp_equal = (safe_pct(a.tradWins.load(), ta) +
                           safe_pct(b.tradWins.load(), tb)) /
                          2.0;
        double lp_equal = (safe_pct(a.perfectWins.load(), ta) +
                           safe_pct(b.perfectWins.load(), tb)) /
                          2.0;
        double dp_equal = (safe_pct(a.draws.load(), ta) +
                           safe_pct(b.draws.load(), tb)) /
                          2.0;

        file << "Equal-Weight Average => Trad:" << std::fixed
             << std::setprecision(2) << wp_equal << "% Perf:" << lp_equal
             << "% Draw:" << dp_equal << "%\n";
        file << "(Note: Equal weight given to each color, ignoring game count "
                "difference)\n";

        // The "Overall" rates above already show the correct weighted average
        file << "Weighted by Game Count => See 'Overall' rates above (" << wp
             << "% / " << lp << "% / " << dp << "%)\n";
    } else {
        // Game counts are balanced, both methods give same result
        double wp_balanced = (safe_pct(a.tradWins.load(), ta) +
                              safe_pct(b.tradWins.load(), tb)) /
                             2.0;
        double lp_balanced = (safe_pct(a.perfectWins.load(), ta) +
                              safe_pct(b.perfectWins.load(), tb)) /
                             2.0;
        double dp_balanced = (safe_pct(a.draws.load(), ta) +
                              safe_pct(b.draws.load(), tb)) /
                             2.0;

        file << "\n[OK] Balanced Game Counts => Trad:" << std::fixed
             << std::setprecision(2) << wp_balanced << "% Perf:" << lp_balanced
             << "% Draw:" << dp_balanced << "%\n";
        file << "(Equal-weight and game-count-weighted averages are "
                "equivalent)\n";
    }
}

// Write current benchmark status to file (thread-safe)
static void write_benchmark_status_to_file(const BenchmarkConfig &cfg,
                                           const ThreadStats &statsA,
                                           const ThreadStats &statsB,
                                           const std::chrono::seconds &elapsed,
                                           const char *algName,
                                           bool isInitialWrite = false)
{
    std::lock_guard<std::mutex> file_lock(g_file_mutex);

    std::ofstream resultFile("benchmark-results.txt");
    if (!resultFile.is_open()) {
        return; // Silently fail to avoid spam
    }

    // Write header and configuration (always)
    auto now = std::chrono::system_clock::now();
    auto time_t = std::chrono::system_clock::to_time_t(now);
    resultFile << "Sanmill Benchmark Results (Live Update)\n";

    // Use safe time formatting
#ifdef _WIN32
    char timeStr[64];
    if (ctime_s(timeStr, sizeof(timeStr), &time_t) == 0) {
        resultFile << "Last Updated: " << timeStr;
    } else {
        resultFile << "Last Updated: [Time format error]\n";
    }
#else
    resultFile << "Last Updated: " << std::ctime(&time_t);
#endif

    if (isInitialWrite) {
        resultFile << "Status: RUNNING (Initial)\n";
    } else {
        resultFile << "Status: RUNNING (Live Update)\n";
    }
    resultFile << "Elapsed Time: " << elapsed.count() << " seconds\n";
    resultFile << "=========================\n\n";

    // Write configuration
    resultFile << "Configuration:\n";
    resultFile << "  Algorithm: " << cfg.algorithm << " (" << algName << ")\n";
    if (cfg.algorithm == 3) {
        resultFile << "  [OK] Thread Safety: Excellent (MCTS uses independent "
                      "threads)\n";
    } else {
        resultFile << "  [INFO] Thread Safety: Managed (single-threaded search "
                      "per engine)\n";
    }
    resultFile << "  Skill Level: " << cfg.skillLevel << "/30\n";
    resultFile << "  Move Time: " << cfg.moveTimeSec << " seconds\n";
    resultFile << "  IDS: " << (cfg.idsEnabled ? "enabled" : "disabled")
               << "\n";
    resultFile << "  Depth Extension: "
               << (cfg.depthExtension ? "enabled" : "disabled") << "\n";
    resultFile << "  Opening Book: "
               << (cfg.openingBook ? "enabled" : "disabled") << "\n";
    resultFile << "  Shuffling: " << (cfg.shuffling ? "enabled" : "disabled")
               << "\n";
    resultFile << "  N-move rule: " << cfg.nMoveRule << " moves\n";
    resultFile << "  Perfect DB Path: " << cfg.perfectDbPath << "\n\n";

    // Write current thread results
    resultFile << "Current Thread Results:\n";
    print_stats_to_file(resultFile, "Thread A (Traditional=White)", statsA);
    print_stats_to_file(resultFile, "Thread B (Traditional=Black)", statsB);

    resultFile << "\nCurrent Overall Summary:\n";
    print_overall_to_file(resultFile, statsA, statsB);

    // Write performance metrics if games completed
    const uint64_t totalGames = statsA.total.load() + statsB.total.load();
    if (elapsed.count() > 0 && totalGames > 0) {
        double gamesPerSecond = static_cast<double>(totalGames) /
                                elapsed.count();
        double avgGameTime = static_cast<double>(elapsed.count()) / totalGames;
        resultFile << "\nCurrent Performance:\n";
        resultFile << "  Elapsed Time: " << elapsed.count() << " seconds\n";
        resultFile << "  Games/Second: " << std::fixed << std::setprecision(2)
                   << gamesPerSecond << "\n";
        resultFile << "  Avg Game Time: " << std::fixed << std::setprecision(2)
                   << avgGameTime << " seconds\n";
    }

    // Write quality metrics if any issues occurred
    const uint64_t totalErrors = statsA.errors.load() + statsB.errors.load();
    const uint64_t totalTimeouts = statsA.timeouts.load() +
                                   statsB.timeouts.load();
    const uint64_t totalEarlyWins = statsA.earlyWinTerminations.load() +
                                    statsB.earlyWinTerminations.load();
    const uint64_t totalEarlyDraws = statsA.earlyDrawTerminations.load() +
                                     statsB.earlyDrawTerminations.load();

    if (totalErrors > 0 || totalTimeouts > 0) {
        resultFile << "\nCurrent Quality Issues:\n";
        if (totalErrors > 0) {
            resultFile << "  [WARNING] Engine Errors: " << totalErrors;
            if (totalGames > 0) {
                resultFile << " (" << std::fixed << std::setprecision(2)
                           << (100.0 * totalErrors / totalGames) << "%)";
            }
            resultFile << "\n";
        }
        if (totalTimeouts > 0) {
            resultFile << "  [WARNING] Game Timeouts: " << totalTimeouts;
            if (totalGames > 0) {
                resultFile << " (" << std::fixed << std::setprecision(2)
                           << (100.0 * totalTimeouts / totalGames) << "%)";
            }
            resultFile << "\n";
        }
    } else if (totalGames > 0) {
        resultFile << "\n[OK] No quality issues detected so far.\n";
    }

    // Write optimization metrics if any occurred
    if (totalEarlyWins > 0 || totalEarlyDraws > 0) {
        resultFile << "\nCurrent Optimization Statistics:\n";
        if (totalEarlyWins > 0) {
            resultFile << "  [INFO] Early Win Terminations: " << totalEarlyWins;
            if (totalGames > 0) {
                resultFile << " (" << std::fixed << std::setprecision(2)
                           << (100.0 * totalEarlyWins / totalGames) << "%)";
            }
            resultFile << "\n";
            resultFile << "    Perfect DB detected winning positions and "
                          "terminated games early\n";
        }
        if (totalEarlyDraws > 0) {
            resultFile << "  [INFO] Early Draw Terminations: "
                       << totalEarlyDraws;
            if (totalGames > 0) {
                resultFile << " (" << std::fixed << std::setprecision(2)
                           << (100.0 * totalEarlyDraws / totalGames) << "%)";
            }
            resultFile << "\n";
            resultFile << "    Moving phase: one side has 3 pieces, other side "
                          "has <7 pieces, Perfect DB shows draw\n";
        }
    }

    if (totalGames == 0) {
        resultFile << "\nNote: No games completed yet. Benchmark is "
                      "starting...\n";
    }

    resultFile.close();
}

static void ensure_engine_inited_once()
{
    static std::once_flag once;
    std::call_once(once, []() {
        UCI::init(Options);
        Bitboards::init();
        Position::init();

        // CRITICAL: Initialize rule BEFORE mills tables
        // Mills::adjacent_squares_init() depends on rule.hasDiagonalLines
        // Default to standard Nine Men's Morris (rule 0)
        set_rule(0);

        // CRITICAL: Configure thread pool for benchmark safety
        // Set to 1 thread to avoid competition between multiple SearchEngine
        // instances This ensures each benchmark thread gets consistent,
        // non-interfering search behavior
        const size_t benchmarkThreads = 1;
        std::cout << "INFO: Configuring thread pool for benchmark ("
                  << benchmarkThreads << " threads per SearchEngine)"
                  << std::endl;
        Threads.set(benchmarkThreads);

        Search::clear();
        EngineCommands::init_start_fen();

        // Initialize mills tables for proper game logic AFTER rule
        // initialization
        Mills::adjacent_squares_init();
        Mills::mill_table_init();
    });
}

static void print_help()
{
    std::cout << "benchmark options:\n"
              << "  --games N            Total games (0 = infinite; default "
                 "100)\n"
              << "  --movetime S         Thinking time per move in seconds "
                 "(0 = infinite; default 0)\n"
              << "  --skill L            Skill level (default 15)\n"
              << "  --algorithm K        0=AB,1=PVS,2=MTDf,3=MCTS,4=Random "
                 "(default 2)\n"
              << "  --ids (on|off)       Iterative deepening (default off)\n"
              << "  --depthext (on|off)  Depth extension (default on)\n"
              << "  --opening (on|off)   Opening book (default off)\n"
              << "  --shuffle (on|off)   Shuffle successors (default on)\n"
              << "  --nmove N            N-move rule for draw (10-200, default "
                 "100)\n"
              << "  --ini PATH           settings.ini to preload options\n"
              << "  --pd PATH            Perfect DB path (required)\n"
              << "\nPath examples:\n"
              << "  Windows: --pd \"C:\\\\DB\\\\Std\" or --pd C:/DB/Std\n"
              << "  Linux:   --pd /home/user/db/std\n"
              << "  Relative: --pd ./database or --pd ..\\\\parent\\\\db\n"
              << std::endl;
}

// Helper function to remove quotes from paths
static std::string unquote_path(std::string s)
{
    if (s.size() >= 2) {
        if ((s.front() == '"' && s.back() == '"') ||
            (s.front() == '\'' && s.back() == '\'')) {
            s = s.substr(1, s.size() - 2);
        }
    }
    return s;
}

static bool parse_onoff(const std::string &s, bool def)
{
    std::string lower = s;
    std::transform(lower.begin(), lower.end(), lower.begin(),
                   [](unsigned char c) {
                       return static_cast<char>(std::tolower(c));
                   });
    if (lower == "on" || lower == "1" || lower == "true")
        return true;
    if (lower == "off" || lower == "0" || lower == "false")
        return false;
    return def;
}

void run_from_cli(std::istream &is)
{
#ifdef ENABLE_BENCHMARK
    ensure_engine_inited_once();

    BenchmarkConfig cfg;

    // Parse command line tokens first to check for --ini parameter
    std::vector<std::string> tokens;
    std::string tok;
    bool hasArgs = false;
    std::string customIniPath;

    // First pass: collect all tokens and check for --ini
    while (is >> tok) {
        hasArgs = true;
        tokens.push_back(tok);
        if (tok == "--ini" && !tokens.empty()) {
            // Next token should be the INI path
            if (is >> tok) {
                customIniPath = unquote_path(tok);
                tokens.push_back(tok);
            }
        }
    }

    // Load INI file (either custom path or default)
    std::string iniPathToUse = customIniPath.empty() ? cfg.iniPath :
                                                       customIniPath;
    bool iniLoaded = load_settings_ini(iniPathToUse, cfg);

    // Second pass: process CLI arguments to override INI settings
    // CLI arguments now properly override INI settings
    for (size_t i = 0; i < tokens.size(); ++i) {
        const std::string &token = tokens[i];

        if (token == "--help" || token == "-h") {
            print_help();
            return;
        } else if (token == "--games" && i + 1 < tokens.size()) {
            cfg.totalGames = clamp_min(
                parse_int_safe(tokens[++i], cfg.totalGames), 0);
        } else if (token == "--movetime" && i + 1 < tokens.size()) {
            cfg.moveTimeSec = clamp_min(
                parse_int_safe(tokens[++i], cfg.moveTimeSec), 0);
        } else if (token == "--skill" && i + 1 < tokens.size()) {
            // Fix: Clamp skill level to valid range (1-30)
            cfg.skillLevel = clamp_range(
                parse_int_safe(tokens[++i], cfg.skillLevel), 1, 30);
        } else if (token == "--algorithm" && i + 1 < tokens.size()) {
            // Fix: Clamp algorithm to valid range (0=AlphaBeta, 1=PVS, 2=MTDf,
            // 3=MCTS, 4=Random)
            cfg.algorithm = clamp_range(
                parse_int_safe(tokens[++i], cfg.algorithm), 0, 4);
        } else if (token == "--ids" && i + 1 < tokens.size()) {
            cfg.idsEnabled = parse_onoff(tokens[++i], cfg.idsEnabled);
        } else if (token == "--depthext" && i + 1 < tokens.size()) {
            cfg.depthExtension = parse_onoff(tokens[++i], cfg.depthExtension);
        } else if (token == "--opening" && i + 1 < tokens.size()) {
            cfg.openingBook = parse_onoff(tokens[++i], cfg.openingBook);
        } else if (token == "--shuffle" && i + 1 < tokens.size()) {
            cfg.shuffling = parse_onoff(tokens[++i], cfg.shuffling);
        } else if (token == "--nmove" && i + 1 < tokens.size()) {
            // Clamp N-move rule to valid range (10-200)
            cfg.nMoveRule = clamp_range(
                parse_int_safe(tokens[++i], cfg.nMoveRule), 10, 200);
        } else if (token == "--ini") {
            // Skip the next token as it's the INI path (already processed)
            if (i + 1 < tokens.size())
                ++i;
        } else if (token == "--pd" && i + 1 < tokens.size()) {
            // Fix: Remove quotes from path arguments
            cfg.perfectDbPath = unquote_path(tokens[++i]);
            cfg.usePerfectDb = true;
        }
        // Unknown tokens are ignored to keep CLI robust
    }

    // If settings.ini was just created, prompt user to edit it first
    if (!iniLoaded && !hasArgs) {
        std::cout << "\nPlease edit the generated settings.ini file to "
                     "configure:"
                  << std::endl;
        std::cout << "  1. Set PerfectDatabasePath to your Perfect DB directory"
                  << std::endl;
        std::cout << "  2. Adjust other parameters as needed (SkillLevel, "
                     "MoveTime, etc.)"
                  << std::endl;
        std::cout << "  3. Run './sanmill benchmark' again to start the "
                     "benchmark"
                  << std::endl;
        std::cout << "\nExample Perfect DB paths:" << std::endl;
        std::cout << "  Windows: PerfectDatabasePath=C:/DB/Std" << std::endl;
        std::cout << "  Linux:   PerfectDatabasePath=/home/user/db/std"
                  << std::endl;
        return;
    }

    // If no command line args but ini was loaded, use ini settings
    if (!hasArgs && iniLoaded) {
        std::cout << "INFO: Using configuration from settings.ini" << std::endl;
    }
    apply_config(cfg);

    // Perfect DB is MANDATORY for benchmark functionality
    if (!cfg.usePerfectDb) {
        std::cout << "ERROR: Perfect DB is required for benchmark!"
                  << std::endl;
        std::cout << "Benchmark tests Traditional Search vs Perfect DB."
                  << std::endl;
        std::cout << "Use --pd PATH to specify Perfect DB path, or enable "
                     "UsePerfectDatabase=true in settings.ini"
                  << std::endl;
        return;
    }

    // Initialize Perfect DB - any failure is fatal
    // CRITICAL: Must initialize Perfect DB in main thread BEFORE starting
    // worker threads to prevent race conditions in Perfect DB initialization
    // code
#ifdef GABOR_MALOM_PERFECT_AI
    std::cout << "Initializing Perfect DB..." << std::endl;
    std::cout << "  Configured path: '" << cfg.perfectDbPath << "'"
              << std::endl;
    std::cout << "  GameOptions path: '" << gameOptions.getPerfectDatabasePath()
              << "'" << std::endl;

    // Verify path consistency
    if (cfg.perfectDbPath != gameOptions.getPerfectDatabasePath()) {
        std::cerr << "WARNING: Path mismatch detected!" << std::endl;
        std::cerr << "  Config path: '" << cfg.perfectDbPath << "'"
                  << std::endl;
        std::cerr << "  GameOptions path: '"
                  << gameOptions.getPerfectDatabasePath() << "'" << std::endl;
    }

    int initResult = perfect_reset();
    if (initResult != 0) {
        std::cerr << "ERROR: Perfect DB initialization failed with code: "
                  << initResult << std::endl;
        std::cerr << "  Configured path: " << cfg.perfectDbPath << std::endl;
        std::cerr << "  GameOptions path: "
                  << gameOptions.getPerfectDatabasePath() << std::endl;
        std::cout << "Possible causes:" << std::endl;
        std::cout << "  1. Path does not exist or is not accessible"
                  << std::endl;
        std::cout << "  2. DB files are corrupted or incomplete" << std::endl;
        std::cout << "  3. Insufficient memory or disk space" << std::endl;
        std::cout << "Cannot proceed with benchmark - Perfect DB is mandatory."
                  << std::endl;
        return;
    }

    // THREAD SAFETY FIX: Pre-initialize Perfect DB structures to prevent race
    // conditions Force initialization of MalomSolutionAccess in main thread
    // before worker threads start
    std::cout << "Pre-initializing Perfect DB structures for thread safety..."
              << std::endl;
    if (!MalomSolutionAccess::initialize_if_needed()) {
        std::cerr << "ERROR: Failed to pre-initialize Perfect DB structures!"
                  << std::endl;
        std::cerr << "This is required for thread-safe benchmark execution."
                  << std::endl;
        return;
    }

    std::cout << "Perfect DB initialized successfully (thread-safe)."
              << std::endl;
#else
    std::cout << "ERROR: Perfect DB not compiled in!" << std::endl;
    std::cout << "Benchmark requires Perfect DB support." << std::endl;
    std::cout << "Rebuild with GABOR_MALOM_PERFECT_AI defined to enable "
                 "benchmark."
              << std::endl;
    std::cout << "Example: make build ARCH=x86-64-modern "
                 "CXXFLAGS=-DGABOR_MALOM_PERFECT_AI"
              << std::endl;
    return;
#endif

    // Setup signal handler for Ctrl+C
    std::signal(SIGINT, signal_handler);

    // Validate configuration before starting
    if (cfg.skillLevel < 1 || cfg.skillLevel > 30) {
        std::cerr << "ERROR: Invalid skill level " << cfg.skillLevel
                  << ". Must be between 1 and 30." << std::endl;
        return;
    }
    if (cfg.algorithm < 0 || cfg.algorithm > 4) {
        std::cerr << "ERROR: Invalid algorithm " << cfg.algorithm
                  << ". Must be between 0 and 4." << std::endl;
        return;
    }
    if (cfg.moveTimeSec < 0) {
        std::cerr << "ERROR: Invalid move time " << cfg.moveTimeSec
                  << ". Must be >= 0." << std::endl;
        return;
    }

    // Thread Safety Information
    if (cfg.algorithm == 3) { // 3 = MCTS
        std::cout << "[OK] MCTS algorithm: Creates independent threads, fully "
                     "thread-safe.\n";
    } else {
        std::cout << "[INFO] Traditional algorithm (" << cfg.algorithm
                  << "): Using single-threaded search to avoid contention.\n";
        std::cout << "   Each benchmark thread will use 1 search thread for "
                     "consistency.\n";
    }
    std::cout << std::endl;

    // Single-thread benchmark execution - no thread splitting needed
    const bool infiniteMode = (cfg.totalGames == 0);

    ThreadStats statsA, statsB;

    const char *algNames[] = {"Alpha-Beta", "PVS", "MTD(f)", "MCTS", "Random"};
    const char *algName = (cfg.algorithm >= 0 && cfg.algorithm <= 4) ?
                              algNames[cfg.algorithm] :
                              "Unknown";

    if (infiniteMode) {
        std::cout << "Starting infinite benchmark (Ctrl+C to stop):\n"
                  << "  Algorithm: " << cfg.algorithm << " (" << algName
                  << ")\n"
                  << "  Move time: " << cfg.moveTimeSec << " seconds\n"
                  << "  Skill level: " << cfg.skillLevel << "/30\n"
                  << "  IDS: " << (cfg.idsEnabled ? "on" : "off") << "\n"
                  << "  Depth ext: " << (cfg.depthExtension ? "on" : "off")
                  << "\n"
                  << "  Opening book: " << (cfg.openingBook ? "on" : "off")
                  << "\n"
                  << "  Shuffling: " << (cfg.shuffling ? "on" : "off") << "\n"
                  << "  N-move rule: " << cfg.nMoveRule << " moves\n"
                  << "  Perfect DB: '" << cfg.perfectDbPath << "'\n"
                  << std::endl;
    } else {
        std::cout << "Starting benchmark (" << cfg.totalGames << " games):\n"
                  << "  Algorithm: " << cfg.algorithm << " (" << algName
                  << ")\n"
                  << "  Move time: " << cfg.moveTimeSec << " seconds\n"
                  << "  Skill level: " << cfg.skillLevel << "/30\n"
                  << "  IDS: " << (cfg.idsEnabled ? "on" : "off") << "\n"
                  << "  Depth ext: " << (cfg.depthExtension ? "on" : "off")
                  << "\n"
                  << "  Opening book: " << (cfg.openingBook ? "on" : "off")
                  << "\n"
                  << "  Shuffling: " << (cfg.shuffling ? "on" : "off") << "\n"
                  << "  N-move rule: " << cfg.nMoveRule << " moves\n"
                  << "  Perfect DB: '" << cfg.perfectDbPath << "'\n"
                  << std::endl;
    }

    // Real-time aggregation (single-threaded execution)
    const auto startTime = std::chrono::steady_clock::now();

    // Write initial status to file
    auto initialElapsed = std::chrono::seconds(0);
    write_benchmark_status_to_file(cfg, statsA, statsB, initialElapsed, algName,
                                   true);

    // Single-thread benchmark: Alternate Traditional AI sides each game.
    // This avoids any global-state race (e.g. move priority shuffling).
    std::cout << "Running benchmark in single-thread mode with alternating "
                 "sides (Trad=White, then Trad=Black).\n";

    int i = 0;
    while (true) {
        // Stop immediately on critical error
        if (g_critical_error.load()) {
            std::cout << "\nCritical error detected, stopping benchmark "
                         "immediately..."
                      << std::endl;
            break;
        }

        // Stop on Ctrl+C
        if (g_interrupted) {
            std::cout << "\nReceived Ctrl+C, stopping benchmark gracefully..."
                      << std::endl;
            break;
        }

        // Stop when reaching the target number of games (if not infinite)
        const uint64_t done = statsA.total.load() + statsB.total.load();
        if (!infiniteMode && done >= static_cast<uint64_t>(cfg.totalGames))
            break;

        // Decide Traditional side for this game: alternate per game index
        const Color tradSide = (i % 2 == 0) ? WHITE : BLACK;
        ThreadStats &stats = (tradSide == WHITE) ? statsA : statsB;

        // Optional progress log (reduced frequency)
        if ((i % 20) == 0) {
            if (infiniteMode) {
                std::cout << "Game " << (i + 1) << " (infinite mode), Trad="
                          << ((tradSide == WHITE) ? "White" : "Black") << "\n";
            } else {
                std::cout << "Starting game " << (i + 1) << "/"
                          << cfg.totalGames << ", Trad="
                          << ((tradSide == WHITE) ? "White" : "Black") << "\n";
            }
        }

        // Play a single game and update stats
        const int outcome = play_game_trad_vs_perfect(tradSide, cfg, i, stats);
        stats.total.fetch_add(1);

        if (outcome == 0) {
            stats.draws.fetch_add(1);
        } else if (outcome > 0) {
            // White wins
            if (tradSide == WHITE)
                stats.tradWins.fetch_add(1);
            else
                stats.perfectWins.fetch_add(1);
        } else {
            // Black wins
            if (tradSide == BLACK)
                stats.tradWins.fetch_add(1);
            else
                stats.perfectWins.fetch_add(1);
        }

        // Periodic console status (reduced frequency)
        if (((i % 10) == 9) || (!infiniteMode && (i + 1) == cfg.totalGames)) {
            print_stats("Thread A (Trad=White, Perfect=Black)", statsA);
            print_stats("Thread B (Trad=Black, Perfect=White)", statsB);
        }

        // Live update file after each game
        auto elapsed = std::chrono::duration_cast<std::chrono::seconds>(
            std::chrono::steady_clock::now() - startTime);
        write_benchmark_status_to_file(cfg, statsA, statsB, elapsed, algName,
                                       false);

        ++i;
    }

    // Final summary with detailed report
    auto endTime = std::chrono::steady_clock::now();
    auto totalElapsed = std::chrono::duration_cast<std::chrono::seconds>(
                            endTime - startTime)
                            .count();

    std::cout << "\n" << std::string(80, '=') << "\n";
    if (g_critical_error.load()) {
        std::cout << "                    BENCHMARK TERMINATED - CRITICAL "
                     "ERROR\n";
        std::cout << std::string(80, '=') << "\n\n";

        // Display error details
        std::lock_guard<std::mutex> details_lock(g_error_mutex);
        std::cout << "ERROR DETAILS:\n" << g_error_details << "\n\n";

        // Show partial results if any games were completed
        const uint64_t totalGames = statsA.total.load() + statsB.total.load();
        if (totalGames > 0) {
            std::cout << "PARTIAL RESULTS (before error):\n";
            std::cout << "Games completed: " << totalGames << "\n";
            print_overall(statsA, statsB);
        } else {
            std::cout << "No games completed before error occurred.\n";
        }

        std::cout << "\nBENCHMARK FAILED - Please fix the above error before "
                     "retrying.\n";
        std::cout << std::string(80, '=') << "\n";

        // Skip normal cleanup and exit with error indication
        return;
    } else {
        std::cout << "                      BENCHMARK COMPLETE\n";
        std::cout << std::string(80, '=') << "\n\n";
    }

    std::cout << "Configuration:\n";
    std::cout << "  Algorithm: " << cfg.algorithm << " (" << algName << ")\n";
    if (cfg.algorithm == 3) {
        std::cout << "  [OK] Thread Safety: Excellent (MCTS uses independent "
                     "threads)\n";
    } else {
        std::cout << "  [INFO] Thread Safety: Managed (single-threaded search "
                     "per engine)\n";
    }
    std::cout << "  Skill Level: " << cfg.skillLevel << "/30\n";
    std::cout << "  Move Time: " << cfg.moveTimeSec << " seconds\n";
    std::cout << "  IDS: " << (cfg.idsEnabled ? "enabled" : "disabled") << "\n";
    std::cout << "  Depth Extension: "
              << (cfg.depthExtension ? "enabled" : "disabled") << "\n";
    std::cout << "  Opening Book: "
              << (cfg.openingBook ? "enabled" : "disabled") << "\n";
    std::cout << "  Shuffling: " << (cfg.shuffling ? "enabled" : "disabled")
              << "\n";
    std::cout << "  N-move rule: " << cfg.nMoveRule << " moves\n";
    std::cout << "  Perfect DB Path: " << cfg.perfectDbPath << "\n\n";

    std::cout << "Thread Results:\n";
    print_stats("Thread A (Traditional=White)", statsA);
    print_stats("Thread B (Traditional=Black)", statsB);

    std::cout << "\nOverall Summary:\n";
    print_overall(statsA, statsB);

    // Performance metrics
    const uint64_t totalGames = statsA.total.load() + statsB.total.load();
    if (totalElapsed > 0 && totalGames > 0) {
        double gamesPerSecond = static_cast<double>(totalGames) / totalElapsed;
        double avgGameTime = static_cast<double>(totalElapsed) / totalGames;
        std::cout << "\nPerformance:\n";
        std::cout << "  Total Time: " << totalElapsed << " seconds\n";
        std::cout << "  Games/Second: " << std::fixed << std::setprecision(2)
                  << gamesPerSecond << "\n";
        std::cout << "  Avg Game Time: " << std::fixed << std::setprecision(2)
                  << avgGameTime << " seconds\n";
    }

    // Quality metrics
    const uint64_t totalErrors = statsA.errors.load() + statsB.errors.load();
    const uint64_t totalTimeouts = statsA.timeouts.load() +
                                   statsB.timeouts.load();
    const uint64_t totalEarlyWins = statsA.earlyWinTerminations.load() +
                                    statsB.earlyWinTerminations.load();
    const uint64_t totalEarlyDraws = statsA.earlyDrawTerminations.load() +
                                     statsB.earlyDrawTerminations.load();

    if (totalErrors > 0 || totalTimeouts > 0) {
        std::cout << "\nQuality Issues Detected:\n";
        if (totalErrors > 0) {
            std::cout << "  [WARNING] Engine Errors: " << totalErrors << " ("
                      << std::fixed << std::setprecision(2)
                      << (100.0 * totalErrors / totalGames) << "%)\n";
        }
        if (totalTimeouts > 0) {
            std::cout << "  [WARNING] Game Timeouts: " << totalTimeouts << " ("
                      << std::fixed << std::setprecision(2)
                      << (100.0 * totalTimeouts / totalGames) << "%)\n";
        }
    } else {
        std::cout << "\n[OK] No quality issues detected - all games completed "
                     "normally.\n";
    }

    // Optimization metrics
    if (totalEarlyWins > 0 || totalEarlyDraws > 0) {
        std::cout << "\nOptimization Statistics:\n";
        if (totalEarlyWins > 0) {
            std::cout << "  [INFO] Early Win Terminations: " << totalEarlyWins
                      << " (" << std::fixed << std::setprecision(2)
                      << (100.0 * totalEarlyWins / totalGames) << "%)\n";
            std::cout << "    Perfect DB detected winning positions and "
                         "terminated games early\n";
        }
        if (totalEarlyDraws > 0) {
            std::cout << "  [INFO] Early Draw Terminations: " << totalEarlyDraws
                      << " (" << std::fixed << std::setprecision(2)
                      << (100.0 * totalEarlyDraws / totalGames) << "%)\n";
            std::cout << "    Moving phase: one side has 3 pieces, other side "
                         "has <7 pieces, Perfect DB shows draw\n";
        }
        std::cout << "  [INFO] Total Early Terminations: "
                  << (totalEarlyWins + totalEarlyDraws) << " (" << std::fixed
                  << std::setprecision(2)
                  << (100.0 * (totalEarlyWins + totalEarlyDraws) / totalGames)
                  << "%)\n";
    }

    // Write final detailed results to file
    {
        std::lock_guard<std::mutex> file_lock(g_file_mutex);
        std::ofstream resultFile("benchmark-results.txt");
        if (resultFile.is_open()) {
            // Write timestamp and configuration
            auto now = std::chrono::system_clock::now();
            auto time_t = std::chrono::system_clock::to_time_t(now);
            resultFile << "Sanmill Benchmark Results (FINAL)\n";

            // Use safe time formatting
#ifdef _WIN32
            char timeStr[64];
            if (ctime_s(timeStr, sizeof(timeStr), &time_t) == 0) {
                resultFile << "Completed: " << timeStr;
            } else {
                resultFile << "Completed: [Time format error]\n";
            }
#else
            resultFile << "Completed: " << std::ctime(&time_t);
#endif
            resultFile << "Status: COMPLETED\n";
            resultFile << "Total Time: " << totalElapsed << " seconds\n";
            resultFile << "=========================\n\n";

            // Write configuration (reuse algName from outer scope)
            resultFile << "Configuration:\n";
            resultFile << "  Algorithm: " << cfg.algorithm << " (" << algName
                       << ")\n";
            if (cfg.algorithm == 3) {
                resultFile << "  [OK] Thread Safety: Excellent (MCTS uses "
                              "independent threads)\n";
            } else {
                resultFile << "  [INFO] Thread Safety: Managed "
                              "(single-threaded search per engine)\n";
            }
            resultFile << "  Skill Level: " << cfg.skillLevel << "/30\n";
            resultFile << "  Move Time: " << cfg.moveTimeSec << " seconds\n";
            resultFile << "  IDS: " << (cfg.idsEnabled ? "enabled" : "disabled")
                       << "\n";
            resultFile << "  Depth Extension: "
                       << (cfg.depthExtension ? "enabled" : "disabled") << "\n";
            resultFile << "  Opening Book: "
                       << (cfg.openingBook ? "enabled" : "disabled") << "\n";
            resultFile << "  Shuffling: "
                       << (cfg.shuffling ? "enabled" : "disabled") << "\n";
            resultFile << "  N-move rule: " << cfg.nMoveRule << " moves\n";
            resultFile << "  Perfect DB Path: " << cfg.perfectDbPath << "\n\n";

            // Write thread results
            resultFile << "Final Thread Results:\n";
            print_stats_to_file(resultFile, "Thread A (Traditional=White)",
                                statsA);
            print_stats_to_file(resultFile, "Thread B (Traditional=Black)",
                                statsB);

            resultFile << "\nFinal Overall Summary:\n";
            print_overall_to_file(resultFile, statsA, statsB);

            // Write performance metrics
            if (totalElapsed > 0 && totalGames > 0) {
                double gamesPerSecond = static_cast<double>(totalGames) /
                                        totalElapsed;
                double avgGameTime = static_cast<double>(totalElapsed) /
                                     totalGames;
                resultFile << "\nFinal Performance:\n";
                resultFile << "  Total Time: " << totalElapsed << " seconds\n";
                resultFile << "  Games/Second: " << std::fixed
                           << std::setprecision(2) << gamesPerSecond << "\n";
                resultFile << "  Avg Game Time: " << std::fixed
                           << std::setprecision(2) << avgGameTime
                           << " seconds\n";
            }

            // Write quality metrics
            if (totalErrors > 0 || totalTimeouts > 0) {
                resultFile << "\nFinal Quality Issues:\n";
                if (totalErrors > 0) {
                    resultFile << "  [WARNING] Engine Errors: " << totalErrors
                               << " (" << std::fixed << std::setprecision(2)
                               << (100.0 * totalErrors / totalGames) << "%)\n";
                }
                if (totalTimeouts > 0) {
                    resultFile << "  [WARNING] Game Timeouts: " << totalTimeouts
                               << " (" << std::fixed << std::setprecision(2)
                               << (100.0 * totalTimeouts / totalGames)
                               << "%)\n";
                }
            } else {
                resultFile << "\n[OK] No quality issues detected - all games "
                              "completed normally.\n";
            }

            // Write optimization metrics
            if (totalEarlyWins > 0 || totalEarlyDraws > 0) {
                resultFile << "\nFinal Optimization Statistics:\n";
                if (totalEarlyWins > 0) {
                    resultFile
                        << "  [INFO] Early Win Terminations: " << totalEarlyWins
                        << " (" << std::fixed << std::setprecision(2)
                        << (100.0 * totalEarlyWins / totalGames) << "%)\n";
                    resultFile << "    Perfect DB detected winning positions "
                                  "and terminated games early\n";
                }
                if (totalEarlyDraws > 0) {
                    resultFile << "  [INFO] Early Draw Terminations: "
                               << totalEarlyDraws << " (" << std::fixed
                               << std::setprecision(2)
                               << (100.0 * totalEarlyDraws / totalGames)
                               << "%)\n";
                    resultFile << "    Moving phase: one side has 3 pieces, "
                                  "other side has <7 pieces, Perfect DB shows "
                                  "draw\n";
                }
                resultFile << "  [INFO] Total Early Terminations: "
                           << (totalEarlyWins + totalEarlyDraws) << " ("
                           << std::fixed << std::setprecision(2)
                           << (100.0 * (totalEarlyWins + totalEarlyDraws) /
                               totalGames)
                           << "%)\n";
            }

            resultFile.close();
            std::cout << "\nFinal detailed results saved to: "
                         "benchmark-results.txt\n";
        } else {
            std::cout << "\nWARNING: Could not create final "
                         "benchmark-results.txt file\n";
        }
    }

    std::cout << "\n" << std::string(80, '=') << "\n";

    // THREAD SAFETY: Clean up Perfect DB resources after benchmark
    // completion Now that all worker threads have finished, it's safe to
    // deinitialize
#ifdef GABOR_MALOM_PERFECT_AI
    std::cout << "Cleaning up Perfect DB resources..." << std::endl;
    MalomSolutionAccess::deinitialize_if_needed();
    std::cout << "Perfect DB cleanup completed." << std::endl;
#endif

#else
    (void)is;
    std::cout << "Benchmark is disabled. Rebuild with ENABLE_BENCHMARK macro."
              << std::endl;
#endif
}

} // namespace Benchmark
