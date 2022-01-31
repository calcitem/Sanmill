/*********************************************************************
    PerfectAI.cpp
    Copyright (c) Thomas Weber. All rights reserved.
    Copyright (C) 2019-2022 The Sanmill developers (see AUTHORS file)
    Licensed under the GPLv3 License.
    https://github.com/madweasel/Muehle
\*********************************************************************/

#include "config.h"

#ifdef MADWEASEL_MUEHLE_PERFECT_AI

#include "perfectAI.h"
#include <cassert>

// clang-format off
uint32_t soTableTurnLeft[] = {
 2,      14,      23,
    5,   13,   20,
       8,12,17,
 1, 4, 7,   16,19,22,
       6,11,15,
    3,   10,   18,
 0,       9,      21
};

uint32_t soTableDoNothing[] = {
 0,       1,       2,
    3,    4,    5,
       6, 7, 8,
 9,10,11,   12,13,14,
      15,16,17,
   18,   19,   20,
21,      22,      23
};

uint32_t soTableMirrorHori[] = {
21,      22,      23,
   18,   19,   20,
      15,16,17,
 9,10,11,   12,13,14,
       6, 7, 8,
    3,    4,    5,
 0,       1,       2
};

uint32_t soTableTurn180[] = {
 23,      22,      21,
    20,   19,   18,
       17,16,15,
 14,13,12,   11,10, 9,
        8, 7, 6,
     5,    4,    3,
  2,       1,       0
};

uint32_t soTableInvert[] = {
  6,       7,       8,
     3,    4,    5,
        0, 1, 2,
 11,10, 9,   14,13,12,
       21,22,23,
    18,   19,   20,
 15,      16,      17
};

uint32_t soTableInvMirHori[] = {
 15,      16,      17,
    18,   19,   20,
       21,22,23,
 11,10, 9,   14,13,12,
        0, 1, 2,
     3,    4,    5,
  6,       7,       8
};

uint32_t soTableInvMirVert[] = {
  8,       7,       6,
     5,    4,    3,
        2, 1, 0,
 12,13,14,    9,10,11,
       23,22,21,
    20,   19,   18,
 17,      16,      15
};

uint32_t soTableInvMirDiag1[] = {
 17,      12,       8,
    20,   13,    5,
       23,14, 2,
 16,19,22,    1, 4, 7,
       21, 9, 0,
    18,   10,    3,
 15,      11,       6
};

uint32_t soTableInvMirDiag2[] = {
  6,      11,      15,
     3,   10,   18,
        0, 9,21,
  7, 4, 1,   22,19,16,
        2,14,23,
     5,   13,   20,
  8,      12,      17
};

uint32_t soTableInvLeft[] = {
  8,      12,      17,
     5,   13,   20,
        2,14,23,
  7, 4, 1,   22,19,16,
        0, 9,21,
     3,   10,   18,
  6,      11,      15
};

uint32_t soTableInvRight[] = {
 15,      11,       6,
    18,   10,    3,
       21, 9, 0,
 16,19,22,    1, 4, 7,
       23,14, 2,
    20,   13,    5,
 17,      12,       8
};

uint32_t soTableInv180[] = {
 17,      16,      15,
    20,   19,   18,
       23,22,21,
 12,13,14,    9,10,11,
        2, 1, 0,
     5,    4,    3,
  8,       7,       6
};

uint32_t soTableMirrorDiag1[] = {
  0,       9,      21,
     3,   10,   18,
        6,11,15,
  1, 4, 7,   16,19,22,
        8,12,17,
     5,   13,   20,
  2,      14,      23
};

uint32_t soTableTurnRight[] = {
  21,       9,       0,
     18,   10,    3,
        15,11, 6,
  22,19,16,    7, 4, 1,
        17,12, 8,
     20,   13,    5,
  23,      14,       2
};

uint32_t soTableMirrorVert[] = {
   2,       1,       0,
      5,    4,    3,
         8, 7, 6,
  14,13,12,   11,10, 9,
        17,16,15,
     20,   19,   18,
  23,      22,      21
};

uint32_t soTableMirrorDiag2[] = {
  23,      14,       2,
     20,   13,    5,
        17,12, 8,
  22,19,16,    7, 4, 1,
        15,11, 6,
     18,   10,    3,
  21,       9,       0
};
// clang-format on

// define the four groups
uint32_t squareIdxGroupA[] = {3, 5, 20, 18};
uint32_t squareIdxGroupB[8] = {4, 13, 19, 10};
uint32_t squareIdxGroupC[] = {0, 2, 23, 21, 6, 8, 17, 15};
uint32_t squareIdxGroupD[] = {1, 7, 14, 12, 22, 16, 9, 11};

// clang-format off
uint32_t fieldPosIsOfGroup[] = { GROUP_C,                GROUP_D,                GROUP_C,
                                         GROUP_A,        GROUP_B,        GROUP_A,
                                                 GROUP_C,GROUP_D,GROUP_C,
                                 GROUP_D,GROUP_B,GROUP_D,        GROUP_D,GROUP_B,GROUP_D,
                                                 GROUP_C,GROUP_D,GROUP_C,
                                         GROUP_A,        GROUP_B,        GROUP_A,
                                 GROUP_C,                GROUP_D,                GROUP_C };
// clang-format on

