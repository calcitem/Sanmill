// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// perfect_strip_db.cpp

#include <cstdio>
#include <cstdlib>
#include <vector>
#include <algorithm>
#include <stdexcept>
#include <iostream>

#include "position.h" // Position
#include "search.h"   // Search::search(...)
#include "search_engine.h"
#include "types.h"  // Value, ...
#include "misc.h"   // sync_cout, sync_endl
#include "option.h" // gameOptions, etc.

#include "perfect_common.h"   // field2Offset, field1Size, field2Size, ...
#include "perfect_sector.h"   // Sector, sector->header_size=64 in DD mode
#include "perfect_wrappers.h" // Wrappers::WID => sectorMap
#include "perfect_adaptor.h"  // perfect_init, ...
#include "perfect_api.h"      // MalomSolutionAccess
#include "perfect_errors.h"   // PerfectErrors error handling

#ifdef WRAPPER
// WRAPPER mode => sector->f pointer
#endif

/// 1) Compare perfect database evaluation with Alpha-Beta evaluation, only
/// distinguishing Win/Lose/Draw
static bool compareEvalDD(const eval_elem2 &dbEval, Value abVal)
{
    // Convert dbEval to 'W' (Win), 'L' (Lose), 'D' (Draw)
    char dbRes = 'D';
    if (dbEval.key1 == virt_win_val) {
        dbRes = 'W';
    } else if (dbEval.key1 == virt_loss_val) {
        dbRes = 'L';
    }

    // Convert abVal to 'W' (Win), 'L' (Lose), 'D' (Draw)
    char abRes = 'D';
    if (abVal >= VALUE_EACH_PIECE) {
        abRes = 'W';
    } else if (abVal <= -VALUE_EACH_PIECE) {
        abRes = 'L';
    }

    return (dbRes == abRes);
}

/// 2) Build Position from sector->hash->inverse_hash(i)
///    If sector->id.W != ... => blackMove, etc. (you can customize this
///    judgment)
static Position buildPositionDD(Sector *sector, int i, bool blackToMove)
{
    Position pos;
    pos.construct_key();
    pos.reset();

    const board raw = sector->hash->inverse_hash(i);
    const uint32_t whiteBits = (uint32_t)(raw & mask24);
    const uint32_t blackBits = (uint32_t)((raw >> 24) & mask24);

    for (int sq = 0; sq < 24; sq++) {
        uint32_t mask = 1U << sq;
        if (whiteBits & mask) {
            pos.put_piece(W_PIECE, from_perfect_square(sq));
        } else if (blackBits & mask) {
            pos.put_piece(B_PIECE, from_perfect_square(sq));
        }
    }

    // Set the number of pieces in hand
    pos.pieceInHandCount[WHITE] = sector->WF;
    pos.pieceInHandCount[BLACK] = sector->BF;

    if (!blackToMove)
        pos.set_side_to_move(WHITE);
    else
        pos.set_side_to_move(BLACK);

    return pos;
}

/// 3) Use a simple Alpha-Beta search
static Value callAlphaBetaDD(Position &pos)
{
    Sanmill::Stack<Position> ss;
    Move best = MOVE_NONE;
    Depth depth = 8; // Can be adjusted as needed

    SearchEngine engine;
    Value v = Search::search(engine, &pos, ss, depth, depth, -VALUE_INFINITE,
                             VALUE_INFINITE, best);
    return v;
}