//-----------------------------------------------------------------------------
// PerfectAI()
// PerfectAI class constructor
//-----------------------------------------------------------------------------
PerfectAI::PerfectAI(const char *dir)
{
    // locals
    uint32_t i, a, b, c, totalPieceCount;
    uint32_t wCD, bCD, wAB, bAB;
    uint32_t stateAB, stateCD, symStateCD, layerNum;
    uint32_t myField[SQUARE_NB] {};
    uint32_t symField[SQUARE_NB];
    uint32_t *origStateCD_tmp[10][10] {};
    DWORD dwBytesRead = 0;
    DWORD dwBytesWritten = 0;
    HANDLE hFilePreCalcVars;
    stringstream ssPreCalcVarsFilePath;
    PreCalcedVarsFileHeader preCalcVarsHeader;

    threadVars = new ThreadVars[getThreadCount()];
    std::memset(threadVars, 0, sizeof(ThreadVars) * getThreadCount());

    for (uint32_t thd = 0; thd < getThreadCount(); thd++) {
        threadVars[thd].parent = this;
        threadVars[thd].field = &dummyField;
        threadVars[thd].possibilities = new Possibility[TREE_DEPTH_MAX + 1];
        std::memset(threadVars[thd].possibilities, 0,
                    sizeof(Possibility) * (TREE_DEPTH_MAX + 1));
        threadVars[thd].oldStates = new Backup[TREE_DEPTH_MAX + 1];
        std::memset(threadVars[thd].oldStates, 0,
                    sizeof(Backup) * (TREE_DEPTH_MAX + 1));
        threadVars[thd].idPossibilities =
            new uint32_t[(TREE_DEPTH_MAX + 1) * POSIBILE_MOVE_COUNT_MAX];
        std::memset(threadVars[thd].idPossibilities, 0,
                    sizeof(uint32_t) *
                        ((TREE_DEPTH_MAX + 1) * POSIBILE_MOVE_COUNT_MAX));
    }

    // Open File, which contains the precalculated vars
    if (strlen(dir) && PathFileExistsA(dir)) {
        ssPreCalcVarsFilePath << dir << "\\";
    }

    ssPreCalcVarsFilePath << "preCalculatedVars.dat";
    hFilePreCalcVars = CreateFileA(ssPreCalcVarsFilePath.str().c_str(),
                                   GENERIC_READ /*| GENERIC_WRITE*/,
                                   FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr,
                                   OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (!ReadFile(hFilePreCalcVars, &preCalcVarsHeader,
                  sizeof(PreCalcedVarsFileHeader), &dwBytesRead, nullptr))
        return;

    // vars already stored in file?
    if (dwBytesRead) {
        // Read from file
        if (!ReadFile(hFilePreCalcVars, layer, sizeof(Layer) * LAYER_COUNT,
                      &dwBytesRead, nullptr))
            return;
        if (!ReadFile(hFilePreCalcVars, layerIndex,
                      sizeof(uint32_t) * 2 * PIECE_PER_PLAYER_PLUS_ONE_COUNT *
                          PIECE_PER_PLAYER_PLUS_ONE_COUNT,
                      &dwBytesRead, nullptr))
            return;
        if (!ReadFile(hFilePreCalcVars, nPositionsAB,
                      sizeof(uint32_t) * PIECE_PER_PLAYER_PLUS_ONE_COUNT *
                          PIECE_PER_PLAYER_PLUS_ONE_COUNT,
                      &dwBytesRead, nullptr))
            return;
        if (!ReadFile(hFilePreCalcVars, nPositionsCD,
                      sizeof(uint32_t) * PIECE_PER_PLAYER_PLUS_ONE_COUNT *
                          PIECE_PER_PLAYER_PLUS_ONE_COUNT,
                      &dwBytesRead, nullptr))
            return;
        if (!ReadFile(hFilePreCalcVars, indexAB,
                      sizeof(uint32_t) * MAX_ANZ_POSITION_A *
                          MAX_ANZ_POSITION_B,
                      &dwBytesRead, nullptr))
            return;
        if (!ReadFile(hFilePreCalcVars, indexCD,
                      sizeof(uint32_t) * MAX_ANZ_POSITION_C *
                          MAX_ANZ_POSITION_D,
                      &dwBytesRead, nullptr))
            return;
        if (!ReadFile(hFilePreCalcVars, symOpCD,
                      sizeof(unsigned char) * MAX_ANZ_POSITION_C *
                          MAX_ANZ_POSITION_D,
                      &dwBytesRead, nullptr))
            return;
        if (!ReadFile(hFilePreCalcVars, powerOfThree,
                      sizeof(uint32_t) * (nSquaresGroupC + nSquaresGroupD),
                      &dwBytesRead, nullptr))
            return;
        if (!ReadFile(hFilePreCalcVars, symOpTable,
                      sizeof(uint32_t) * SQUARE_NB * SO_COUNT, &dwBytesRead,
                      nullptr))
            return;
        if (!ReadFile(hFilePreCalcVars, reverseSymOp,
                      sizeof(uint32_t) * SO_COUNT, &dwBytesRead, nullptr))
            return;
        if (!ReadFile(hFilePreCalcVars, concSymOp,
                      sizeof(uint32_t) * SO_COUNT * SO_COUNT, &dwBytesRead,
                      nullptr))
            return;
        if (!ReadFile(hFilePreCalcVars, mOverN,
                      sizeof(uint32_t) * (SQUARE_NB + 1) * (SQUARE_NB + 1),
                      &dwBytesRead, nullptr))
            return;
        if (!ReadFile(hFilePreCalcVars, moveValue,
                      sizeof(unsigned char) * SQUARE_NB * SQUARE_NB,
                      &dwBytesRead, nullptr))
            return;
        if (!ReadFile(hFilePreCalcVars, plyInfoForOutput,
                      sizeof(PlyInfoVarType) * SQUARE_NB * SQUARE_NB,
                      &dwBytesRead, nullptr))
            return;
        if (!ReadFile(hFilePreCalcVars, incidencesValuesSubMoves,
                      sizeof(uint32_t) * 4 * SQUARE_NB * SQUARE_NB,
                      &dwBytesRead, nullptr))
            return;

        // process origStateAB[][]
        for (a = 0; a <= PIECE_PER_PLAYER_COUNT; a++) {
            for (b = 0; b <= PIECE_PER_PLAYER_COUNT; b++) {
                if (a + b > nSquaresGroupA + nSquaresGroupB)
                    continue;
                origStateAB[a][b] = new uint32_t[nPositionsAB[a][b]];
                std::memset(origStateAB[a][b], 0,
                            sizeof(uint32_t) * nPositionsAB[a][b]);
                if (!ReadFile(hFilePreCalcVars, origStateAB[a][b],
                              sizeof(uint32_t) * nPositionsAB[a][b],
                              &dwBytesRead, nullptr))
                    return;
            }
        }

        // process origStateCD[][]
        for (a = 0; a <= PIECE_PER_PLAYER_COUNT; a++) {
            for (b = 0; b <= PIECE_PER_PLAYER_COUNT; b++) {
                if (a + b > nSquaresGroupC + nSquaresGroupD)
                    continue;
                origStateCD[a][b] = new uint32_t[nPositionsCD[a][b]];
                std::memset(origStateCD[a][b], 0,
                            sizeof(uint32_t) * nPositionsCD[a][b]);
                if (!ReadFile(hFilePreCalcVars, origStateCD[a][b],
                              sizeof(uint32_t) * nPositionsCD[a][b],
                              &dwBytesRead, nullptr))
                    return;
            }
        }

        // calculate vars and save into file
    } else {
        // calculate mOverN
        for (a = 0; a <= SQUARE_NB; a++) {
            for (b = 0; b <= SQUARE_NB; b++) {
                mOverN[a][b] = static_cast<uint32_t>(mOverN_Function(a, b));
            }
        }

        // reset
        for (i = 0; i < SQUARE_NB * SQUARE_NB; i++) {
            plyInfoForOutput[i] = PLYINFO_VALUE_INVALID;
            moveValue[i] = SKV_VALUE_INVALID;
            incidencesValuesSubMoves[i][SKV_VALUE_INVALID] = 0;
            incidencesValuesSubMoves[i][SKV_VALUE_GAME_LOST] = 0;
            incidencesValuesSubMoves[i][SKV_VALUE_GAME_DRAWN] = 0;
            incidencesValuesSubMoves[i][SKV_VALUE_GAME_WON] = 0;
        }

        // power of three
        for (powerOfThree[0] = 1, i = 1; i < nSquaresGroupC + nSquaresGroupD;
             i++)
            powerOfThree[i] = 3 * powerOfThree[i - 1];

        // symmetry operation table
        for (i = 0; i < SQUARE_NB; i++) {
            symOpTable[SO_TURN_LEFT][i] = soTableTurnLeft[i];
            symOpTable[SO_TURN_180][i] = soTableTurn180[i];
            symOpTable[SO_TURN_RIGHT][i] = soTableTurnRight[i];
            symOpTable[SO_DO_NOTHING][i] = soTableDoNothing[i];
            symOpTable[SO_INVERT][i] = soTableInvert[i];
            symOpTable[SO_MIRROR_VERT][i] = soTableMirrorVert[i];
            symOpTable[SO_MIRROR_HORI][i] = soTableMirrorHori[i];
            symOpTable[SO_MIRROR_DIAG_1][i] = soTableMirrorDiag1[i];
            symOpTable[SO_MIRROR_DIAG_2][i] = soTableMirrorDiag2[i];
            symOpTable[SO_INV_LEFT][i] = soTableInvLeft[i];
            symOpTable[SO_INV_RIGHT][i] = soTableInvRight[i];
            symOpTable[SO_INV_180][i] = soTableInv180[i];
            symOpTable[SO_INV_MIRROR_VERT][i] = soTableInvMirHori[i];
            symOpTable[SO_INV_MIRROR_HORI][i] = soTableInvMirVert[i];
            symOpTable[SO_INV_MIRROR_DIAG_1][i] = soTableInvMirDiag1[i];
            symOpTable[SO_INV_MIRROR_DIAG_2][i] = soTableInvMirDiag2[i];
        }

        // reverse symmetry operation
        reverseSymOp[SO_TURN_LEFT] = SO_TURN_RIGHT;
        reverseSymOp[SO_TURN_180] = SO_TURN_180;
        reverseSymOp[SO_TURN_RIGHT] = SO_TURN_LEFT;
        reverseSymOp[SO_DO_NOTHING] = SO_DO_NOTHING;
        reverseSymOp[SO_INVERT] = SO_INVERT;
        reverseSymOp[SO_MIRROR_VERT] = SO_MIRROR_VERT;
        reverseSymOp[SO_MIRROR_HORI] = SO_MIRROR_HORI;
        reverseSymOp[SO_MIRROR_DIAG_1] = SO_MIRROR_DIAG_1;
        reverseSymOp[SO_MIRROR_DIAG_2] = SO_MIRROR_DIAG_2;
        reverseSymOp[SO_INV_LEFT] = SO_INV_RIGHT;
        reverseSymOp[SO_INV_RIGHT] = SO_INV_LEFT;
        reverseSymOp[SO_INV_180] = SO_INV_180;
        reverseSymOp[SO_INV_MIRROR_VERT] = SO_INV_MIRROR_VERT;
        reverseSymOp[SO_INV_MIRROR_HORI] = SO_INV_MIRROR_HORI;
        reverseSymOp[SO_INV_MIRROR_DIAG_1] = SO_INV_MIRROR_DIAG_1;
        reverseSymOp[SO_INV_MIRROR_DIAG_2] = SO_INV_MIRROR_DIAG_2;

        // concatenated symmetry operations
        for (a = 0; a < SO_COUNT; a++) {
            for (b = 0; b < SO_COUNT; b++) {
                // test each symmetry operation
                for (c = 0; c < SO_COUNT; c++) {
                    // look if b(a(state)) == c(state)
                    for (i = 0; i < SQUARE_NB; i++) {
                        if (symOpTable[c][i] != symOpTable[a][symOpTable[b][i]])
                            break;
                    }

                    // match found?
                    if (i == SQUARE_NB) {
                        concSymOp[a][b] = c;
                        break;
                    }
                }

                // no match found
                if (c == SO_COUNT) {
                    cout << endl << "ERROR IN SYMMETRY-OPERATIONS!" << endl;
                }
            }
        }

        // group A&B //

        // reserve memory
        for (a = 0; a <= PIECE_PER_PLAYER_COUNT; a++) {
            for (b = 0; b <= PIECE_PER_PLAYER_COUNT; b++) {
                if (a + b > nSquaresGroupA + nSquaresGroupB)
                    continue;

                nPositionsAB[a][b] =
                    mOverN[nSquaresGroupA + nSquaresGroupB][a] *
                    mOverN[nSquaresGroupA + nSquaresGroupB - a][b];
                origStateAB[a][b] = new uint32_t[nPositionsAB[a][b]];
                std::memset(origStateAB[a][b], 0,
                            sizeof(uint32_t) * nPositionsAB[a][b]);
                nPositionsAB[a][b] = 0;
            }
        }

        // mark all indexCD as not indexed
        for (stateAB = 0; stateAB < MAX_ANZ_POSITION_A * MAX_ANZ_POSITION_B;
             stateAB++)
            indexAB[stateAB] = NOT_INDEXED;

        for (stateAB = 0; stateAB < MAX_ANZ_POSITION_A * MAX_ANZ_POSITION_B;
             stateAB++) {
            // new state ?
            if (indexAB[stateAB] == NOT_INDEXED) {
                // zero board
                for (i = 0; i < SQUARE_NB; i++)
                    myField[i] = FREE_SQUARE;

                // make board
                myField[squareIdxGroupA[0]] = (stateAB / powerOfThree[7]) % 3;
                myField[squareIdxGroupA[1]] = (stateAB / powerOfThree[6]) % 3;
                myField[squareIdxGroupA[2]] = (stateAB / powerOfThree[5]) % 3;
                myField[squareIdxGroupA[3]] = (stateAB / powerOfThree[4]) % 3;
                myField[squareIdxGroupB[4]] = (stateAB / powerOfThree[3]) % 3;
                myField[squareIdxGroupB[5]] = (stateAB / powerOfThree[2]) % 3;
                myField[squareIdxGroupB[6]] = (stateAB / powerOfThree[1]) % 3;
                myField[squareIdxGroupB[7]] = (stateAB / powerOfThree[0]) % 3;

                // count black and white pieces
                for (a = 0, i = 0; i < SQUARE_NB; i++)
                    if (myField[i] == WHITE_PIECE)
                        a++;
                for (b = 0, i = 0; i < SQUARE_NB; i++)
                    if (myField[i] == BLACK_PIECE)
                        b++;

                // condition
                if (a + b > nSquaresGroupA + nSquaresGroupB)
                    continue;

                // mark original state
                indexAB[stateAB] = nPositionsAB[a][b];
                origStateAB[a][b][nPositionsAB[a][b]] = stateAB;

                // state counter
                nPositionsAB[a][b]++;
            }
        }

        // group C&D //

        // reserve memory
        for (a = 0; a <= PIECE_PER_PLAYER_COUNT; a++) {
            for (b = 0; b <= PIECE_PER_PLAYER_COUNT; b++) {
                if (a + b > nSquaresGroupC + nSquaresGroupD)
                    continue;
                origStateCD_tmp[a][b] =
                    new uint32_t[mOverN[nSquaresGroupC + nSquaresGroupD][a] *
                                 mOverN[nSquaresGroupC + nSquaresGroupD - a][b]];
                nPositionsCD[a][b] = 0;
            }
        }

        // mark all indexCD as not indexed
        memset(indexCD, NOT_INDEXED,
               4 * MAX_ANZ_POSITION_C * MAX_ANZ_POSITION_D);

        for (stateCD = 0; stateCD < MAX_ANZ_POSITION_C * MAX_ANZ_POSITION_D;
             stateCD++) {
            // new state ?
            if (indexCD[stateCD] == NOT_INDEXED) {
                // zero board
                for (i = 0; i < SQUARE_NB; i++)
                    myField[i] = FREE_SQUARE;

                // make board
                myField[squareIdxGroupC[0]] = (stateCD / powerOfThree[15]) % 3;
                myField[squareIdxGroupC[1]] = (stateCD / powerOfThree[14]) % 3;
                myField[squareIdxGroupC[2]] = (stateCD / powerOfThree[13]) % 3;
                myField[squareIdxGroupC[3]] = (stateCD / powerOfThree[12]) % 3;
                myField[squareIdxGroupC[4]] = (stateCD / powerOfThree[11]) % 3;
                myField[squareIdxGroupC[5]] = (stateCD / powerOfThree[10]) % 3;
                myField[squareIdxGroupC[6]] = (stateCD / powerOfThree[9]) % 3;
                myField[squareIdxGroupC[7]] = (stateCD / powerOfThree[8]) % 3;
                myField[squareIdxGroupD[0]] = (stateCD / powerOfThree[7]) % 3;
                myField[squareIdxGroupD[1]] = (stateCD / powerOfThree[6]) % 3;
                myField[squareIdxGroupD[2]] = (stateCD / powerOfThree[5]) % 3;
                myField[squareIdxGroupD[3]] = (stateCD / powerOfThree[4]) % 3;
                myField[squareIdxGroupD[4]] = (stateCD / powerOfThree[3]) % 3;
                myField[squareIdxGroupD[5]] = (stateCD / powerOfThree[2]) % 3;
                myField[squareIdxGroupD[6]] = (stateCD / powerOfThree[1]) % 3;
                myField[squareIdxGroupD[7]] = (stateCD / powerOfThree[0]) % 3;

                // count black and white pieces
                for (a = 0, i = 0; i < SQUARE_NB; i++)
                    if (myField[i] == WHITE_PIECE)
                        a++;
                for (b = 0, i = 0; i < SQUARE_NB; i++)
                    if (myField[i] == BLACK_PIECE)
                        b++;

                // condition
                if (a + b > nSquaresGroupC + nSquaresGroupD)
                    continue;
                if (a > PIECE_PER_PLAYER_COUNT)
                    continue;
                if (b > PIECE_PER_PLAYER_COUNT)
                    continue;

                // mark orig state
                indexCD[stateCD] = nPositionsCD[a][b];
                symOpCD[stateCD] = SO_DO_NOTHING;
                origStateCD_tmp[a][b][nPositionsCD[a][b]] = stateCD;

                // mark all sym states
                for (i = 0; i < SO_COUNT; i++) {
                    applySymOpOnField(i, myField, symField);

                    symStateCD =
                        symField[squareIdxGroupC[0]] * powerOfThree[15] +
                        symField[squareIdxGroupC[1]] * powerOfThree[14] +
                        symField[squareIdxGroupC[2]] * powerOfThree[13] +
                        symField[squareIdxGroupC[3]] * powerOfThree[12] +
                        symField[squareIdxGroupC[4]] * powerOfThree[11] +
                        symField[squareIdxGroupC[5]] * powerOfThree[10] +
                        symField[squareIdxGroupC[6]] * powerOfThree[9] +
                        symField[squareIdxGroupC[7]] * powerOfThree[8] +
                        symField[squareIdxGroupD[0]] * powerOfThree[7] +
                        symField[squareIdxGroupD[1]] * powerOfThree[6] +
                        symField[squareIdxGroupD[2]] * powerOfThree[5] +
                        symField[squareIdxGroupD[3]] * powerOfThree[4] +
                        symField[squareIdxGroupD[4]] * powerOfThree[3] +
                        symField[squareIdxGroupD[5]] * powerOfThree[2] +
                        symField[squareIdxGroupD[6]] * powerOfThree[1] +
                        symField[squareIdxGroupD[7]] * powerOfThree[0];

                    if (stateCD != symStateCD) {
                        indexCD[symStateCD] = nPositionsCD[a][b];
                        symOpCD[symStateCD] = reverseSymOp[i];
                    }
                }

                // state counter
                nPositionsCD[a][b]++;
            }
        }

        // copy from origStateCD_tmp to origStateCD
        for (a = 0; a <= PIECE_PER_PLAYER_COUNT; a++) {
            for (b = 0; b <= PIECE_PER_PLAYER_COUNT; b++) {
                if (a + b > nSquaresGroupC + nSquaresGroupD)
                    continue;
                origStateCD[a][b] = new uint32_t[nPositionsCD[a][b]];
                std::memset(origStateCD[a][b], 0,
                            sizeof(uint32_t) * nPositionsCD[a][b]);
                for (i = 0; i < nPositionsCD[a][b]; i++)
                    origStateCD[a][b][i] = origStateCD_tmp[a][b][i];
                SAFE_DELETE_ARRAY(origStateCD_tmp[a][b]);
            }
        }

        // moving phase
        for (totalPieceCount = 0, layerNum = 0; totalPieceCount <= 18;
             totalPieceCount++) {
            for (a = 0; a <= totalPieceCount; a++) {
                for (b = 0; b <= totalPieceCount - a; b++) {
                    if (a > PIECE_PER_PLAYER_COUNT)
                        continue;
                    if (b > PIECE_PER_PLAYER_COUNT)
                        continue;
                    if (a + b != totalPieceCount)
                        continue;

                    layerIndex[LAYER_INDEX_MOVING_PHASE][a][b] = layerNum;
                    layer[layerNum].whitePieceCount = a;
                    layer[layerNum].blackPieceCount = b;
                    layer[layerNum].subLayerCount = 0;

                    for (wCD = 0; wCD <= layer[layerNum].whitePieceCount;
                         wCD++) {
                        for (bCD = 0; bCD <= layer[layerNum].blackPieceCount;
                             bCD++) {
                            // calculate number of white and black pieces for
                            // group A&B
                            wAB = layer[layerNum].whitePieceCount - wCD;
                            bAB = layer[layerNum].blackPieceCount - bCD;

                            // conditions
                            if (wCD + wAB != layer[layerNum].whitePieceCount)
                                continue;
                            if (bCD + bAB != layer[layerNum].blackPieceCount)
                                continue;
                            if (wAB + bAB > nSquaresGroupA + nSquaresGroupB)
                                continue;
                            if (wCD + bCD > nSquaresGroupC + nSquaresGroupD)
                                continue;

                            if (layer[layerNum].subLayerCount > 0) {
                                layer[layerNum]
                                    .subLayer[layer[layerNum].subLayerCount]
                                    .maxIndex =
                                    layer[layerNum]
                                        .subLayer[layer[layerNum].subLayerCount -
                                                  1]
                                        .maxIndex +
                                    nPositionsAB[wAB][bAB] *
                                        nPositionsCD[wCD][bCD];
                                layer[layerNum]
                                    .subLayer[layer[layerNum].subLayerCount]
                                    .minIndex =
                                    layer[layerNum]
                                        .subLayer[layer[layerNum].subLayerCount -
                                                  1]
                                        .maxIndex +
                                    1;
                            } else {
                                layer[layerNum]
                                    .subLayer[layer[layerNum].subLayerCount]
                                    .maxIndex = nPositionsAB[wAB][bAB] *
                                                    nPositionsCD[wCD][bCD] -
                                                1;
                                layer[layerNum]
                                    .subLayer[layer[layerNum].subLayerCount]
                                    .minIndex = 0;
                            }
                            layer[layerNum]
                                .subLayer[layer[layerNum].subLayerCount]
                                .nBlackPiecesGroupAB = bAB;
                            layer[layerNum]
                                .subLayer[layer[layerNum].subLayerCount]
                                .nBlackPiecesGroupCD = bCD;
                            layer[layerNum]
                                .subLayer[layer[layerNum].subLayerCount]
                                .nWhitePiecesGroupAB = wAB;
                            layer[layerNum]
                                .subLayer[layer[layerNum].subLayerCount]
                                .nWhitePiecesGroupCD = wCD;
                            layer[layerNum].subLayerIndexAB[wAB][bAB] =
                                layer[layerNum].subLayerCount;
                            layer[layerNum].subLayerIndexCD[wCD][bCD] =
                                layer[layerNum].subLayerCount;
                            layer[layerNum].subLayerCount++;
                        }
                    }
                    layerNum++;
                }
            }
        }

        // placing phase
        for (totalPieceCount = 0, layerNum = LAYER_COUNT - 1;
             totalPieceCount <= 2 * PIECE_PER_PLAYER_COUNT; totalPieceCount++) {
            for (a = 0; a <= totalPieceCount; a++) {
                for (b = 0; b <= totalPieceCount - a; b++) {
                    if (a > PIECE_PER_PLAYER_COUNT)
                        continue;
                    if (b > PIECE_PER_PLAYER_COUNT)
                        continue;
                    if (a + b != totalPieceCount)
                        continue;
                    layer[layerNum].whitePieceCount = a;
                    layer[layerNum].blackPieceCount = b;
                    layerIndex[LAYER_INDEX_PLACING_PHASE][a][b] = layerNum;
                    layer[layerNum].subLayerCount = 0;

                    for (wCD = 0; wCD <= layer[layerNum].whitePieceCount;
                         wCD++) {
                        for (bCD = 0; bCD <= layer[layerNum].blackPieceCount;
                             bCD++) {
                            // calculate number of white and black pieces for
                            // group A&B
                            wAB = layer[layerNum].whitePieceCount - wCD;
                            bAB = layer[layerNum].blackPieceCount - bCD;

                            // conditions
                            if (wCD + wAB != layer[layerNum].whitePieceCount)
                                continue;
                            if (bCD + bAB != layer[layerNum].blackPieceCount)
                                continue;
                            if (wAB + bAB > nSquaresGroupA + nSquaresGroupB)
                                continue;
                            if (wCD + bCD > nSquaresGroupC + nSquaresGroupD)
                                continue;

                            if (layer[layerNum].subLayerCount > 0) {
                                layer[layerNum]
                                    .subLayer[layer[layerNum].subLayerCount]
                                    .maxIndex =
                                    layer[layerNum]
                                        .subLayer[layer[layerNum].subLayerCount -
                                                  1]
                                        .maxIndex +
                                    nPositionsAB[wAB][bAB] *
                                        nPositionsCD[wCD][bCD];
                                layer[layerNum]
                                    .subLayer[layer[layerNum].subLayerCount]
                                    .minIndex =
                                    layer[layerNum]
                                        .subLayer[layer[layerNum].subLayerCount -
                                                  1]
                                        .maxIndex +
                                    1;
                            } else {
                                layer[layerNum]
                                    .subLayer[layer[layerNum].subLayerCount]
                                    .maxIndex = nPositionsAB[wAB][bAB] *
                                                    nPositionsCD[wCD][bCD] -
                                                1;
                                layer[layerNum]
                                    .subLayer[layer[layerNum].subLayerCount]
                                    .minIndex = 0;
                            }
                            layer[layerNum]
                                .subLayer[layer[layerNum].subLayerCount]
                                .nBlackPiecesGroupAB = bAB;
                            layer[layerNum]
                                .subLayer[layer[layerNum].subLayerCount]
                                .nBlackPiecesGroupCD = bCD;
                            layer[layerNum]
                                .subLayer[layer[layerNum].subLayerCount]
                                .nWhitePiecesGroupAB = wAB;
                            layer[layerNum]
                                .subLayer[layer[layerNum].subLayerCount]
                                .nWhitePiecesGroupCD = wCD;
                            layer[layerNum].subLayerIndexAB[wAB][bAB] =
                                layer[layerNum].subLayerCount;
                            layer[layerNum].subLayerIndexCD[wCD][bCD] =
                                layer[layerNum].subLayerCount;
                            layer[layerNum].subLayerCount++;
                        }
                    }
                    layerNum--;
                }
            }
        }

        // write vars into file
        preCalcVarsHeader.sizeInBytes = sizeof(PreCalcedVarsFileHeader);

        WriteFile(hFilePreCalcVars, &preCalcVarsHeader,
                  preCalcVarsHeader.sizeInBytes, &dwBytesWritten, nullptr);
        WriteFile(hFilePreCalcVars, layer, sizeof(Layer) * LAYER_COUNT,
                  &dwBytesWritten, nullptr);
        WriteFile(hFilePreCalcVars, layerIndex,
                  sizeof(uint32_t) * 2 * PIECE_PER_PLAYER_PLUS_ONE_COUNT *
                      PIECE_PER_PLAYER_PLUS_ONE_COUNT,
                  &dwBytesWritten, nullptr);
        WriteFile(hFilePreCalcVars, nPositionsAB,
                  sizeof(uint32_t) * PIECE_PER_PLAYER_PLUS_ONE_COUNT *
                      PIECE_PER_PLAYER_PLUS_ONE_COUNT,
                  &dwBytesWritten, nullptr);
        WriteFile(hFilePreCalcVars, nPositionsCD,
                  sizeof(uint32_t) * PIECE_PER_PLAYER_PLUS_ONE_COUNT *
                      PIECE_PER_PLAYER_PLUS_ONE_COUNT,
                  &dwBytesWritten, nullptr);
        WriteFile(hFilePreCalcVars, indexAB,
                  sizeof(uint32_t) * MAX_ANZ_POSITION_A * MAX_ANZ_POSITION_B,
                  &dwBytesWritten, nullptr);
        WriteFile(hFilePreCalcVars, indexCD,
                  sizeof(uint32_t) * MAX_ANZ_POSITION_C * MAX_ANZ_POSITION_D,
                  &dwBytesWritten, nullptr);
        WriteFile(hFilePreCalcVars, symOpCD,
                  sizeof(unsigned char) * MAX_ANZ_POSITION_C *
                      MAX_ANZ_POSITION_D,
                  &dwBytesWritten, nullptr);
        WriteFile(hFilePreCalcVars, powerOfThree,
                  sizeof(uint32_t) * (nSquaresGroupC + nSquaresGroupD),
                  &dwBytesWritten, nullptr);
        WriteFile(hFilePreCalcVars, symOpTable,
                  sizeof(uint32_t) * SQUARE_NB * SO_COUNT, &dwBytesWritten,
                  nullptr);
        WriteFile(hFilePreCalcVars, reverseSymOp, sizeof(uint32_t) * SO_COUNT,
                  &dwBytesWritten, nullptr);
        WriteFile(hFilePreCalcVars, concSymOp,
                  sizeof(uint32_t) * SO_COUNT * SO_COUNT, &dwBytesWritten,
                  nullptr);
        WriteFile(hFilePreCalcVars, mOverN,
                  sizeof(uint32_t) * (SQUARE_NB + 1) * (SQUARE_NB + 1),
                  &dwBytesWritten, nullptr);
        WriteFile(hFilePreCalcVars, moveValue,
                  sizeof(unsigned char) * SQUARE_NB * SQUARE_NB,
                  &dwBytesWritten, nullptr);
        WriteFile(hFilePreCalcVars, plyInfoForOutput,
                  sizeof(PlyInfoVarType) * SQUARE_NB * SQUARE_NB,
                  &dwBytesWritten, nullptr);
        WriteFile(hFilePreCalcVars, incidencesValuesSubMoves,
                  sizeof(uint32_t) * 4 * SQUARE_NB * SQUARE_NB, &dwBytesWritten,
                  nullptr);

        // process origStateAB[][]
        for (a = 0; a <= PIECE_PER_PLAYER_COUNT; a++) {
            for (b = 0; b <= PIECE_PER_PLAYER_COUNT; b++) {
                if (a + b > nSquaresGroupA + nSquaresGroupB)
                    continue;
                WriteFile(hFilePreCalcVars, origStateAB[a][b],
                          sizeof(uint32_t) * nPositionsAB[a][b],
                          &dwBytesWritten, nullptr);
            }
        }

        // process origStateCD[][]
        for (a = 0; a <= PIECE_PER_PLAYER_COUNT; a++) {
            for (b = 0; b <= PIECE_PER_PLAYER_COUNT; b++) {
                if (a + b > nSquaresGroupC + nSquaresGroupD)
                    continue;
                WriteFile(hFilePreCalcVars, origStateCD[a][b],
                          sizeof(uint32_t) * nPositionsCD[a][b],
                          &dwBytesWritten, nullptr);
            }
        }
    }

    // Close File
    CloseHandle(hFilePreCalcVars);
}

//-----------------------------------------------------------------------------
// ~PerfectAI()
// PerfectAI class destructor
//-----------------------------------------------------------------------------
PerfectAI::~PerfectAI()
{
    // release memory
    for (uint32_t thd = 0; thd < getThreadCount(); thd++) {
        SAFE_DELETE_ARRAY(threadVars[thd].oldStates);
        SAFE_DELETE_ARRAY(threadVars[thd].idPossibilities);
        SAFE_DELETE_ARRAY(threadVars[thd].possibilities);
        threadVars[thd].field->deleteBoard();
    }
    SAFE_DELETE_ARRAY(threadVars);
}

//-----------------------------------------------------------------------------
// play()
//
//-----------------------------------------------------------------------------
void PerfectAI::play(fieldStruct *theField, uint32_t *pushFrom,
                     uint32_t *pushTo)
{
    // ... trick 17
    theField->copyBoard(&dummyField);
    // assert(dummyField.oppPlayer->id >= -1 && dummyField.oppPlayer->id <= 1);

    // locals
    threadVars[0].field = theField;
    threadVars[0].ownId = threadVars[0].field->curPlayer->id;
    uint32_t bestChoice;

    // assert(theField->oppPlayer->id >= -1 && theField->oppPlayer->id <= 1);

    // reset
    for (uint32_t i = 0; i < SQUARE_NB * SQUARE_NB; i++) {
        moveValue[i] = SKV_VALUE_INVALID;
        plyInfoForOutput[i] = PLYINFO_VALUE_INVALID;
        incidencesValuesSubMoves[i][SKV_VALUE_INVALID] = 0;
        incidencesValuesSubMoves[i][SKV_VALUE_GAME_LOST] = 0;
        incidencesValuesSubMoves[i][SKV_VALUE_GAME_DRAWN] = 0;
        incidencesValuesSubMoves[i][SKV_VALUE_GAME_WON] = 0;
    }

    // assert(theField->oppPlayer->id >= -1 && theField->oppPlayer->id <= 1);

    // open database file
    openDatabase(databaseDir.c_str(), POSIBILE_MOVE_COUNT_MAX);

    // assert(theField->oppPlayer->id >= -1 && theField->oppPlayer->id <= 1);

    if (theField->isPlacingPhase)
        threadVars[0].fullTreeDepth = 2;
    else
        threadVars[0].fullTreeDepth = 2;

    // assert(theField->oppPlayer->id >= -1 && theField->oppPlayer->id <= 1);

    // current state already calculated?
    if (isCurStateInDatabase(0)) {
        cout << "PerfectAI is using database!\n\n\n";
        threadVars[0].fullTreeDepth = 3;
    } else {
        cout << "PerfectAI is thinking thinking with a depth of "
             << threadVars[0].fullTreeDepth << " steps!\n\n\n";
    }

    // assert(theField->oppPlayer->id >= -1 && theField->oppPlayer->id <= 1);

    // start the miniMax-algorithm
    const auto rootPossibilities = static_cast<Possibility *>(getBestChoice(
        threadVars[0].fullTreeDepth, &bestChoice, POSIBILE_MOVE_COUNT_MAX));

    // assert(theField->oppPlayer->id >= -1 && theField->oppPlayer->id <= 1);

    // decode the best choice
    if (threadVars[0].field->pieceMustBeRemovedCount) {
        *pushFrom = bestChoice;
        *pushTo = 0;
    } else if (threadVars[0].field->isPlacingPhase) {
        *pushFrom = 0;
        *pushTo = bestChoice;
    } else {
        *pushFrom = rootPossibilities->from[bestChoice];
        *pushTo = rootPossibilities->to[bestChoice];
    }

    // assert(theField->oppPlayer->id >= -1 && theField->oppPlayer->id <= 1);

    // release memory
    threadVars[0].field = &dummyField;

    // assert(theField->oppPlayer->id >= -1 && theField->oppPlayer->id <= 1);
}

//-----------------------------------------------------------------------------
// prepareDatabaseCalc()
//
//-----------------------------------------------------------------------------
void PerfectAI::prepareDatabaseCalc()
{
    // create a temporary board
    for (uint32_t thd = 0; thd < getThreadCount(); thd++) {
        // only prepare layers ?
        threadVars[thd].field = new fieldStruct();
        threadVars[thd].field->createBoard();
        setOpponentLevel(thd, false);
    }

    // open database file
    openDatabase(databaseDir.c_str(), POSIBILE_MOVE_COUNT_MAX);
}

//-----------------------------------------------------------------------------
// wrapUpDatabaseCalc()
//
//-----------------------------------------------------------------------------
void PerfectAI::wrapUpDatabaseCalc(bool calcuAborted)
{
    // release memory
    for (uint32_t thd = 0; thd < getThreadCount(); thd++) {
        threadVars[thd].field->deleteBoard();
        SAFE_DELETE(threadVars[thd].field);
        threadVars[thd].field = &dummyField;
    }
}

//-----------------------------------------------------------------------------
// testLayers()
//
//-----------------------------------------------------------------------------
bool PerfectAI::testLayers(uint32_t startTestFromLayer, uint32_t endTestAtLayer)
{
    // locals
    bool result = true;

    for (uint32_t curLayer = startTestFromLayer; curLayer <= endTestAtLayer;
         curLayer++) {
        closeDatabase();
        if (!openDatabase(databaseDir.c_str(), POSIBILE_MOVE_COUNT_MAX))
            result = false;
        if (!testIfSymStatesHaveSameValue(curLayer))
            result = false;
        if (!testLayer(curLayer))
            result = false;
        unloadAllLayers();
        unloadAllPlyInfos();
        closeDatabase();
    }
    return result;
}

//-----------------------------------------------------------------------------
// setDatabasePath()
//
//-----------------------------------------------------------------------------
bool PerfectAI::setDatabasePath(const char *dir)
{
    if (dir == nullptr) {
        return false;
    }

    cout << "Path to database set to: " << dir << endl;
    databaseDir.assign(dir);
    return true;
}

//-----------------------------------------------------------------------------
// prepareBestChoiceCalc()
//
//-----------------------------------------------------------------------------
void PerfectAI::prepareBestChoiceCalc()
{
    for (uint32_t thd = 0; thd < getThreadCount(); thd++) {
        threadVars[thd].floatValue = 0.0f;
        threadVars[thd].shortValue = SKV_VALUE_INVALID;
        threadVars[thd].gameHasFinished = false;
        threadVars[thd].curSearchDepth = 0;
    }
}

//-----------------------------------------------------------------------------
// ThreadVars()
//
//-----------------------------------------------------------------------------
PerfectAI::ThreadVars::ThreadVars()
{
    field = nullptr;
    floatValue = 0;
    shortValue = 0;
    gameHasFinished = false;
    ownId = 0;
    curSearchDepth = 0;
    fullTreeDepth = 0;
    idPossibilities = nullptr;
    oldStates = nullptr;
    possibilities = nullptr;
    parent = nullptr;
}

//-----------------------------------------------------------------------------
// getPossPlacingPhase()
//
//-----------------------------------------------------------------------------
uint32_t *
PerfectAI::ThreadVars::getPossPlacingPhase(uint32_t *possibilityCount,
                                           void **pPossibilities) const
{
    // locals
    uint32_t i;
    uint32_t *idPossibility =
        &idPossibilities[curSearchDepth * POSIBILE_MOVE_COUNT_MAX];
    bool pieceCanBeRemoved;

    // check if an opponent piece can be removed
    for (pieceCanBeRemoved = false, i = 0; i < SQUARE_NB; i++) {
        if (field->board[i] == field->oppPlayer->id &&
            field->piecePartOfMillCount[i] == 0) {
            pieceCanBeRemoved = true;
            break;
        }
    }

    // possibilities with cut off
    for (*possibilityCount = 0, i = 0; i < SQUARE_NB; i++) {
        // move possible ?
        if (field->board[i] == field->squareIsFree) {
            // check if a mill is beeing closed
            uint32_t nMillsBeeingClosed = 0;
            if (field->curPlayer->id ==
                    field->board[field->neighbor[i][0][0]] &&
                field->curPlayer->id == field->board[field->neighbor[i][0][1]])
                nMillsBeeingClosed++;
            if (field->curPlayer->id ==
                    field->board[field->neighbor[i][1][0]] &&
                field->curPlayer->id == field->board[field->neighbor[i][1][1]])
                nMillsBeeingClosed++;

            // Version 15: don't allow to close two mills at once
            // Version 25: don't allow to close a mill, although no piece can be
            // removed from the opponent
            if (nMillsBeeingClosed < 2 &&
                (nMillsBeeingClosed == 0 || pieceCanBeRemoved)) {
                idPossibility[*possibilityCount] = i;
                (*possibilityCount)++;
            }
        }
    }

    // possibility code is simple
    if (pPossibilities != nullptr)
        *pPossibilities = nullptr;

    return idPossibility;
}

//-----------------------------------------------------------------------------
// getPossNormalMove()
//
//-----------------------------------------------------------------------------
uint32_t *PerfectAI::ThreadVars::getPossNormalMove(uint32_t *possibilityCount,
                                                   void **pPossibilities) const
{
    // locals
    uint32_t from, to, dir;
    uint32_t *idPossibility =
        &idPossibilities[curSearchDepth * POSIBILE_MOVE_COUNT_MAX];
    Possibility *possibility = &possibilities[curSearchDepth];

    // if he is not allowed to spring
    if (field->curPlayer->pieceCount > 3) {
        for (*possibilityCount = 0, from = 0; from < SQUARE_NB; from++) {
            for (dir = 0; dir < MD_NB; dir++) {
                // dest
                to = field->connectedSquare[from][dir];

                // move possible ?
                if (to < SQUARE_NB &&
                    field->board[from] == field->curPlayer->id &&
                    field->board[to] == field->squareIsFree) {
                    // piece is moveable
                    idPossibility[*possibilityCount] = *possibilityCount;
                    possibility->from[*possibilityCount] = from;
                    possibility->to[*possibilityCount] = to;
                    (*possibilityCount)++;

                    // current player is allowed to spring
                }
            }
        }
    } else if (field->curPlayer->pieceCount == 3) {
        for (*possibilityCount = 0, from = 0; from < SQUARE_NB; from++) {
            for (to = 0; to < SQUARE_NB; to++) {
                // move possible ?
                if (field->board[from] == field->curPlayer->id &&
                    field->board[to] == field->squareIsFree &&
                    *possibilityCount < POSIBILE_MOVE_COUNT_MAX) {
                    // piece is moveable
                    idPossibility[*possibilityCount] = *possibilityCount;
                    possibility->from[*possibilityCount] = from;
                    possibility->to[*possibilityCount] = to;
                    (*possibilityCount)++;
                }
            }
        }
    } else {
        *possibilityCount = 0;
    }

    // pass possibilities
    if (pPossibilities != nullptr)
        *pPossibilities = static_cast<void *>(possibility);

    return idPossibility;
}

//-----------------------------------------------------------------------------
// getPossPieceRemove()
//
//-----------------------------------------------------------------------------
uint32_t *PerfectAI::ThreadVars::getPossPieceRemove(uint32_t *possibilityCount,
                                                    void **pPossibilities) const
{
    // locals
    uint32_t i;
    uint32_t *idPossibility =
        &idPossibilities[curSearchDepth * POSIBILE_MOVE_COUNT_MAX];

    // possibilities with cut off
    for (*possibilityCount = 0, i = 0; i < SQUARE_NB; i++) {
        // move possible ?
        if (field->board[i] == field->oppPlayer->id &&
            !field->piecePartOfMillCount[i]) {
            idPossibility[*possibilityCount] = i;
            (*possibilityCount)++;
        }
    }

    // possibility code is simple
    if (pPossibilities != nullptr)
        *pPossibilities = nullptr;

    return idPossibility;
}

//-----------------------------------------------------------------------------
// getPossibilities()
//
//-----------------------------------------------------------------------------
uint32_t *PerfectAI::getPossibilities(uint32_t threadNo,
                                      uint32_t *possibilityCount,
                                      bool *opponentsMove,
                                      void **pPossibilities)
{
    // locals
    bool aPieceCanBeRemovedFromCurPlayer = false;
    uint32_t nMillsCurPlayer = 0;
    uint32_t nMillsOpponentPlayer = 0;

    // set opponentsMove
    const ThreadVars *tv = &threadVars[threadNo];
    *opponentsMove = tv->field->curPlayer->id == tv->ownId ? false : true;

    // count completed mills
    for (uint32_t i = 0; i < SQUARE_NB; i++) {
        if (tv->field->board[i] == tv->field->curPlayer->id)
            nMillsCurPlayer += tv->field->piecePartOfMillCount[i];
        else
            nMillsOpponentPlayer += tv->field->piecePartOfMillCount[i];
        if (tv->field->piecePartOfMillCount[i] == 0 &&
            tv->field->board[i] == tv->field->curPlayer->id)
            aPieceCanBeRemovedFromCurPlayer = true;
    }
    nMillsCurPlayer /= 3;
    nMillsOpponentPlayer /= 3;

    // When game has ended of course nothing happens any more
    if (tv->gameHasFinished ||
        !tv->fieldIntegrityOK(nMillsCurPlayer, nMillsOpponentPlayer,
                              aPieceCanBeRemovedFromCurPlayer)) {
        *possibilityCount = 0;
        return nullptr;
        // look what is to do
    }

    if (tv->field->pieceMustBeRemovedCount)
        return tv->getPossPieceRemove(possibilityCount, pPossibilities);

    if (tv->field->isPlacingPhase)
        return tv->getPossPlacingPhase(possibilityCount, pPossibilities);

    return tv->getPossNormalMove(possibilityCount, pPossibilities);
}

//-----------------------------------------------------------------------------
// getSituationValue()
//
//-----------------------------------------------------------------------------
void PerfectAI::getSituationValue(uint32_t threadNo, float &floatValue,
                                  TwoBit &shortValue)
{
    const ThreadVars *tv = &threadVars[threadNo];
    floatValue = tv->floatValue;
    shortValue = tv->shortValue;
}

//-----------------------------------------------------------------------------
// deletePossibilities()
//
//-----------------------------------------------------------------------------
void PerfectAI::deletePossibilities(uint32_t threadNo, void *pPossibilities) { }

//-----------------------------------------------------------------------------
// undo()
//
//-----------------------------------------------------------------------------
void PerfectAI::undo(uint32_t threadNo, uint32_t idPossibility,
                     bool opponentsMove, void *pBackup, void *pPossibilities)
{
    // locals
    ThreadVars *tv = &threadVars[threadNo];
    const auto oldState = static_cast<Backup *>(pBackup);

    // reset old value
    tv->floatValue = oldState->floatValue;
    tv->shortValue = oldState->shortValue;
    tv->gameHasFinished = oldState->gameHasFinished;
    tv->curSearchDepth--;

    tv->field->curPlayer = oldState->curPlayer;
    tv->field->oppPlayer = oldState->oppPlayer;
    tv->field->curPlayer->pieceCount = oldState->curPieceCount;
    tv->field->oppPlayer->pieceCount = oldState->oppPieceCount;
    tv->field->curPlayer->removedPiecesCount = oldState->curMissPieces;
    tv->field->oppPlayer->removedPiecesCount = oldState->oppMissPieces;
    tv->field->curPlayer->possibleMovesCount = oldState->curPosMoves;
    tv->field->oppPlayer->possibleMovesCount = oldState->oppPosMoves;
    tv->field->isPlacingPhase = oldState->isPlacingPhase;
    tv->field->piecePlacedCount = oldState->piecePlacedCount;
    tv->field->pieceMustBeRemovedCount = oldState->pieceMustBeRemovedCount;
    tv->field->board[oldState->from] = oldState->fieldFrom;
    tv->field->board[oldState->to] = oldState->fieldTo;

    // very expensive
    for (int i = 0; i < SQUARE_NB; i++) {
        tv->field->piecePartOfMillCount[i] = oldState->piecePartOfMillCount[i];
    }
}

//-----------------------------------------------------------------------------
// setWarning()
//
//-----------------------------------------------------------------------------
inline void PerfectAI::ThreadVars::setWarning(uint32_t pieceOne,
                                              uint32_t pieceTwo,
                                              uint32_t pieceThree) const
{
    // if all 3 fields are occupied by current player than he closed a mill
    if (field->board[pieceOne] == field->curPlayer->id &&
        field->board[pieceTwo] == field->curPlayer->id &&
        field->board[pieceThree] == field->curPlayer->id) {
        field->piecePartOfMillCount[pieceOne]++;
        field->piecePartOfMillCount[pieceTwo]++;
        field->piecePartOfMillCount[pieceThree]++;
        field->pieceMustBeRemovedCount = 1;
    }

    // is a mill destroyed ?
    if (field->board[pieceOne] == field->squareIsFree &&
        field->piecePartOfMillCount[pieceOne] &&
        field->piecePartOfMillCount[pieceTwo] &&
        field->piecePartOfMillCount[pieceThree]) {
        field->piecePartOfMillCount[pieceOne]--;
        field->piecePartOfMillCount[pieceTwo]--;
        field->piecePartOfMillCount[pieceThree]--;
    }
}

//-----------------------------------------------------------------------------
// updateWarning()
//
//-----------------------------------------------------------------------------
inline void PerfectAI::ThreadVars::updateWarning(uint32_t firstPiece,
                                                 uint32_t secondPiece) const
{
    // set warnings
    if (firstPiece < SQUARE_NB)
        this->setWarning(firstPiece, field->neighbor[firstPiece][0][0],
                         field->neighbor[firstPiece][0][1]);
    if (firstPiece < SQUARE_NB)
        this->setWarning(firstPiece, field->neighbor[firstPiece][1][0],
                         field->neighbor[firstPiece][1][1]);

    if (secondPiece < SQUARE_NB)
        this->setWarning(secondPiece, field->neighbor[secondPiece][0][0],
                         field->neighbor[secondPiece][0][1]);
    if (secondPiece < SQUARE_NB)
        this->setWarning(secondPiece, field->neighbor[secondPiece][1][0],
                         field->neighbor[secondPiece][1][1]);

    // no piece must be removed if each belongs to a mill
    uint32_t i;
    bool atLeastOnePieceRemoveAble = false;
    if (field->pieceMustBeRemovedCount) {
        for (i = 0; i < SQUARE_NB; i++) {
            if (field->piecePartOfMillCount[i] == 0 &&
                field->board[i] == field->oppPlayer->id) {
                atLeastOnePieceRemoveAble = true;
                break;
            }
        }
    }
    if (!atLeastOnePieceRemoveAble)
        field->pieceMustBeRemovedCount = 0;
}

//-----------------------------------------------------------------------------
// updatePossibleMoves()
//
//-----------------------------------------------------------------------------
inline void
PerfectAI::ThreadVars::updatePossibleMoves(uint32_t piece, Player *pieceOwner,
                                           bool pieceRemoved,
                                           uint32_t ignorePiece) const
{
    // look into every direction
    for (uint32_t direction = 0; direction < MD_NB; direction++) {
        const uint32_t neighbor = field->connectedSquare[piece][direction];

        // neighbor must exist
        if (neighbor < SQUARE_NB) {
            // relevant when moving from one square to another connected square
            if (ignorePiece == neighbor)
                continue;

            // if there is no neighbor piece than it only affects the actual
            // piece
            if (field->board[neighbor] == field->squareIsFree) {
                if (pieceRemoved)
                    pieceOwner->possibleMovesCount--;
                else
                    pieceOwner->possibleMovesCount++;

                // if there is a neighbor piece than it effects only this one
            } else if (field->board[neighbor] == field->curPlayer->id) {
                if (pieceRemoved)
                    field->curPlayer->possibleMovesCount++;
                else
                    field->curPlayer->possibleMovesCount--;
            } else {
                if (pieceRemoved)
                    field->oppPlayer->possibleMovesCount++;
                else
                    field->oppPlayer->possibleMovesCount--;
            }
        }
    }

    // only 3 pieces resting
    if (field->curPlayer->pieceCount <= 3 && !field->isPlacingPhase)
        field->curPlayer->possibleMovesCount = field->curPlayer->pieceCount *
                                               (SQUARE_NB -
                                                field->curPlayer->pieceCount -
                                                field->oppPlayer->pieceCount);
    if (field->oppPlayer->pieceCount <= 3 && !field->isPlacingPhase)
        field->oppPlayer->possibleMovesCount = field->oppPlayer->pieceCount *
                                               (SQUARE_NB -
                                                field->curPlayer->pieceCount -
                                                field->oppPlayer->pieceCount);
}

//-----------------------------------------------------------------------------
// setPiece()
//
//-----------------------------------------------------------------------------
inline void PerfectAI::ThreadVars::setPiece(uint32_t to, Backup *backup) const
{
    // backup
    backup->from = SQUARE_NB;
    backup->to = to;
    backup->fieldFrom = SQUARE_NB;
    backup->fieldTo = field->board[to];

    // set piece into board
    field->board[to] = field->curPlayer->id;
    field->curPlayer->pieceCount++;
    field->piecePlacedCount++;

    // placing phase finished ?
    if (field->piecePlacedCount == 18)
        field->isPlacingPhase = false;

    // update possible moves
    updatePossibleMoves(to, field->curPlayer, false, SQUARE_NB);

    // update warnings
    updateWarning(to, SQUARE_NB);
}

//-----------------------------------------------------------------------------
// normalMove()
//
//-----------------------------------------------------------------------------
inline void PerfectAI::ThreadVars::normalMove(uint32_t from, uint32_t to,
                                              Backup *backup) const
{
    // backup
    backup->from = from;
    backup->to = to;
    backup->fieldFrom = field->board[from];
    backup->fieldTo = field->board[to];

    // set piece into board
    field->board[from] = field->squareIsFree;
    field->board[to] = field->curPlayer->id;

    // update possible moves
    updatePossibleMoves(from, field->curPlayer, true, to);
    updatePossibleMoves(to, field->curPlayer, false, from);

    // update warnings
    updateWarning(from, to);
}

//-----------------------------------------------------------------------------
// removePiece()
//
//-----------------------------------------------------------------------------
inline void PerfectAI::ThreadVars::removePiece(uint32_t from, Backup *backup)
{
    // backup
    backup->from = from;
    backup->to = SQUARE_NB;
    backup->fieldFrom = field->board[from];
    backup->fieldTo = SQUARE_NB;

    // remove piece
    field->board[from] = field->squareIsFree;
    field->oppPlayer->pieceCount--;
    field->oppPlayer->removedPiecesCount++;
    field->pieceMustBeRemovedCount--;

    // update possible moves
    updatePossibleMoves(from, field->oppPlayer, true, SQUARE_NB);

    // update warnings
    updateWarning(from, SQUARE_NB);

    // end of game ?
    if (field->oppPlayer->pieceCount < 3 && !field->isPlacingPhase)
        gameHasFinished = true;
}

//-----------------------------------------------------------------------------
// move()
//
//-----------------------------------------------------------------------------
void PerfectAI::move(uint32_t threadNo, uint32_t idPossibility,
                     bool opponentsMove, void **pBackup, void *pPossibilities)
{
    // locals
    ThreadVars *tv = &threadVars[threadNo];
    Backup *oldState = &tv->oldStates[tv->curSearchDepth];
    const auto tmpPossibility = static_cast<Possibility *>(pPossibilities);
    Player *tmpPlayer;

    // calculate place of piece
    *pBackup = static_cast<void *>(oldState);
    oldState->floatValue = tv->floatValue;
    oldState->shortValue = tv->shortValue;
    oldState->gameHasFinished = tv->gameHasFinished;
    oldState->curPlayer = tv->field->curPlayer;
    oldState->oppPlayer = tv->field->oppPlayer;
    oldState->curPieceCount = tv->field->curPlayer->pieceCount;
    oldState->oppPieceCount = tv->field->oppPlayer->pieceCount;
    oldState->curPosMoves = tv->field->curPlayer->possibleMovesCount;
    oldState->oppPosMoves = tv->field->oppPlayer->possibleMovesCount;
    oldState->curMissPieces = tv->field->curPlayer->removedPiecesCount;
    oldState->oppMissPieces = tv->field->oppPlayer->removedPiecesCount;
    oldState->isPlacingPhase = tv->field->isPlacingPhase;
    oldState->piecePlacedCount = tv->field->piecePlacedCount;
    oldState->pieceMustBeRemovedCount = tv->field->pieceMustBeRemovedCount;
    tv->curSearchDepth++;

    // very expensive
    for (uint32_t i = 0; i < SQUARE_NB; i++) {
        oldState->piecePartOfMillCount[i] = tv->field->piecePartOfMillCount[i];
    }

    // move
    if (tv->field->pieceMustBeRemovedCount) {
        tv->removePiece(idPossibility, oldState);
    } else if (tv->field->isPlacingPhase) {
        tv->setPiece(idPossibility, oldState);
    } else {
        tv->normalMove(tmpPossibility->from[idPossibility],
                       tmpPossibility->to[idPossibility], oldState);
    }

    // when opponent is unable to move than current player has won
    if (!tv->field->oppPlayer->possibleMovesCount &&
        !tv->field->isPlacingPhase && !tv->field->pieceMustBeRemovedCount &&
        tv->field->oppPlayer->pieceCount > 3)
        tv->gameHasFinished = true;

    // when game has finished - perfect for the current player
    if (tv->gameHasFinished && !opponentsMove)
        tv->shortValue = SKV_VALUE_GAME_WON;
    if (tv->gameHasFinished && opponentsMove)
        tv->shortValue = SKV_VALUE_GAME_LOST;

    tv->floatValue = tv->shortValue;

    // calculate value
    if (!opponentsMove)
        tv->floatValue = static_cast<float>(
                             tv->field->oppPlayer->removedPiecesCount) -
                         tv->field->curPlayer->removedPiecesCount +
                         tv->field->pieceMustBeRemovedCount +
                         tv->field->curPlayer->possibleMovesCount * 0.1f -
                         tv->field->oppPlayer->possibleMovesCount * 0.1f;
    else
        tv->floatValue = static_cast<float>(
                             tv->field->curPlayer->removedPiecesCount) -
                         tv->field->oppPlayer->removedPiecesCount -
                         tv->field->pieceMustBeRemovedCount +
                         tv->field->oppPlayer->possibleMovesCount * 0.1f -
                         tv->field->curPlayer->possibleMovesCount * 0.1f;

    // when game has finished - perfect for the current player
    if (tv->gameHasFinished && !opponentsMove)
        tv->floatValue = VALUE_GAME_WON - tv->curSearchDepth;
    if (tv->gameHasFinished && opponentsMove)
        tv->floatValue = VALUE_GAME_LOST + tv->curSearchDepth;

    // set next player
    if (!tv->field->pieceMustBeRemovedCount) {
        tmpPlayer = tv->field->curPlayer;
        tv->field->curPlayer = tv->field->oppPlayer;
        tv->field->oppPlayer = tmpPlayer;
    }
}

//-----------------------------------------------------------------------------
// storeMoveValue()
//
//-----------------------------------------------------------------------------
void PerfectAI::storeMoveValue(uint32_t threadNo, uint32_t idPossibility,
                               void *pPossibilities, unsigned char value,
                               uint32_t *freqValuesSubMoves,
                               PlyInfoVarType plyInfo)
{
    // locals
    const ThreadVars *tv = &threadVars[threadNo];
    uint32_t i;
    const auto tmpPossibility = static_cast<Possibility *>(pPossibilities);

    if (tv->field->pieceMustBeRemovedCount)
        i = idPossibility;
    else if (tv->field->isPlacingPhase)
        i = idPossibility;
    else
        i = tmpPossibility->from[idPossibility] * SQUARE_NB +
            tmpPossibility->to[idPossibility];

    plyInfoForOutput[i] = plyInfo;
    moveValue[i] = value;
    incidencesValuesSubMoves[i][SKV_VALUE_INVALID] =
        freqValuesSubMoves[SKV_VALUE_INVALID];
    incidencesValuesSubMoves[i][SKV_VALUE_GAME_LOST] =
        freqValuesSubMoves[SKV_VALUE_GAME_LOST];
    incidencesValuesSubMoves[i][SKV_VALUE_GAME_DRAWN] =
        freqValuesSubMoves[SKV_VALUE_GAME_DRAWN];
    incidencesValuesSubMoves[i][SKV_VALUE_GAME_WON] =
        freqValuesSubMoves[SKV_VALUE_GAME_WON];
}

//-----------------------------------------------------------------------------
// printMoveInfo()
//
//-----------------------------------------------------------------------------
void PerfectAI::printMoveInfo(uint32_t threadNo, uint32_t idPossibility,
                              void *pPossibilities)
{
    // locals
    const ThreadVars *tv = &threadVars[threadNo];
    const auto tmpPossibility = static_cast<Possibility *>(pPossibilities);

    // move
    if (tv->field->pieceMustBeRemovedCount)
        cout << "remove piece from " << static_cast<char>(idPossibility + 97);
    else if (tv->field->isPlacingPhase)
        cout << "set piece to " << static_cast<char>(idPossibility + 97);
    else
        cout << "move from "
             << static_cast<char>(tmpPossibility->from[idPossibility] + 97)
             << " to "
             << static_cast<char>(tmpPossibility->to[idPossibility] + 97);
}

//-----------------------------------------------------------------------------
// getNumberOfLayers()
// called one time
//-----------------------------------------------------------------------------
uint32_t PerfectAI::getNumberOfLayers()
{
    return LAYER_COUNT;
}

//-----------------------------------------------------------------------------
// shallRetroAnalysisBeUsed()
// called one time for each layer time
//-----------------------------------------------------------------------------
bool PerfectAI::shallRetroAnalysisBeUsed(uint32_t layerNum)
{
    if (layerNum < 100)
        return true;

    return false;
}

//-----------------------------------------------------------------------------
// getNumberOfKnotsInLayer()
// called one time
//-----------------------------------------------------------------------------
uint32_t PerfectAI::getNumberOfKnotsInLayer(uint32_t layerNum)
{
    // locals
    uint32_t nKnots =
        layer[layerNum].subLayer[layer[layerNum].subLayerCount - 1].maxIndex +
        1;

    // times two since either an own piece must be moved or an opponent piece
    // must be removed
    nKnots *= MAX_NUM_PIECES_REMOVED_MINUS_1;

    // return zero if layer is not reachable
    if (((layer[layerNum].blackPieceCount < 2 ||
          layer[layerNum].whitePieceCount < 2) &&
         layerNum < 100) // moving phase
        || (layerNum < LAYER_COUNT && layer[layerNum].blackPieceCount == 2 &&
            layer[layerNum].whitePieceCount == 2 && layerNum < 100) ||
        layerNum == 100)
        return 0;

    // another way
    return nKnots;
}

//-----------------------------------------------------------------------------
// nOverN()
// called seldom
//-----------------------------------------------------------------------------
int64_t PerfectAI::mOverN_Function(uint32_t m, uint32_t n)
{
    // locals
    int64_t result = 1;
    int64_t fakN = 1;
    uint32_t i;

    // invalid params ?
    if (n > m)
        return 0;

    // flip, since then the result value won't get so high
    if (n > m / 2)
        n = m - n;

    // calculate number of possibilities one can put n different pieces in m
    // holes
    for (i = m - n + 1; i <= m; i++)
        result *= i;

    // calculate number of possibilities one can sort n different pieces
    for (i = 1; i <= n; i++)
        fakN *= i;

    // divide
    result /= fakN;

    return result;
}

//-----------------------------------------------------------------------------
// applySymOpOnField()
// called very often
//-----------------------------------------------------------------------------
void PerfectAI::applySymOpOnField(unsigned char symOpNumber,
                                  const uint32_t *sourceField,
                                  uint32_t *destField) const
{
    for (uint32_t i = 0; i < SQUARE_NB; i++) {
        destField[i] = sourceField[symOpTable[symOpNumber][i]];
    }
}

//-----------------------------------------------------------------------------
// getLayerNumber()
//
//-----------------------------------------------------------------------------
uint32_t PerfectAI::getLayerNumber(uint32_t threadNo)
{
    const ThreadVars *tv = &threadVars[threadNo];
    const uint32_t blackPieceCount = tv->field->oppPlayer->pieceCount;
    const uint32_t whitePieceCount = tv->field->curPlayer->pieceCount;
    const uint32_t phaseIndex = tv->field->isPlacingPhase == true ?
                                    LAYER_INDEX_PLACING_PHASE :
                                    LAYER_INDEX_MOVING_PHASE;
    return layerIndex[phaseIndex][whitePieceCount][blackPieceCount];
}

//-----------------------------------------------------------------------------
// getLayerAndStateNumber()
//
//-----------------------------------------------------------------------------
uint32_t PerfectAI::getLayerAndStateNumber(uint32_t threadNo,
                                           uint32_t &layerNum,
                                           uint32_t &stateNumber)
{
    const ThreadVars *tv = &threadVars[threadNo];
    return tv->getLayerAndStateNumber(layerNum, stateNumber);
}

//-----------------------------------------------------------------------------
// getLayerAndStateNumber()
// Current player has white pieces, the opponent the black ones.
//-----------------------------------------------------------------------------
uint32_t
PerfectAI::ThreadVars::getLayerAndStateNumber(uint32_t &layerNum,
                                              uint32_t &stateNumber) const
{
    // locals
    uint32_t myField[SQUARE_NB];
    uint32_t symField[SQUARE_NB];
    const uint32_t blackPieceCount = field->oppPlayer->pieceCount;
    const uint32_t whitePieceCount = field->curPlayer->pieceCount;
    const uint32_t phaseIndex = field->isPlacingPhase == true ?
                                    LAYER_INDEX_PLACING_PHASE :
                                    LAYER_INDEX_MOVING_PHASE;
    uint32_t wCD = 0, bCD = 0;

    // layer number
    layerNum = parent->layerIndex[phaseIndex][whitePieceCount][blackPieceCount];

    // make white and black fields
    for (uint32_t i = 0; i < SQUARE_NB; i++) {
        if (field->board[i] == fieldStruct::squareIsFree) {
            myField[i] = FREE_SQUARE;
        } else if (field->board[i] == field->curPlayer->id) {
            myField[i] = WHITE_PIECE;
            if (fieldPosIsOfGroup[i] == GROUP_C)
                wCD++;
            if (fieldPosIsOfGroup[i] == GROUP_D)
                wCD++;
        } else {
            myField[i] = BLACK_PIECE;
            if (fieldPosIsOfGroup[i] == GROUP_C)
                bCD++;
            if (fieldPosIsOfGroup[i] == GROUP_D)
                bCD++;
        }
    }

    // calculate stateCD
    const uint32_t stateCD =
        myField[squareIdxGroupC[0]] * parent->powerOfThree[15] +
        myField[squareIdxGroupC[1]] * parent->powerOfThree[14] +
        myField[squareIdxGroupC[2]] * parent->powerOfThree[13] +
        myField[squareIdxGroupC[3]] * parent->powerOfThree[12] +
        myField[squareIdxGroupC[4]] * parent->powerOfThree[11] +
        myField[squareIdxGroupC[5]] * parent->powerOfThree[10] +
        myField[squareIdxGroupC[6]] * parent->powerOfThree[9] +
        myField[squareIdxGroupC[7]] * parent->powerOfThree[8] +
        myField[squareIdxGroupD[0]] * parent->powerOfThree[7] +
        myField[squareIdxGroupD[1]] * parent->powerOfThree[6] +
        myField[squareIdxGroupD[2]] * parent->powerOfThree[5] +
        myField[squareIdxGroupD[3]] * parent->powerOfThree[4] +
        myField[squareIdxGroupD[4]] * parent->powerOfThree[3] +
        myField[squareIdxGroupD[5]] * parent->powerOfThree[2] +
        myField[squareIdxGroupD[6]] * parent->powerOfThree[1] +
        myField[squareIdxGroupD[7]] * parent->powerOfThree[0];

    // apply symmetry operation on group A&B
    parent->applySymOpOnField(parent->symOpCD[stateCD], myField, symField);

    // calculate stateAB
    const uint32_t stateAB =
        symField[squareIdxGroupA[0]] * parent->powerOfThree[7] +
        symField[squareIdxGroupA[1]] * parent->powerOfThree[6] +
        symField[squareIdxGroupA[2]] * parent->powerOfThree[5] +
        symField[squareIdxGroupA[3]] * parent->powerOfThree[4] +
        symField[squareIdxGroupB[0]] * parent->powerOfThree[3] +
        symField[squareIdxGroupB[1]] * parent->powerOfThree[2] +
        symField[squareIdxGroupB[2]] * parent->powerOfThree[1] +
        symField[squareIdxGroupB[3]] * parent->powerOfThree[0];

    // calculate index
    stateNumber =
        parent->layer[layerNum]
                .subLayer[parent->layer[layerNum].subLayerIndexCD[wCD][bCD]]
                .minIndex *
            MAX_NUM_PIECES_REMOVED_MINUS_1 +
        parent->indexAB[stateAB] * parent->nPositionsCD[wCD][bCD] *
            MAX_NUM_PIECES_REMOVED_MINUS_1 +
        parent->indexCD[stateCD] * MAX_NUM_PIECES_REMOVED_MINUS_1 +
        field->pieceMustBeRemovedCount;

    return parent->symOpCD[stateCD];
}

//-----------------------------------------------------------------------------
// setSituation()
// Current player has white pieces, the opponent the black ones.
//     Sets up the game situation corresponding to the passed layer number and
//     state.
//-----------------------------------------------------------------------------
bool PerfectAI::setSituation(uint32_t threadNo, uint32_t layerNum,
                             uint32_t stateNumber)
{
    // params ok ?
    if (getNumberOfLayers() <= layerNum)
        return false;
    if (getNumberOfKnotsInLayer(layerNum) <= stateNumber)
        return false;

    // locals
    ThreadVars *tv = &threadVars[threadNo];
    uint32_t myField[SQUARE_NB];
    uint32_t symField[SQUARE_NB];
    const uint32_t whitePieceCount = layer[layerNum].whitePieceCount;
    const uint32_t blackPieceCount = layer[layerNum].blackPieceCount;
    uint32_t nMillsCurPlayer = 0;
    uint32_t nMillsOpponentPlayer = 0;
    uint32_t wCD = 0, bCD = 0, wAB = 0, bAB = 0;
    uint32_t i;
    bool aPieceCanBeRemovedFromCurPlayer;

    // get wCD, bCD, wAB, bAB
    for (i = 0; i <= layer[layerNum].subLayerCount; i++) {
        if (layer[layerNum].subLayer[i].minIndex <=
                stateNumber / MAX_NUM_PIECES_REMOVED_MINUS_1 &&
            layer[layerNum].subLayer[i].maxIndex >=
                stateNumber / MAX_NUM_PIECES_REMOVED_MINUS_1) {
            wCD = layer[layerNum].subLayer[i].nWhitePiecesGroupCD;
            bCD = layer[layerNum].subLayer[i].nBlackPiecesGroupCD;
            wAB = layer[layerNum].subLayer[i].nWhitePiecesGroupAB;
            bAB = layer[layerNum].subLayer[i].nBlackPiecesGroupAB;
            break;
        }
    }

    // reset values
    tv->curSearchDepth = 0;
    tv->floatValue = 0.0f;
    tv->shortValue = SKV_VALUE_GAME_DRAWN;
    tv->gameHasFinished = false;

    tv->field->isPlacingPhase = layerNum >= LAYER_COUNT / 2 ?
                                    LAYER_INDEX_PLACING_PHASE :
                                    LAYER_INDEX_MOVING_PHASE;
    tv->field->pieceMustBeRemovedCount = stateNumber %
                                         MAX_NUM_PIECES_REMOVED_MINUS_1;
    tv->field->curPlayer->pieceCount = whitePieceCount;
    tv->field->oppPlayer->pieceCount = blackPieceCount;

    // reconstruct board->board[]
    const uint32_t stateNumberWithInSubLayer =
        stateNumber / MAX_NUM_PIECES_REMOVED_MINUS_1 -
        layer[layerNum]
            .subLayer[layer[layerNum].subLayerIndexCD[wCD][bCD]]
            .minIndex;
    const uint32_t stateNumberWithInAB = stateNumberWithInSubLayer /
                                         nPositionsCD[wCD][bCD];
    const uint32_t stateNumberWithInCD = stateNumberWithInSubLayer %
                                         nPositionsCD[wCD][bCD];

    // get stateCD
    const uint32_t stateCD = origStateCD[wCD][bCD][stateNumberWithInCD];
    const uint32_t stateAB = origStateAB[wAB][bAB][stateNumberWithInAB];

    // set myField from stateCD and stateAB
    myField[squareIdxGroupA[0]] = (stateAB / powerOfThree[7]) % 3;
    myField[squareIdxGroupA[1]] = (stateAB / powerOfThree[6]) % 3;
    myField[squareIdxGroupA[2]] = (stateAB / powerOfThree[5]) % 3;
    myField[squareIdxGroupA[3]] = (stateAB / powerOfThree[4]) % 3;
    myField[squareIdxGroupB[0]] = (stateAB / powerOfThree[3]) % 3;
    myField[squareIdxGroupB[1]] = (stateAB / powerOfThree[2]) % 3;
    myField[squareIdxGroupB[2]] = (stateAB / powerOfThree[1]) % 3;
    myField[squareIdxGroupB[3]] = (stateAB / powerOfThree[0]) % 3;

    myField[squareIdxGroupC[0]] = (stateCD / powerOfThree[15]) % 3;
    myField[squareIdxGroupC[1]] = (stateCD / powerOfThree[14]) % 3;
    myField[squareIdxGroupC[2]] = (stateCD / powerOfThree[13]) % 3;
    myField[squareIdxGroupC[3]] = (stateCD / powerOfThree[12]) % 3;
    myField[squareIdxGroupC[4]] = (stateCD / powerOfThree[11]) % 3;
    myField[squareIdxGroupC[5]] = (stateCD / powerOfThree[10]) % 3;
    myField[squareIdxGroupC[6]] = (stateCD / powerOfThree[9]) % 3;
    myField[squareIdxGroupC[7]] = (stateCD / powerOfThree[8]) % 3;
    myField[squareIdxGroupD[0]] = (stateCD / powerOfThree[7]) % 3;
    myField[squareIdxGroupD[1]] = (stateCD / powerOfThree[6]) % 3;
    myField[squareIdxGroupD[2]] = (stateCD / powerOfThree[5]) % 3;
    myField[squareIdxGroupD[3]] = (stateCD / powerOfThree[4]) % 3;
    myField[squareIdxGroupD[4]] = (stateCD / powerOfThree[3]) % 3;
    myField[squareIdxGroupD[5]] = (stateCD / powerOfThree[2]) % 3;
    myField[squareIdxGroupD[6]] = (stateCD / powerOfThree[1]) % 3;
    myField[squareIdxGroupD[7]] = (stateCD / powerOfThree[0]) % 3;

    // apply symmetry operation on group A&B
    applySymOpOnField(reverseSymOp[symOpCD[stateCD]], myField, symField);

    // translate symField[] to board->board[]
    for (i = 0; i < SQUARE_NB; i++) {
        if (symField[i] == FREE_SQUARE)
            tv->field->board[i] = fieldStruct::squareIsFree;
        else if (symField[i] == WHITE_PIECE)
            tv->field->board[i] = tv->field->curPlayer->id;
        else
            tv->field->board[i] = tv->field->oppPlayer->id;
    }

    // calculate possible moves
    tv->generateMoves(tv->field->curPlayer);
    tv->generateMoves(tv->field->oppPlayer);

    // zero
    for (i = 0; i < SQUARE_NB; i++) {
        tv->field->piecePartOfMillCount[i] = 0;
    }

    // go in every direction
    for (i = 0; i < SQUARE_NB; i++) {
        tv->setWarningAndMill(i, tv->field->neighbor[i][0][0],
                              tv->field->neighbor[i][0][1]);
        tv->setWarningAndMill(i, tv->field->neighbor[i][1][0],
                              tv->field->neighbor[i][1][1]);
    }

    // since every mill was detected 3 times
    for (i = 0; i < SQUARE_NB; i++)
        tv->field->piecePartOfMillCount[i] /= 3;

    // count completed mills
    for (i = 0; i < SQUARE_NB; i++) {
        if (tv->field->board[i] == tv->field->curPlayer->id)
            nMillsCurPlayer += tv->field->piecePartOfMillCount[i];
        else
            nMillsOpponentPlayer += tv->field->piecePartOfMillCount[i];
    }

    nMillsCurPlayer /= 3;
    nMillsOpponentPlayer /= 3;

    // piecePlacedCount & removedPiecesCount
    if (tv->field->isPlacingPhase) {
        // BUG: ... This calculation is not correct! It is possible that some
        // mills did not cause a piece removal.
        tv->field->curPlayer->removedPiecesCount = nMillsOpponentPlayer;
        tv->field->oppPlayer->removedPiecesCount =
            nMillsCurPlayer - tv->field->pieceMustBeRemovedCount;
        tv->field->piecePlacedCount = tv->field->curPlayer->pieceCount +
                                      tv->field->oppPlayer->pieceCount +
                                      tv->field->curPlayer->removedPiecesCount +
                                      tv->field->oppPlayer->removedPiecesCount;
    } else {
        tv->field->piecePlacedCount = 18;
        tv->field->curPlayer->removedPiecesCount = 9 - tv->field->curPlayer
                                                           ->pieceCount;
        tv->field->oppPlayer->removedPiecesCount = 9 - tv->field->oppPlayer
                                                           ->pieceCount;
    }

    // when opponent is unable to move than current player has won
    if (!tv->field->curPlayer->possibleMovesCount &&
        !tv->field->isPlacingPhase && !tv->field->pieceMustBeRemovedCount &&
        tv->field->curPlayer->pieceCount > 3) {
        tv->gameHasFinished = true;
        tv->shortValue = SKV_VALUE_GAME_LOST;
    }
    if (tv->field->curPlayer->pieceCount < 3 && !tv->field->isPlacingPhase) {
        tv->gameHasFinished = true;
        tv->shortValue = SKV_VALUE_GAME_LOST;
    }
    if (tv->field->oppPlayer->pieceCount < 3 && !tv->field->isPlacingPhase) {
        tv->gameHasFinished = true;
        tv->shortValue = SKV_VALUE_GAME_WON;
    }

    tv->floatValue = tv->shortValue;

    // precalc aPieceCanBeRemovedFromCurPlayer
    for (aPieceCanBeRemovedFromCurPlayer = false, i = 0; i < SQUARE_NB; i++) {
        if (tv->field->piecePartOfMillCount[i] == 0 &&
            tv->field->board[i] == tv->field->curPlayer->id) {
            aPieceCanBeRemovedFromCurPlayer = true;
            break;
        }
    }

    // test if board is ok
    return tv->fieldIntegrityOK(nMillsCurPlayer, nMillsOpponentPlayer,
                                aPieceCanBeRemovedFromCurPlayer);
}

//-----------------------------------------------------------------------------
// generateMoves()
//
//-----------------------------------------------------------------------------
void PerfectAI::ThreadVars::generateMoves(Player *player) const
{
    // locals
    uint32_t i, k, movingDirection;

    for (player->possibleMovesCount = 0, i = 0; i < SQUARE_NB; i++) {
        for (uint32_t j = 0; j < SQUARE_NB; j++) {
            // is piece from player ?
            if (field->board[i] != player->id)
                continue;

            // is dest free ?
            if (field->board[j] != field->squareIsFree)
                continue;

            // when current player has only 3 pieces he is allowed to spring his
            // piece
            if (player->pieceCount > 3 || field->isPlacingPhase) {
                // determine moving direction
                for (k = 0, movingDirection = MD_NB; k < MD_NB; k++)
                    if (field->connectedSquare[i][k] == j)
                        movingDirection = k;

                // are both squares connected ?
                if (movingDirection == 4)
                    continue;
            }

            // everything is ok
            player->possibleMovesCount++;
        }
    }
}

//-----------------------------------------------------------------------------
// setWarningAndMill()
//
//-----------------------------------------------------------------------------
void PerfectAI::ThreadVars::setWarningAndMill(uint32_t piece,
                                              uint32_t firstNeighbor,
                                              uint32_t secondNeighbor) const
{
    // locals
    const int rowOwner = field->board[piece];

    // mill closed ?
    if (rowOwner != field->squareIsFree &&
        field->board[firstNeighbor] == rowOwner &&
        field->board[secondNeighbor] == rowOwner) {
        field->piecePartOfMillCount[piece]++;
        field->piecePartOfMillCount[firstNeighbor]++;
        field->piecePartOfMillCount[secondNeighbor]++;
    }
}

//-----------------------------------------------------------------------------
// getOutputInfo()
//
//-----------------------------------------------------------------------------
string PerfectAI::getOutputInfo(uint32_t layerNum)
{
    stringstream ss;
    ss << " white pieces : " << layer[layerNum].whitePieceCount
       << "  \tblack pieces  : " << layer[layerNum].blackPieceCount;
    return ss.str();
}

//-----------------------------------------------------------------------------
// printBoard()
//
//-----------------------------------------------------------------------------
void PerfectAI::printBoard(uint32_t threadNo, unsigned char value)
{
    const ThreadVars *tv = &threadVars[threadNo];
    char wonStr[] = "WON";
    char lostStr[] = "LOST";
    char drawStr[] = "DRAW";
    char invStr[] = "INVALID";
    char *table[4] = {invStr, lostStr, drawStr, wonStr};

    cout << "\nstate value             : " << table[value];
    cout << "\npieces set              : " << tv->field->piecePlacedCount
         << "\n";
    tv->field->printBoard();
}

//-----------------------------------------------------------------------------
// getLayerAndStateNumber()
//
//-----------------------------------------------------------------------------
void PerfectAI::getLayerAndStateNumber(
    uint32_t &layerNum, uint32_t &stateNumber /*, uint32_t& symOp*/) const
{
    /*symOp = */ threadVars[0].getLayerAndStateNumber(layerNum, stateNumber);
}

//-----------------------------------------------------------------------------
// setOpponentLevel()
//
//-----------------------------------------------------------------------------
void PerfectAI::setOpponentLevel(uint32_t threadNo, bool isOpponentLevel)
{
    ThreadVars *tv = &threadVars[threadNo];
    tv->ownId = isOpponentLevel ? tv->field->oppPlayer->id :
                                  tv->field->curPlayer->id;
}

//-----------------------------------------------------------------------------
// getOpponentLevel()
//
//-----------------------------------------------------------------------------
bool PerfectAI::getOpponentLevel(uint32_t threadNo)
{
    const ThreadVars *tv = &threadVars[threadNo];
    return tv->ownId == tv->field->oppPlayer->id;
}

//-----------------------------------------------------------------------------
// getPartnerLayer()
//
//-----------------------------------------------------------------------------
uint32_t PerfectAI::getPartnerLayer(uint32_t layerNum)
{
    if (layerNum < 100) {
        for (int i = 0; i < 100; i++) {
            if (layer[layerNum].blackPieceCount == layer[i].whitePieceCount &&
                layer[layerNum].whitePieceCount == layer[i].blackPieceCount) {
                return i;
            }
        }
    }
    return layerNum;
}

//-----------------------------------------------------------------------------
// getSuccLayers()
//
//-----------------------------------------------------------------------------
void PerfectAI::getSuccLayers(uint32_t layerNum, uint32_t *amountOfSuccLayers,
                              uint32_t *succeedingLayers)
{
    // locals
    uint32_t i;
    const uint32_t shift = layerNum >= 100 ? 100 : 0;
    const int diff = layerNum >= 100 ? 1 : -1;

    // search layer with one white piece less
    for (*amountOfSuccLayers = 0, i = 0 + shift; i < 100 + shift; i++) {
        if (layer[i].whitePieceCount ==
                layer[layerNum].blackPieceCount + diff &&
            layer[i].blackPieceCount == layer[layerNum].whitePieceCount) {
            succeedingLayers[*amountOfSuccLayers] = i;
            *amountOfSuccLayers = *amountOfSuccLayers + 1;
            break;
        }
    }

    // search layer with one black piece less
    for (i = 0 + shift; i < 100 + shift; i++) {
        if (layer[i].whitePieceCount == layer[layerNum].blackPieceCount &&
            layer[i].blackPieceCount ==
                layer[layerNum].whitePieceCount + diff) {
            succeedingLayers[*amountOfSuccLayers] = i;
            *amountOfSuccLayers = *amountOfSuccLayers + 1;
            break;
        }
    }
}

//-----------------------------------------------------------------------------
// getSymStateNumWithDoubles()
//
//-----------------------------------------------------------------------------
void PerfectAI::getSymStateNumWithDoubles(uint32_t threadNo,
                                          uint32_t *nSymStates,
                                          uint32_t **symStateNumbers)
{
    // locals
    const ThreadVars *tv = &threadVars[threadNo];
    int origField[SQUARE_NB];
    uint32_t origPartOfMill[SQUARE_NB];
    uint32_t i;
    uint32_t layerNum, stateNum;

    *nSymStates = 0;
    *symStateNumbers = symStateNumberArray;

    // save current board
    for (i = 0; i < SQUARE_NB; i++) {
        origField[i] = tv->field->board[i];
        origPartOfMill[i] = tv->field->piecePartOfMillCount[i];
    }

    // add all sym states
    for (uint32_t symOp = 0; symOp < SO_COUNT; symOp++) {
        // apply symmetry operation
        applySymOpOnField(symOp, reinterpret_cast<uint32_t *>(origField),
                          reinterpret_cast<uint32_t *>(tv->field->board));
        applySymOpOnField(symOp, origPartOfMill,
                          tv->field->piecePartOfMillCount);

        getLayerAndStateNumber(threadNo, layerNum, stateNum);
        symStateNumberArray[*nSymStates] = stateNum;
        (*nSymStates)++;
    }

    // restore orig board
    for (i = 0; i < SQUARE_NB; i++) {
        tv->field->board[i] = origField[i];
        tv->field->piecePartOfMillCount[i] = origPartOfMill[i];
    }
}

//-----------------------------------------------------------------------------
// fieldIntegrityOK()
//
//-----------------------------------------------------------------------------
bool PerfectAI::ThreadVars::fieldIntegrityOK(
    uint32_t nMillsCurPlayer, uint32_t nMillsOpponentPlayer,
    bool aPieceCanBeRemovedFromCurPlayer) const
{
    // locals
    int i, j;
    bool noneFullFilled;

    // when piece is going to be removed than at least one opponent piece
    // mustn't be part of a mill
    if (nMillsOpponentPlayer > 0 && field->pieceMustBeRemovedCount) {
        for (i = 0; i < SQUARE_NB; i++)
            if (field->piecePartOfMillCount[i] == 0 &&
                field->oppPlayer->id == field->board[i])
                break;
        if (i == SQUARE_NB)
            return false;
    }

    // when no mill is closed than no piece can be removed
    if (field->pieceMustBeRemovedCount && nMillsCurPlayer == 0) {
        return false;

        // when in placing phase and difference in number of pieces between the
        // two players is not
    }

    if (field->isPlacingPhase) {
        // Version 8: added for-loop
        noneFullFilled = true;

        for (i = 0;
             noneFullFilled && i <= static_cast<int>(nMillsOpponentPlayer) &&
             i <= static_cast<int>(nMillsCurPlayer);
             i++) {
            for (j = 0;
                 noneFullFilled &&
                 j <= static_cast<int>(nMillsOpponentPlayer) &&
                 j <= static_cast<int>(nMillsCurPlayer) -
                          static_cast<int>(field->pieceMustBeRemovedCount);
                 j++) {
                if (field->curPlayer->pieceCount + nMillsOpponentPlayer + 0 -
                        field->pieceMustBeRemovedCount - j ==
                    field->oppPlayer->pieceCount + nMillsCurPlayer -
                        field->pieceMustBeRemovedCount - i)
                    noneFullFilled = false;
                if (field->curPlayer->pieceCount + nMillsOpponentPlayer + 1 -
                        field->pieceMustBeRemovedCount - j ==
                    field->oppPlayer->pieceCount + nMillsCurPlayer -
                        field->pieceMustBeRemovedCount - i)
                    noneFullFilled = false;
            }
        }

        if (noneFullFilled || field->piecePlacedCount >= 18) {
            return false;
        }

        // moving phase
    } else if (!field->isPlacingPhase && (field->curPlayer->pieceCount < 2 ||
                                          field->oppPlayer->pieceCount < 2)) {
        return false;
    }

    return true;
}

//-----------------------------------------------------------------------------
// isSymOpInvariantOnGroupCD()
//
//-----------------------------------------------------------------------------
bool PerfectAI::isSymOpInvariantOnGroupCD(uint32_t symOp,
                                          const int *theField) const
{
    uint32_t i = squareIdxGroupC[0];
    if (theField[i] != theField[symOpTable[symOp][i]])
        return false;
    i = squareIdxGroupC[1];
    if (theField[i] != theField[symOpTable[symOp][i]])
        return false;
    i = squareIdxGroupC[2];
    if (theField[i] != theField[symOpTable[symOp][i]])
        return false;
    i = squareIdxGroupC[3];
    if (theField[i] != theField[symOpTable[symOp][i]])
        return false;
    i = squareIdxGroupC[4];
    if (theField[i] != theField[symOpTable[symOp][i]])
        return false;
    i = squareIdxGroupC[5];
    if (theField[i] != theField[symOpTable[symOp][i]])
        return false;
    i = squareIdxGroupC[6];
    if (theField[i] != theField[symOpTable[symOp][i]])
        return false;
    i = squareIdxGroupC[7];
    if (theField[i] != theField[symOpTable[symOp][i]])
        return false;
    i = squareIdxGroupD[0];
    if (theField[i] != theField[symOpTable[symOp][i]])
        return false;
    i = squareIdxGroupD[1];
    if (theField[i] != theField[symOpTable[symOp][i]])
        return false;
    i = squareIdxGroupD[2];
    if (theField[i] != theField[symOpTable[symOp][i]])
        return false;
    i = squareIdxGroupD[3];
    if (theField[i] != theField[symOpTable[symOp][i]])
        return false;
    i = squareIdxGroupD[4];
    if (theField[i] != theField[symOpTable[symOp][i]])
        return false;
    i = squareIdxGroupD[5];
    if (theField[i] != theField[symOpTable[symOp][i]])
        return false;
    i = squareIdxGroupD[6];
    if (theField[i] != theField[symOpTable[symOp][i]])
        return false;
    i = squareIdxGroupD[7];
    if (theField[i] != theField[symOpTable[symOp][i]])
        return false;

    return true;
}

//-----------------------------------------------------------------------------
// storePredecessor()
//
//-----------------------------------------------------------------------------
void PerfectAI::ThreadVars::storePredecessor(
    uint32_t nMillsCurPlayer, uint32_t nMillsOpponentPlayer,
    uint32_t *amountOfPred, RetroAnalysisPredVars *predVars) const
{
    // locals
    int origField[SQUARE_NB];
    uint32_t i, symOp, symOpApplied;
    uint32_t predLayerNum, predStateNum;
    const uint32_t origAmountOfPred = *amountOfPred;

    // store only if state is valid
    if (fieldIntegrityOK(nMillsCurPlayer, nMillsOpponentPlayer, false)) {
        // save current board
        for (i = 0; i < SQUARE_NB; i++)
            origField[i] = field->board[i];

        // add all sym states
        for (symOp = 0; symOp < SO_COUNT; symOp++) {
            // ...
            if (symOp == SO_DO_NOTHING ||
                parent->isSymOpInvariantOnGroupCD(symOp, origField)) {
                // apply symmetry operation
                parent->applySymOpOnField(
                    symOp, reinterpret_cast<uint32_t *>(origField),
                    reinterpret_cast<uint32_t *>(field->board));

                symOpApplied = getLayerAndStateNumber(predLayerNum,
                                                      predStateNum);
                predVars[*amountOfPred].predSymOp =
                    parent->concSymOp[symOp][symOpApplied];
                predVars[*amountOfPred].predLayerNumbers = predLayerNum;
                predVars[*amountOfPred].predStateNumbers = predStateNum;
                predVars[*amountOfPred].playerToMoveChanged =
                    predVars[origAmountOfPred].playerToMoveChanged;

                // add only if not already in list
                for (i = 0; i < *amountOfPred; i++)
                    if (predVars[i].predLayerNumbers == predLayerNum &&
                        predVars[i].predStateNumbers == predStateNum)
                        break;
                if (i == *amountOfPred)
                    (*amountOfPred)++;
            }
        }

        // restore orig board
        for (i = 0; i < SQUARE_NB; i++)
            field->board[i] = origField[i];
    }
}

//-----------------------------------------------------------------------------
// getPredecessors()
// CAUTION: States mustn't be returned twice.
//-----------------------------------------------------------------------------
void PerfectAI::getPredecessors(uint32_t threadNo, uint32_t *amountOfPred,
                                RetroAnalysisPredVars *predVars)
{
    ////////////////////////////////////////////////////////////////////////////
    // the important variables, which much be updated for the
    // getLayerAndStateNumber function are the following ones:
    // - board->curPlayer->pieceCount
    // - board->oppPlayer->pieceCount
    // - board->curPlayer->id
    // - board->board
    // - board->pieceMustBeRemovedCount
    // - board->isPlacingPhase
    ////////////////////////////////////////////////////////////////////////////

    // locals
    const ThreadVars *tv = &threadVars[threadNo];
    bool aPieceCanBeRemovedFromCurPlayer;
    bool millWasClosed;
    uint32_t from, to, dir, i;
    Player *tmpPlayer;
    uint32_t nMillsCurPlayer = 0;
    uint32_t nMillsOpponentPlayer = 0;

    // zero
    *amountOfPred = 0;

    // count completed mills
    for (i = 0; i < SQUARE_NB; i++) {
        if (tv->field->board[i] == tv->field->curPlayer->id)
            nMillsCurPlayer += tv->field->piecePartOfMillCount[i];
        else
            nMillsOpponentPlayer += tv->field->piecePartOfMillCount[i];
    }

    nMillsCurPlayer /= 3;
    nMillsOpponentPlayer /= 3;

    // precalc aPieceCanBeRemovedFromCurPlayer
    for (aPieceCanBeRemovedFromCurPlayer = false, i = 0; i < SQUARE_NB; i++) {
        if (tv->field->piecePartOfMillCount[i] == 0 &&
            tv->field->board[i] == tv->field->curPlayer->id) {
            aPieceCanBeRemovedFromCurPlayer = true;
            break;
        }
    }

    // was a mill closed?
    if (tv->field->pieceMustBeRemovedCount)
        millWasClosed = true;
    else
        millWasClosed = false;

    // in moving phase
    if (!tv->field->isPlacingPhase && tv->field->curPlayer->pieceCount >= 3 &&
        tv->field->oppPlayer->pieceCount >= 3) {
        // normal move
        if ((tv->field->pieceMustBeRemovedCount &&
             tv->field->curPlayer->pieceCount > 3) ||
            (!tv->field->pieceMustBeRemovedCount &&
             tv->field->oppPlayer->pieceCount > 3)) {
            // when game has finished then because current player can't move
            // anymore or has less then 3 pieces
            if (!tv->gameHasFinished ||
                tv->field->curPlayer->possibleMovesCount == 0) {
                // test each dest
                for (to = 0; to < SQUARE_NB; to++) {
                    // was opponent player piece owner?
                    if (tv->field->board[to] !=
                        (tv->field->pieceMustBeRemovedCount ?
                             tv->field->curPlayer->id :
                             tv->field->oppPlayer->id))
                        continue;

                    // when piece is going to be removed than a mill must be
                    // closed
                    if (tv->field->pieceMustBeRemovedCount &&
                        tv->field->piecePartOfMillCount[to] == 0)
                        continue;

                    // when piece is part of a mill then a piece must be removed
                    if (aPieceCanBeRemovedFromCurPlayer &&
                        tv->field->pieceMustBeRemovedCount == 0 &&
                        tv->field->piecePartOfMillCount[to])
                        continue;

                    // test each direction
                    for (dir = 0; dir < MD_NB; dir++) {
                        // origin
                        from = tv->field->connectedSquare[to][dir];

                        // move possible ?
                        if (from < SQUARE_NB &&
                            tv->field->board[from] == tv->field->squareIsFree) {
                            if (millWasClosed) {
                                nMillsCurPlayer -=
                                    tv->field->piecePartOfMillCount[to];
                                tv->field->pieceMustBeRemovedCount = 0;
                                predVars[*amountOfPred].playerToMoveChanged =
                                    false;
                            } else {
                                predVars[*amountOfPred].playerToMoveChanged =
                                    true;
                                tmpPlayer = tv->field->curPlayer;
                                tv->field->curPlayer = tv->field->oppPlayer;
                                tv->field->oppPlayer = tmpPlayer;
                                i = nMillsCurPlayer;
                                nMillsCurPlayer = nMillsOpponentPlayer;
                                nMillsOpponentPlayer = i;
                                nMillsCurPlayer -=
                                    tv->field->piecePartOfMillCount[to];
                            }

                            // make move
                            tv->field->board[from] = tv->field->board[to];
                            tv->field->board[to] = tv->field->squareIsFree;

                            // store predecessor
                            tv->storePredecessor(nMillsCurPlayer,
                                                 nMillsOpponentPlayer,
                                                 amountOfPred, predVars);

                            // undo move
                            tv->field->board[to] = tv->field->board[from];
                            tv->field->board[from] = tv->field->squareIsFree;

                            if (millWasClosed) {
                                nMillsCurPlayer +=
                                    tv->field->piecePartOfMillCount[to];
                                tv->field->pieceMustBeRemovedCount = 1;
                            } else {
                                tmpPlayer = tv->field->curPlayer;
                                tv->field->curPlayer = tv->field->oppPlayer;
                                tv->field->oppPlayer = tmpPlayer;
                                nMillsCurPlayer +=
                                    tv->field->piecePartOfMillCount[to];
                                i = nMillsCurPlayer;
                                nMillsCurPlayer = nMillsOpponentPlayer;
                                nMillsOpponentPlayer = i;
                            }

                            // current or opponent player were allowed to spring
                        }
                    }
                }
            }

        } else if (!tv->gameHasFinished) {
            // test each dest
            for (to = 0; to < SQUARE_NB; to++) {
                // when piece must be removed than current player closed a mill,
                // otherwise the opponent did a common spring move
                if (tv->field->board[to] !=
                    (tv->field->pieceMustBeRemovedCount ?
                         tv->field->curPlayer->id :
                         tv->field->oppPlayer->id))
                    continue;

                // when piece is going to be removed than a mill must be closed
                if (tv->field->pieceMustBeRemovedCount &&
                    tv->field->piecePartOfMillCount[to] == 0)
                    continue;

                // when piece is part of a mill then a piece must be removed
                if (aPieceCanBeRemovedFromCurPlayer &&
                    tv->field->pieceMustBeRemovedCount == 0 &&
                    tv->field->piecePartOfMillCount[to])
                    continue;

                // test each direction
                for (from = 0; from < SQUARE_NB; from++) {
                    // move possible ?
                    if (tv->field->board[from] == tv->field->squareIsFree) {
                        // was a mill closed?
                        if (millWasClosed) {
                            nMillsCurPlayer -= tv->field
                                                   ->piecePartOfMillCount[to];
                            tv->field->pieceMustBeRemovedCount = 0;
                            predVars[*amountOfPred].playerToMoveChanged = false;
                        } else {
                            predVars[*amountOfPred].playerToMoveChanged = true;
                            tmpPlayer = tv->field->curPlayer;
                            tv->field->curPlayer = tv->field->oppPlayer;
                            tv->field->oppPlayer = tmpPlayer;
                            i = nMillsCurPlayer;
                            nMillsCurPlayer = nMillsOpponentPlayer;
                            nMillsOpponentPlayer = i;
                            nMillsCurPlayer -= tv->field
                                                   ->piecePartOfMillCount[to];
                        }

                        // make move
                        tv->field->board[from] = tv->field->board[to];
                        tv->field->board[to] = tv->field->squareIsFree;

                        // store predecessor
                        tv->storePredecessor(nMillsCurPlayer,
                                             nMillsOpponentPlayer, amountOfPred,
                                             predVars);

                        // undo move
                        tv->field->board[to] = tv->field->board[from];
                        tv->field->board[from] = tv->field->squareIsFree;

                        if (millWasClosed) {
                            nMillsCurPlayer += tv->field
                                                   ->piecePartOfMillCount[to];
                            tv->field->pieceMustBeRemovedCount = 1;
                        } else {
                            tmpPlayer = tv->field->curPlayer;
                            tv->field->curPlayer = tv->field->oppPlayer;
                            tv->field->oppPlayer = tmpPlayer;
                            nMillsCurPlayer += tv->field
                                                   ->piecePartOfMillCount[to];
                            i = nMillsCurPlayer;
                            nMillsCurPlayer = nMillsOpponentPlayer;
                            nMillsOpponentPlayer = i;
                        }
                    }
                }
            }
        }
    }

    // was a piece removed ?
    if (tv->field->curPlayer->pieceCount < 9 &&
        tv->field->curPlayer->removedPiecesCount > 0 &&
        tv->field->pieceMustBeRemovedCount == 0) {
        // has opponent player a closed mill ?
        if (nMillsOpponentPlayer) {
            // from each free position the opponent could have removed a piece
            // from the current player
            for (from = 0; from < SQUARE_NB; from++) {
                // square free?
                if (tv->field->board[from] == tv->field->squareIsFree) {
                    // piece mustn't be part of mill
                    if ((!(tv->field->board[tv->field->neighbor[from][0][0]] ==
                               tv->field->curPlayer->id &&
                           tv->field->board[tv->field->neighbor[from][0][1]] ==
                               tv->field->curPlayer->id)) &&
                        (!(tv->field->board[tv->field->neighbor[from][1][0]] ==
                               tv->field->curPlayer->id &&
                           tv->field->board[tv->field->neighbor[from][1][1]] ==
                               tv->field->curPlayer->id))) {
                        // put back piece
                        tv->field->pieceMustBeRemovedCount = 1;
                        tv->field->board[from] = tv->field->curPlayer->id;
                        tv->field->curPlayer->pieceCount++;
                        tv->field->curPlayer->removedPiecesCount--;

                        // it was an opponent move
                        predVars[*amountOfPred].playerToMoveChanged = true;
                        tmpPlayer = tv->field->curPlayer;
                        tv->field->curPlayer = tv->field->oppPlayer;
                        tv->field->oppPlayer = tmpPlayer;

                        // store predecessor
                        tv->storePredecessor(nMillsOpponentPlayer,
                                             nMillsCurPlayer, amountOfPred,
                                             predVars);

                        tmpPlayer = tv->field->curPlayer;
                        tv->field->curPlayer = tv->field->oppPlayer;
                        tv->field->oppPlayer = tmpPlayer;

                        // remove piece again
                        tv->field->pieceMustBeRemovedCount = 0;
                        tv->field->board[from] = tv->field->squareIsFree;
                        tv->field->curPlayer->pieceCount--;
                        tv->field->curPlayer->removedPiecesCount++;
                    }
                }
            }
        }
    }
}

/*** To Do's ***************************************
- Possibly save all cyclicArrays in a file. Better to even compress it (at
Windows or program level?), Which should work fine because you work in blocks
anyway. Since the size was previously unknown, a table must be produced.
Possible class name "compressedCyclicArray (blockSize, blockCount, numArrays,
filePath)".
- Implement initFileReader
***************************************************/

#endif // MADWEASEL_MUEHLE_PERFECT_AI