/// 4) Strip a single sector (DD mode + WRAPPER=ON)
///    Only keep entries where "compareEvalDD(...)==false"
static void stripSectorDD(Sector *sector)
{
    std::string oldFileName = sector->id.file_name();
    std::string newFileName = oldFileName + ".filtered";

    // Open the old file
    FILE *fOld = nullptr;
    if (FOPEN(&fOld, oldFileName.c_str(), "rb") != 0 || !fOld) {
        std::cerr << "[stripDB] failed to open old sector " << oldFileName
                  << std::endl;
        return;
    }

    // Open the new file
    FILE *fNew = nullptr;
    if (FOPEN(&fNew, newFileName.c_str(), "wb") != 0 || !fNew) {
        std::cerr << "[stripDB] failed to open new sector " << newFileName
                  << std::endl;
        fclose(fOld);
        return;
    }

    // Write the header (64 bytes)
    sector->write_header(fNew); // Includes version, eval_struct_size,
                                // field2Offset, stone_diff_flag, etc.

    const int totalCount = sector->hash->hash_count;
    const int itemSize = eval_struct_size; //=3

    // Read the old evaluations from (header_size to header_size + totalCount*3)
    fseek(fOld, Sector::header_size, SEEK_SET);
    std::vector<unsigned char> oldEval(totalCount * itemSize);
    {
        size_t readN = fread(oldEval.data(), itemSize, totalCount, fOld);
        if (readN != (size_t)totalCount) {
            std::cerr << "[stripDB] read mismatch. " << readN << " vs "
                      << totalCount << std::endl;
            fclose(fOld);
            fclose(fNew);
            return;
        }
    }

    // Iterate through i to determine which entries to keep
    std::vector<int> keep;
    keep.reserve(totalCount);

    for (int i = 0; i < totalCount; i++) {
        eval_elem2 dbVal = sector->get_eval(i);

        // Determine side to move (example: if sector->B > sector->W, black
        // moves)
        bool blackMove = false;
        if (sector->B > sector->W)
            blackMove = true;

        Position pos = buildPositionDD(sector, i, blackMove);
        Value abVal = callAlphaBetaDD(pos);

        if (!compareEvalDD(dbVal, abVal)) {
            keep.push_back(i);
        }
    }

    // Write the evaluations of the kept entries
    fseek(fNew, Sector::header_size, SEEK_SET);

    for (int newI = 0; newI < (int)keep.size(); newI++) {
        int oldI = keep[newI];
        // Copy itemSize bytes corresponding to oldI
        size_t offOld = (size_t)oldI * itemSize;
        fwrite(oldEval.data() + offOld, 1, itemSize, fNew);
    }

    // Write em_set
    // Only keep entries where oldI is in keep, and map oldI to newI
    std::map<int, int> newEmSet;
    for (int newI = 0; newI < (int)keep.size(); newI++) {
        int oldI = keep[newI];
        auto it = sector->em_set.find(oldI);
        if (it != sector->em_set.end()) {
            newEmSet[newI] = it->second;
        }
    }

    int newCount = (int)newEmSet.size();
    fwrite(&newCount, sizeof(int), 1, fNew);
    for (auto &kv : newEmSet) {
        int iKey = kv.first;
        int iVal = kv.second;
        fwrite(&iKey, sizeof(int), 1, fNew);
        fwrite(&iVal, sizeof(int), 1, fNew);
    }

    fclose(fOld);
    fclose(fNew);

    remove(oldFileName.c_str());
    rename(newFileName.c_str(), oldFileName.c_str());

    std::cout << "[stripDB] sector: " << oldFileName
              << ", remain = " << keep.size() << "/" << totalCount << std::endl;
}

/// Main function to strip the perfect database
void stripPerfectDatabase()
{
    using namespace PerfectErrors;

    clearError(); // Clear any previous errors

    // 1) Ensure perfect_init(), field2Offset, etc., are set via
    // MalomSolutionAccess::initialize_if_needed()
    //    This prepares ruleVariant, pieceCount, field2Offset, etc.
    if (!MalomSolutionAccess::initialize_if_needed()) {
        std::cerr << "[stripDB] init failed: "
                  << PerfectErrors::getLastErrorMessage() << std::endl;
        return;
    }

    auto sectorMap = Sectors::get_sectors();
    if (sectorMap.empty()) {
        std::cerr << "[stripDB] no sector found." << std::endl;
        return;
    }

    // Iterate through all sectors
    for (auto &kv : sectorMap) {
        Wrappers::WSector &wsec = kv.second;
        Sector *sec = wsec.s;
        // Allocate hash
        sec->allocate_hash();
        if (!sec->hash || sec->hash->hash_count == 0) {
            sec->release_hash();
            continue;
        }

        // Strip the sector
        stripSectorDD(sec);

        // Release the hash
        sec->release_hash();
    }

    MalomSolutionAccess::deinitialize_if_needed();

    std::cout << "[stripDB] all done.\n";
}
