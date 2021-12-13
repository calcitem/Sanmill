/*********************************************************************
    PerfectAI.cpp
    Copyright (c) Thomas Weber. All rights reserved.
    Copyright (C) 2021 The Sanmill developers (see AUTHORS file)
    Licensed under the GPLv3 License.
    https://github.com/madweasel/Muehle
\*********************************************************************/

#include "config.h"

#ifdef MADWEASEL_MUEHLE_PERFECT_AI

#include "perfectAI.h"
#include <cassert>

// clang-format off
unsigned int soTableTurnLeft[] = {
 2,      14,      23,
    5,   13,   20,
       8,12,17,
 1, 4, 7,   16,19,22,
       6,11,15,
    3,   10,   18,
 0,       9,      21
};

unsigned int soTableDoNothing[] = {
 0,       1,       2,
    3,    4,    5,
       6, 7, 8,
 9,10,11,   12,13,14,
      15,16,17,
   18,   19,   20,
21,      22,      23
};

unsigned int soTableMirrorHori[] = {
21,      22,      23,
   18,   19,   20,
      15,16,17,
 9,10,11,   12,13,14,
       6, 7, 8,
    3,    4,    5,
 0,       1,       2
};

unsigned int soTableTurn180[] = {
 23,      22,      21,
    20,   19,   18,
       17,16,15,
 14,13,12,   11,10, 9,
        8, 7, 6,
     5,    4,    3,
  2,       1,       0
};

unsigned int soTableInvert[] = {
  6,       7,       8,
     3,    4,    5,
        0, 1, 2,
 11,10, 9,   14,13,12,
       21,22,23,
    18,   19,   20,
 15,      16,      17
};

unsigned int soTableInvMirHori[] = {
 15,      16,      17,
    18,   19,   20,
       21,22,23,
 11,10, 9,   14,13,12,
        0, 1, 2,
     3,    4,    5,
  6,       7,       8
};

unsigned int soTableInvMirVert[] = {
  8,       7,       6,
     5,    4,    3,
        2, 1, 0,
 12,13,14,    9,10,11,
       23,22,21,
    20,   19,   18,
 17,      16,      15
};

unsigned int soTableInvMirDiag1[] = {
 17,      12,       8,
    20,   13,    5,
       23,14, 2,
 16,19,22,    1, 4, 7,
       21, 9, 0,
    18,   10,    3,
 15,      11,       6
};

unsigned int soTableInvMirDiag2[] = {
  6,      11,      15,
     3,   10,   18,
        0, 9,21,
  7, 4, 1,   22,19,16,
        2,14,23,
     5,   13,   20,
  8,      12,      17
};

unsigned int soTableInvLeft[] = {
  8,      12,      17,
     5,   13,   20,
        2,14,23,
  7, 4, 1,   22,19,16,
        0, 9,21,
     3,   10,   18,
  6,      11,      15
};

unsigned int soTableInvRight[] = {
 15,      11,       6,
    18,   10,    3,
       21, 9, 0,
 16,19,22,    1, 4, 7,
       23,14, 2,
    20,   13,    5,
 17,      12,       8
};

unsigned int soTableInv180[] = {
 17,      16,      15,
    20,   19,   18,
       23,22,21,
 12,13,14,    9,10,11,
        2, 1, 0,
     5,    4,    3,
  8,       7,       6
};

unsigned int soTableMirrorDiag1[] = {
  0,       9,      21,
     3,   10,   18,
        6,11,15,
  1, 4, 7,   16,19,22,
        8,12,17,
     5,   13,   20,
  2,      14,      23
};

unsigned int soTableTurnRight[] = {
  21,       9,       0,
     18,   10,    3,
        15,11, 6,
  22,19,16,    7, 4, 1,
        17,12, 8,
     20,   13,    5,
  23,      14,       2
};

unsigned int soTableMirrorVert[] = {
   2,       1,       0,
      5,    4,    3,
         8, 7, 6,
  14,13,12,   11,10, 9,
        17,16,15,
     20,   19,   18,
  23,      22,      21
};

unsigned int soTableMirrorDiag2[] = {
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
unsigned int squareIndexGroupA[] = {3, 5, 20, 18};
unsigned int squareIndexGroupB[8] = {4, 13, 19, 10};
unsigned int squareIndexGroupC[] = {0, 2, 23, 21, 6, 8, 17, 15};
unsigned int squareIndexGroupD[] = {1, 7, 14, 12, 22, 16, 9, 11};

unsigned int fieldPosIsOfGroup[] = {GROUP_C, GROUP_D, GROUP_C, GROUP_A, GROUP_B,
                                    GROUP_A, GROUP_C, GROUP_D, GROUP_C, GROUP_D,
                                    GROUP_B, GROUP_D, GROUP_D, GROUP_B, GROUP_D,
                                    GROUP_C, GROUP_D, GROUP_C, GROUP_A, GROUP_B,
                                    GROUP_A, GROUP_C, GROUP_D, GROUP_C};

//-----------------------------------------------------------------------------
// PerfectAI()
// PerfectAI class constructor
//-----------------------------------------------------------------------------
PerfectAI::PerfectAI(const char *dir)
{
    // locals
    unsigned int i, a, b, c, totalNumPieces;
    unsigned int wCD, bCD, wAB, bAB;
    unsigned int stateAB, stateCD, symStateCD, layerNum;
    unsigned int myField[SQUARE_NB];
    unsigned int symField[SQUARE_NB];
    unsigned int *originalStateCD_tmp[10][10];
    DWORD dwBytesRead = 0;
    DWORD dwBytesWritten = 0;
    HANDLE hFilePreCalcVars;
    stringstream ssPreCalcVarsFilePath;
    PreCalcedVarsFileHeader preCalcVarsHeader;

    //
    threadVars = new ThreadVars[getThreadCount()];

    for (unsigned int curThread = 0; curThread < getThreadCount();
         curThread++) {
        threadVars[curThread].parent = this;
        threadVars[curThread].field = &dummyField;
        threadVars[curThread].possibilities =
            new Possibility[MAX_DEPTH_OF_TREE + 1];
        threadVars[curThread].oldStates = new Backup[MAX_DEPTH_OF_TREE + 1];
        threadVars[curThread].idPossibilities =
            new unsigned int[(MAX_DEPTH_OF_TREE + 1) * POSIBILE_MOVE_COUNT_MAX];
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
        if (!ReadFile(hFilePreCalcVars, layer, sizeof(Layer) * NUM_LAYERS,
                      &dwBytesRead, nullptr))
            return;
        if (!ReadFile(hFilePreCalcVars, layerIndex,
                      sizeof(unsigned int) * 2 *
                          NUM_PIECES_PER_PLAYER_PLUS_ONE *
                          NUM_PIECES_PER_PLAYER_PLUS_ONE,
                      &dwBytesRead, nullptr))
            return;
        if (!ReadFile(hFilePreCalcVars, nPositionsAB,
                      sizeof(unsigned int) * NUM_PIECES_PER_PLAYER_PLUS_ONE *
                          NUM_PIECES_PER_PLAYER_PLUS_ONE,
                      &dwBytesRead, nullptr))
            return;
        if (!ReadFile(hFilePreCalcVars, nPositionsCD,
                      sizeof(unsigned int) * NUM_PIECES_PER_PLAYER_PLUS_ONE *
                          NUM_PIECES_PER_PLAYER_PLUS_ONE,
                      &dwBytesRead, nullptr))
            return;
        if (!ReadFile(hFilePreCalcVars, indexAB,
                      sizeof(unsigned int) * MAX_ANZ_POSITION_A *
                          MAX_ANZ_POSITION_B,
                      &dwBytesRead, nullptr))
            return;
        if (!ReadFile(hFilePreCalcVars, indexCD,
                      sizeof(unsigned int) * MAX_ANZ_POSITION_C *
                          MAX_ANZ_POSITION_D,
                      &dwBytesRead, nullptr))
            return;
        if (!ReadFile(hFilePreCalcVars, symmetryOperationCD,
                      sizeof(unsigned char) * MAX_ANZ_POSITION_C *
                          MAX_ANZ_POSITION_D,
                      &dwBytesRead, nullptr))
            return;
        if (!ReadFile(hFilePreCalcVars, powerOfThree,
                      sizeof(unsigned int) * (nSquaresGroupC + nSquaresGroupD),
                      &dwBytesRead, nullptr))
            return;
        if (!ReadFile(hFilePreCalcVars, symmetryOperationTable,
                      sizeof(unsigned int) * SQUARE_NB * SO_COUNT,
                      &dwBytesRead, nullptr))
            return;
        if (!ReadFile(hFilePreCalcVars, reverseSymOperation,
                      sizeof(unsigned int) * SO_COUNT, &dwBytesRead,
                      nullptr))
            return;
        if (!ReadFile(hFilePreCalcVars, concSymOperation,
                      sizeof(unsigned int) * SO_COUNT *
                          SO_COUNT,
                      &dwBytesRead, nullptr))
            return;
        if (!ReadFile(hFilePreCalcVars, mOverN,
                      sizeof(unsigned int) * (SQUARE_NB + 1) * (SQUARE_NB + 1),
                      &dwBytesRead, nullptr))
            return;
        if (!ReadFile(hFilePreCalcVars, valueOfMove,
                      sizeof(unsigned char) * SQUARE_NB * SQUARE_NB,
                      &dwBytesRead, nullptr))
            return;
        if (!ReadFile(hFilePreCalcVars, plyInfoForOutput,
                      sizeof(PlyInfoVarType) * SQUARE_NB * SQUARE_NB,
                      &dwBytesRead, nullptr))
            return;
        if (!ReadFile(hFilePreCalcVars, incidencesValuesSubMoves,
                      sizeof(unsigned int) * 4 * SQUARE_NB * SQUARE_NB,
                      &dwBytesRead, nullptr))
            return;

        // process originalStateAB[][]
        for (a = 0; a <= NUM_PIECES_PER_PLAYER; a++) {
            for (b = 0; b <= NUM_PIECES_PER_PLAYER; b++) {
                if (a + b > nSquaresGroupA + nSquaresGroupB)
                    continue;
                originalStateAB[a][b] = new unsigned int[nPositionsAB[a][b]];
                if (!ReadFile(hFilePreCalcVars, originalStateAB[a][b],
                              sizeof(unsigned int) * nPositionsAB[a][b],
                              &dwBytesRead, nullptr))
                    return;
            }
        }

        // process originalStateCD[][]
        for (a = 0; a <= NUM_PIECES_PER_PLAYER; a++) {
            for (b = 0; b <= NUM_PIECES_PER_PLAYER; b++) {
                if (a + b > nSquaresGroupC + nSquaresGroupD)
                    continue;
                originalStateCD[a][b] = new unsigned int[nPositionsCD[a][b]];
                if (!ReadFile(hFilePreCalcVars, originalStateCD[a][b],
                              sizeof(unsigned int) * nPositionsCD[a][b],
                              &dwBytesRead, nullptr))
                    return;
            }
        }

        // calculate vars and save into file
    } else {
        // calc mOverN
        for (a = 0; a <= SQUARE_NB; a++) {
            for (b = 0; b <= SQUARE_NB; b++) {
                mOverN[a][b] = (unsigned int)mOverN_Function(a, b);
            }
        }

        // reset
        for (i = 0; i < SQUARE_NB * SQUARE_NB; i++) {
            plyInfoForOutput[i] = PLYINFO_VALUE_INVALID;
            valueOfMove[i] = SKV_VALUE_INVALID;
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
            symmetryOperationTable[SO_TURN_LEFT][i] = soTableTurnLeft[i];
            symmetryOperationTable[SO_TURN_180][i] = soTableTurn180[i];
            symmetryOperationTable[SO_TURN_RIGHT][i] = soTableTurnRight[i];
            symmetryOperationTable[SO_DO_NOTHING][i] = soTableDoNothing[i];
            symmetryOperationTable[SO_INVERT][i] = soTableInvert[i];
            symmetryOperationTable[SO_MIRROR_VERT][i] = soTableMirrorVert[i];
            symmetryOperationTable[SO_MIRROR_HORI][i] = soTableMirrorHori[i];
            symmetryOperationTable[SO_MIRROR_DIAG_1][i] = soTableMirrorDiag1[i];
            symmetryOperationTable[SO_MIRROR_DIAG_2][i] = soTableMirrorDiag2[i];
            symmetryOperationTable[SO_INV_LEFT][i] = soTableInvLeft[i];
            symmetryOperationTable[SO_INV_RIGHT][i] = soTableInvRight[i];
            symmetryOperationTable[SO_INV_180][i] = soTableInv180[i];
            symmetryOperationTable[SO_INV_MIR_VERT][i] = soTableInvMirHori[i];
            symmetryOperationTable[SO_INV_MIR_HORI][i] = soTableInvMirVert[i];
            symmetryOperationTable[SO_INV_MIR_DIAG_1][i] = soTableInvMirDiag1[i];
            symmetryOperationTable[SO_INV_MIR_DIAG_2][i] = soTableInvMirDiag2[i];
        }

        // reverse symmetry operation
        reverseSymOperation[SO_TURN_LEFT] = SO_TURN_RIGHT;
        reverseSymOperation[SO_TURN_180] = SO_TURN_180;
        reverseSymOperation[SO_TURN_RIGHT] = SO_TURN_LEFT;
        reverseSymOperation[SO_DO_NOTHING] = SO_DO_NOTHING;
        reverseSymOperation[SO_INVERT] = SO_INVERT;
        reverseSymOperation[SO_MIRROR_VERT] = SO_MIRROR_VERT;
        reverseSymOperation[SO_MIRROR_HORI] = SO_MIRROR_HORI;
        reverseSymOperation[SO_MIRROR_DIAG_1] = SO_MIRROR_DIAG_1;
        reverseSymOperation[SO_MIRROR_DIAG_2] = SO_MIRROR_DIAG_2;
        reverseSymOperation[SO_INV_LEFT] = SO_INV_RIGHT;
        reverseSymOperation[SO_INV_RIGHT] = SO_INV_LEFT;
        reverseSymOperation[SO_INV_180] = SO_INV_180;
        reverseSymOperation[SO_INV_MIR_VERT] = SO_INV_MIR_VERT;
        reverseSymOperation[SO_INV_MIR_HORI] = SO_INV_MIR_HORI;
        reverseSymOperation[SO_INV_MIR_DIAG_1] = SO_INV_MIR_DIAG_1;
        reverseSymOperation[SO_INV_MIR_DIAG_2] = SO_INV_MIR_DIAG_2;

        // concatenated symmetry operations
        for (a = 0; a < SO_COUNT; a++) {
            for (b = 0; b < SO_COUNT; b++) {
                // test each symmetry operation
                for (c = 0; c < SO_COUNT; c++) {
                    // look if b(a(state)) == c(state)
                    for (i = 0; i < SQUARE_NB; i++) {
                        if (symmetryOperationTable[c][i] !=
                            symmetryOperationTable[a]
                                                  [symmetryOperationTable[b][i]])
                            break;
                    }

                    // match found?
                    if (i == SQUARE_NB) {
                        concSymOperation[a][b] = c;
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
        for (a = 0; a <= NUM_PIECES_PER_PLAYER; a++) {
            for (b = 0; b <= NUM_PIECES_PER_PLAYER; b++) {
                if (a + b > nSquaresGroupA + nSquaresGroupB)
                    continue;

                nPositionsAB[a][b] =
                    mOverN[nSquaresGroupA + nSquaresGroupB][a] *
                    mOverN[nSquaresGroupA + nSquaresGroupB - a][b];
                originalStateAB[a][b] = new unsigned int[nPositionsAB[a][b]];
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
                myField[squareIndexGroupA[0]] = (stateAB / powerOfThree[7]) % 3;
                myField[squareIndexGroupA[1]] = (stateAB / powerOfThree[6]) % 3;
                myField[squareIndexGroupA[2]] = (stateAB / powerOfThree[5]) % 3;
                myField[squareIndexGroupA[3]] = (stateAB / powerOfThree[4]) % 3;
                myField[squareIndexGroupB[4]] = (stateAB / powerOfThree[3]) % 3;
                myField[squareIndexGroupB[5]] = (stateAB / powerOfThree[2]) % 3;
                myField[squareIndexGroupB[6]] = (stateAB / powerOfThree[1]) % 3;
                myField[squareIndexGroupB[7]] = (stateAB / powerOfThree[0]) % 3;

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
                originalStateAB[a][b][nPositionsAB[a][b]] = stateAB;

                // state counter
                nPositionsAB[a][b]++;
            }
        }

        // group C&D //

        // reserve memory
        for (a = 0; a <= NUM_PIECES_PER_PLAYER; a++) {
            for (b = 0; b <= NUM_PIECES_PER_PLAYER; b++) {
                if (a + b > nSquaresGroupC + nSquaresGroupD)
                    continue;
                originalStateCD_tmp[a][b] = new unsigned int
                    [mOverN[nSquaresGroupC + nSquaresGroupD][a] *
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
                myField[squareIndexGroupC[0]] = (stateCD / powerOfThree[15]) %
                                                3;
                myField[squareIndexGroupC[1]] = (stateCD / powerOfThree[14]) %
                                                3;
                myField[squareIndexGroupC[2]] = (stateCD / powerOfThree[13]) %
                                                3;
                myField[squareIndexGroupC[3]] = (stateCD / powerOfThree[12]) %
                                                3;
                myField[squareIndexGroupC[4]] = (stateCD / powerOfThree[11]) %
                                                3;
                myField[squareIndexGroupC[5]] = (stateCD / powerOfThree[10]) %
                                                3;
                myField[squareIndexGroupC[6]] = (stateCD / powerOfThree[9]) % 3;
                myField[squareIndexGroupC[7]] = (stateCD / powerOfThree[8]) % 3;
                myField[squareIndexGroupD[0]] = (stateCD / powerOfThree[7]) % 3;
                myField[squareIndexGroupD[1]] = (stateCD / powerOfThree[6]) % 3;
                myField[squareIndexGroupD[2]] = (stateCD / powerOfThree[5]) % 3;
                myField[squareIndexGroupD[3]] = (stateCD / powerOfThree[4]) % 3;
                myField[squareIndexGroupD[4]] = (stateCD / powerOfThree[3]) % 3;
                myField[squareIndexGroupD[5]] = (stateCD / powerOfThree[2]) % 3;
                myField[squareIndexGroupD[6]] = (stateCD / powerOfThree[1]) % 3;
                myField[squareIndexGroupD[7]] = (stateCD / powerOfThree[0]) % 3;

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
                if (a > NUM_PIECES_PER_PLAYER)
                    continue;
                if (b > NUM_PIECES_PER_PLAYER)
                    continue;

                // mark original state
                indexCD[stateCD] = nPositionsCD[a][b];
                symmetryOperationCD[stateCD] = SO_DO_NOTHING;
                originalStateCD_tmp[a][b][nPositionsCD[a][b]] = stateCD;

                // mark all symmetric states
                for (i = 0; i < SO_COUNT; i++) {
                    applySymmetryOperationOnField(i, myField, symField);

                    symStateCD =
                        symField[squareIndexGroupC[0]] * powerOfThree[15] +
                        symField[squareIndexGroupC[1]] * powerOfThree[14] +
                        symField[squareIndexGroupC[2]] * powerOfThree[13] +
                        symField[squareIndexGroupC[3]] * powerOfThree[12] +
                        symField[squareIndexGroupC[4]] * powerOfThree[11] +
                        symField[squareIndexGroupC[5]] * powerOfThree[10] +
                        symField[squareIndexGroupC[6]] * powerOfThree[9] +
                        symField[squareIndexGroupC[7]] * powerOfThree[8] +
                        symField[squareIndexGroupD[0]] * powerOfThree[7] +
                        symField[squareIndexGroupD[1]] * powerOfThree[6] +
                        symField[squareIndexGroupD[2]] * powerOfThree[5] +
                        symField[squareIndexGroupD[3]] * powerOfThree[4] +
                        symField[squareIndexGroupD[4]] * powerOfThree[3] +
                        symField[squareIndexGroupD[5]] * powerOfThree[2] +
                        symField[squareIndexGroupD[6]] * powerOfThree[1] +
                        symField[squareIndexGroupD[7]] * powerOfThree[0];

                    if (stateCD != symStateCD) {
                        indexCD[symStateCD] = nPositionsCD[a][b];
                        symmetryOperationCD[symStateCD] = reverseSymOperation[i];
                    }
                }

                // state counter
                nPositionsCD[a][b]++;
            }
        }

        // copy from originalStateCD_tmp to originalStateCD
        for (a = 0; a <= NUM_PIECES_PER_PLAYER; a++) {
            for (b = 0; b <= NUM_PIECES_PER_PLAYER; b++) {
                if (a + b > nSquaresGroupC + nSquaresGroupD)
                    continue;
                originalStateCD[a][b] = new unsigned int[nPositionsCD[a][b]];
                for (i = 0; i < nPositionsCD[a][b]; i++)
                    originalStateCD[a][b][i] = originalStateCD_tmp[a][b][i];
                SAFE_DELETE_ARRAY(originalStateCD_tmp[a][b]);
            }
        }

        // moving phase
        for (totalNumPieces = 0, layerNum = 0; totalNumPieces <= 18;
             totalNumPieces++) {
            for (a = 0; a <= totalNumPieces; a++) {
                for (b = 0; b <= totalNumPieces - a; b++) {
                    if (a > NUM_PIECES_PER_PLAYER)
                        continue;
                    if (b > NUM_PIECES_PER_PLAYER)
                        continue;
                    if (a + b != totalNumPieces)
                        continue;

                    layerIndex[LAYER_INDEX_MOVING_PHASE][a][b] = layerNum;
                    layer[layerNum].whitePieceCount = a;
                    layer[layerNum].blackPieceCount = b;
                    layer[layerNum].subLayerCount = 0;

                    for (wCD = 0; wCD <= layer[layerNum].whitePieceCount;
                         wCD++) {
                        for (bCD = 0; bCD <= layer[layerNum].blackPieceCount;
                             bCD++) {
                            // calc number of white and black pieces for group
                            // A&B
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
        for (totalNumPieces = 0, layerNum = NUM_LAYERS - 1;
             totalNumPieces <= 2 * NUM_PIECES_PER_PLAYER; totalNumPieces++) {
            for (a = 0; a <= totalNumPieces; a++) {
                for (b = 0; b <= totalNumPieces - a; b++) {
                    if (a > NUM_PIECES_PER_PLAYER)
                        continue;
                    if (b > NUM_PIECES_PER_PLAYER)
                        continue;
                    if (a + b != totalNumPieces)
                        continue;
                    layer[layerNum].whitePieceCount = a;
                    layer[layerNum].blackPieceCount = b;
                    layerIndex[LAYER_INDEX_PLACING_PHASE][a][b] = layerNum;
                    layer[layerNum].subLayerCount = 0;

                    for (wCD = 0; wCD <= layer[layerNum].whitePieceCount;
                         wCD++) {
                        for (bCD = 0; bCD <= layer[layerNum].blackPieceCount;
                             bCD++) {
                            // calculate number of white and black pieces for group
                            // A&B
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
        WriteFile(hFilePreCalcVars, layer, sizeof(Layer) * NUM_LAYERS,
                  &dwBytesWritten, nullptr);
        WriteFile(hFilePreCalcVars, layerIndex,
                  sizeof(unsigned int) * 2 * NUM_PIECES_PER_PLAYER_PLUS_ONE *
                      NUM_PIECES_PER_PLAYER_PLUS_ONE,
                  &dwBytesWritten, nullptr);
        WriteFile(hFilePreCalcVars, nPositionsAB,
                  sizeof(unsigned int) * NUM_PIECES_PER_PLAYER_PLUS_ONE *
                      NUM_PIECES_PER_PLAYER_PLUS_ONE,
                  &dwBytesWritten, nullptr);
        WriteFile(hFilePreCalcVars, nPositionsCD,
                  sizeof(unsigned int) * NUM_PIECES_PER_PLAYER_PLUS_ONE *
                      NUM_PIECES_PER_PLAYER_PLUS_ONE,
                  &dwBytesWritten, nullptr);
        WriteFile(hFilePreCalcVars, indexAB,
                  sizeof(unsigned int) * MAX_ANZ_POSITION_A *
                      MAX_ANZ_POSITION_B,
                  &dwBytesWritten, nullptr);
        WriteFile(hFilePreCalcVars, indexCD,
                  sizeof(unsigned int) * MAX_ANZ_POSITION_C *
                      MAX_ANZ_POSITION_D,
                  &dwBytesWritten, nullptr);
        WriteFile(hFilePreCalcVars, symmetryOperationCD,
                  sizeof(unsigned char) * MAX_ANZ_POSITION_C *
                      MAX_ANZ_POSITION_D,
                  &dwBytesWritten, nullptr);
        WriteFile(hFilePreCalcVars, powerOfThree,
                  sizeof(unsigned int) * (nSquaresGroupC + nSquaresGroupD),
                  &dwBytesWritten, nullptr);
        WriteFile(hFilePreCalcVars, symmetryOperationTable,
                  sizeof(unsigned int) * SQUARE_NB * SO_COUNT,
                  &dwBytesWritten, nullptr);
        WriteFile(hFilePreCalcVars, reverseSymOperation,
                  sizeof(unsigned int) * SO_COUNT, &dwBytesWritten,
                  nullptr);
        WriteFile(hFilePreCalcVars, concSymOperation,
                  sizeof(unsigned int) * SO_COUNT *
                      SO_COUNT,
                  &dwBytesWritten, nullptr);
        WriteFile(hFilePreCalcVars, mOverN,
                  sizeof(unsigned int) * (SQUARE_NB + 1) * (SQUARE_NB + 1),
                  &dwBytesWritten, nullptr);
        WriteFile(hFilePreCalcVars, valueOfMove,
                  sizeof(unsigned char) * SQUARE_NB * SQUARE_NB,
                  &dwBytesWritten, nullptr);
        WriteFile(hFilePreCalcVars, plyInfoForOutput,
                  sizeof(PlyInfoVarType) * SQUARE_NB * SQUARE_NB,
                  &dwBytesWritten, nullptr);
        WriteFile(hFilePreCalcVars, incidencesValuesSubMoves,
                  sizeof(unsigned int) * 4 * SQUARE_NB * SQUARE_NB,
                  &dwBytesWritten, nullptr);

        // process originalStateAB[][]
        for (a = 0; a <= NUM_PIECES_PER_PLAYER; a++) {
            for (b = 0; b <= NUM_PIECES_PER_PLAYER; b++) {
                if (a + b > nSquaresGroupA + nSquaresGroupB)
                    continue;
                WriteFile(hFilePreCalcVars, originalStateAB[a][b],
                          sizeof(unsigned int) * nPositionsAB[a][b],
                          &dwBytesWritten, nullptr);
            }
        }

        // process originalStateCD[][]
        for (a = 0; a <= NUM_PIECES_PER_PLAYER; a++) {
            for (b = 0; b <= NUM_PIECES_PER_PLAYER; b++) {
                if (a + b > nSquaresGroupC + nSquaresGroupD)
                    continue;
                WriteFile(hFilePreCalcVars, originalStateCD[a][b],
                          sizeof(unsigned int) * nPositionsCD[a][b],
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
    // locals
    unsigned int curThread;

    // release memory
    for (curThread = 0; curThread < getThreadCount(); curThread++) {
        SAFE_DELETE_ARRAY(threadVars[curThread].oldStates);
        SAFE_DELETE_ARRAY(threadVars[curThread].idPossibilities);
        SAFE_DELETE_ARRAY(threadVars[curThread].possibilities);
        threadVars[curThread].field->deleteBoard();
    }
    SAFE_DELETE_ARRAY(threadVars);
}

//-----------------------------------------------------------------------------
// play()
//
//-----------------------------------------------------------------------------
void PerfectAI::play(fieldStruct *theField, unsigned int *pushFrom,
                     unsigned int *pushTo)
{
    // ... trick 17
    theField->copyBoard(&dummyField);
    // assert(dummyField.oppPlayer->id >= -1 && dummyField.oppPlayer->id <= 1);

    // locals
    threadVars[0].field = theField;
    threadVars[0].ownId = threadVars[0].field->curPlayer->id;
    unsigned int bestChoice, i;

    // assert(theField->oppPlayer->id >= -1 && theField->oppPlayer->id <= 1);

    // reset
    for (i = 0; i < SQUARE_NB * SQUARE_NB; i++) {
        valueOfMove[i] = SKV_VALUE_INVALID;
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

    if (theField->placingPhase)
        threadVars[0].fullTreeDepth = 2;
    else
        threadVars[0].fullTreeDepth = 2;

    // assert(theField->oppPlayer->id >= -1 && theField->oppPlayer->id <= 1);

    // current state already calculated?
    if (isCurrentStateInDatabase(0)) {
        cout << "PerfectAI is using database!\n\n\n";
        threadVars[0].fullTreeDepth = 3;
    } else {
        cout << "PerfectAI is thinking thinking with a depth of "
             << threadVars[0].fullTreeDepth << " steps!\n\n\n";
    }

    // assert(theField->oppPlayer->id >= -1 && theField->oppPlayer->id <= 1);

    // start the miniMax-algorithm
    Possibility *rootPossibilities = (Possibility *)getBestChoice(
        threadVars[0].fullTreeDepth, &bestChoice, POSIBILE_MOVE_COUNT_MAX);

    // assert(theField->oppPlayer->id >= -1 && theField->oppPlayer->id <= 1);

    // decode the best choice
    if (threadVars[0].field->pieceMustBeRemoved) {
        *pushFrom = bestChoice;
        *pushTo = 0;
    } else if (threadVars[0].field->placingPhase) {
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
// prepareDatabaseCalculation()
//
//-----------------------------------------------------------------------------
void PerfectAI::prepareDatabaseCalculation()
{
    // only prepare layers?
    unsigned int curThread;

    // create a temporary board
    for (curThread = 0; curThread < getThreadCount(); curThread++) {
        threadVars[curThread].field = new fieldStruct();
        threadVars[curThread].field->createBoard();
        setOpponentLevel(curThread, false);
    }

    // open database file
    openDatabase(databaseDir.c_str(), POSIBILE_MOVE_COUNT_MAX);
}

//-----------------------------------------------------------------------------
// wrapUpDatabaseCalculation()
//
//-----------------------------------------------------------------------------
void PerfectAI::wrapUpDatabaseCalculation(bool calculationAborted)
{
    // locals
    unsigned int curThread;

    // release memory
    for (curThread = 0; curThread < getThreadCount(); curThread++) {
        threadVars[curThread].field->deleteBoard();
        SAFE_DELETE(threadVars[curThread].field);
        threadVars[curThread].field = &dummyField;
    }
}

//-----------------------------------------------------------------------------
// testLayers()
//
//-----------------------------------------------------------------------------
bool PerfectAI::testLayers(unsigned int startTestFromLayer,
                           unsigned int endTestAtLayer)
{
    // locals
    unsigned int curLayer;
    bool result = true;

    for (curLayer = startTestFromLayer; curLayer <= endTestAtLayer;
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
    } else {
        cout << "Path to database set to: " << dir << endl;
        databaseDir.assign(dir);
        return true;
    }
}

//-----------------------------------------------------------------------------
// prepareBestChoiceCalculation()
//
//-----------------------------------------------------------------------------
void PerfectAI::prepareBestChoiceCalculation()
{
    for (unsigned int curThread = 0; curThread < getThreadCount();
         curThread++) {
        threadVars[curThread].floatValue = 0.0f;
        threadVars[curThread].shortValue = SKV_VALUE_INVALID;
        threadVars[curThread].gameHasFinished = false;
        threadVars[curThread].curSearchDepth = 0;
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
unsigned int *
PerfectAI::ThreadVars::getPossPlacingPhase(unsigned int *possibilityCount,
                                           void **pPossibilities)
{
    // locals
    unsigned int i;
    unsigned int *idPossibility =
        &idPossibilities[curSearchDepth * POSIBILE_MOVE_COUNT_MAX];
    bool pieceCanBeRemoved;
    unsigned int nMillsBeeingClosed;

    // check if an opponent piece can be removed
    for (pieceCanBeRemoved = false, i = 0; i < SQUARE_NB; i++) {
        if (field->board[i] == field->oppPlayer->id &&
            field->piecePartOfMill[i] == 0) {
            pieceCanBeRemoved = true;
            break;
        }
    }

    // possibilities with cut off
    for ((*possibilityCount) = 0, i = 0; i < SQUARE_NB; i++) {
        // move possible ?
        if (field->board[i] == field->squareIsFree) {
            // check if a mill is beeing closed
            nMillsBeeingClosed = 0;
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
            if ((nMillsBeeingClosed < 2) &&
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
unsigned int *
PerfectAI::ThreadVars::getPossNormalMove(unsigned int *possibilityCount,
                                         void **pPossibilities)
{
    // locals
    unsigned int from, to, dir;
    unsigned int *idPossibility =
        &idPossibilities[curSearchDepth * POSIBILE_MOVE_COUNT_MAX];
    Possibility *possibility = &possibilities[curSearchDepth];

    // if he is not allowed to spring
    if (field->curPlayer->pieceCount > 3) {
        for ((*possibilityCount) = 0, from = 0; from < SQUARE_NB; from++) {
            for (dir = 0; dir < MD_NB; dir++) {
                // destination
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
        for ((*possibilityCount) = 0, from = 0; from < SQUARE_NB; from++) {
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
        *pPossibilities = (void *)possibility;

    return idPossibility;
}

//-----------------------------------------------------------------------------
// getPossPieceRemove()
//
//-----------------------------------------------------------------------------
unsigned int *
PerfectAI::ThreadVars::getPossPieceRemove(unsigned int *possibilityCount,
                                          void **pPossibilities)
{
    // locals
    unsigned int i;
    unsigned int *idPossibility =
        &idPossibilities[curSearchDepth * POSIBILE_MOVE_COUNT_MAX];

    // possibilities with cut off
    for ((*possibilityCount) = 0, i = 0; i < SQUARE_NB; i++) {
        // move possible ?
        if (field->board[i] == field->oppPlayer->id &&
            !field->piecePartOfMill[i]) {
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
unsigned int *PerfectAI::getPossibilities(unsigned int threadNo,
                                          unsigned int *possibilityCount,
                                          bool *opponentsMove,
                                          void **pPossibilities)
{
    // locals
    bool aPieceCanBeRemovedFromCurPlayer = 0;
    unsigned int nMillsCurrentPlayer = 0;
    unsigned int nMillsOpponentPlayer = 0;
    unsigned int i;

    // set opponentsMove
    ThreadVars *tv = &threadVars[threadNo];
    *opponentsMove = (tv->field->curPlayer->id == tv->ownId) ? false : true;

    // count completed mills
    for (i = 0; i < SQUARE_NB; i++) {
        if (tv->field->board[i] == tv->field->curPlayer->id)
            nMillsCurrentPlayer += tv->field->piecePartOfMill[i];
        else
            nMillsOpponentPlayer += tv->field->piecePartOfMill[i];
        if (tv->field->piecePartOfMill[i] == 0 &&
            tv->field->board[i] == tv->field->curPlayer->id)
            aPieceCanBeRemovedFromCurPlayer = true;
    }
    nMillsCurrentPlayer /= 3;
    nMillsOpponentPlayer /= 3;

    // When game has ended of course nothing happens any more
    if (tv->gameHasFinished ||
        !tv->fieldIntegrityOK(nMillsCurrentPlayer, nMillsOpponentPlayer,
                              aPieceCanBeRemovedFromCurPlayer)) {
        *possibilityCount = 0;
        return 0;
        // look what is to do
    } else {
        if (tv->field->pieceMustBeRemoved)
            return tv->getPossPieceRemove(possibilityCount, pPossibilities);
        else if (tv->field->placingPhase)
            return tv->getPossPlacingPhase(possibilityCount, pPossibilities);
        else
            return tv->getPossNormalMove(possibilityCount, pPossibilities);
    }
}

//-----------------------------------------------------------------------------
// getSituationValue()
//
//-----------------------------------------------------------------------------
void PerfectAI::getSituationValue(unsigned int threadNo, float &floatValue,
                                    TwoBit &shortValue)
{
    ThreadVars *tv = &threadVars[threadNo];
    floatValue = tv->floatValue;
    shortValue = tv->shortValue;
}

//-----------------------------------------------------------------------------
// deletePossibilities()
//
//-----------------------------------------------------------------------------
void PerfectAI::deletePossibilities(unsigned int threadNo, void *pPossibilities)
{ }

//-----------------------------------------------------------------------------
// undo()
//
//-----------------------------------------------------------------------------
void PerfectAI::undo(unsigned int threadNo, unsigned int idPossibility,
                     bool opponentsMove, void *pBackup, void *pPossibilities)
{
    // locals
    ThreadVars *tv = &threadVars[threadNo];
    Backup *oldState = (Backup *)pBackup;

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
    tv->field->placingPhase = oldState->placingPhase;
    tv->field->piecesSet = oldState->piecesSet;
    tv->field->pieceMustBeRemoved = oldState->pieceMustBeRemoved;
    tv->field->board[oldState->from] = oldState->fieldFrom;
    tv->field->board[oldState->to] = oldState->fieldTo;

    // very expensive
    for (int i = 0; i < SQUARE_NB; i++) {
        tv->field->piecePartOfMill[i] = oldState->piecePartOfMill[i];
    }
}

//-----------------------------------------------------------------------------
// setWarning()
//
//-----------------------------------------------------------------------------
inline void PerfectAI::ThreadVars::setWarning(unsigned int pieceOne,
                                              unsigned int pieceTwo,
                                              unsigned int pieceThree)
{
    // if all 3 fields are occupied by current player than he closed a mill
    if (field->board[pieceOne] == field->curPlayer->id &&
        field->board[pieceTwo] == field->curPlayer->id &&
        field->board[pieceThree] == field->curPlayer->id) {
        field->piecePartOfMill[pieceOne]++;
        field->piecePartOfMill[pieceTwo]++;
        field->piecePartOfMill[pieceThree]++;
        field->pieceMustBeRemoved = 1;
    }

    // is a mill destroyed ?
    if (field->board[pieceOne] == field->squareIsFree &&
        field->piecePartOfMill[pieceOne] && field->piecePartOfMill[pieceTwo] &&
        field->piecePartOfMill[pieceThree]) {
        field->piecePartOfMill[pieceOne]--;
        field->piecePartOfMill[pieceTwo]--;
        field->piecePartOfMill[pieceThree]--;
    }
}

//-----------------------------------------------------------------------------
// updateWarning()
//
//-----------------------------------------------------------------------------
inline void PerfectAI::ThreadVars::updateWarning(unsigned int firstPiece,
                                                 unsigned int secondPiece)
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
    unsigned int i;
    bool atLeastOnePieceRemoveAble = false;
    if (field->pieceMustBeRemoved) {
        for (i = 0; i < SQUARE_NB; i++) {
            if (field->piecePartOfMill[i] == 0 &&
                field->board[i] == field->oppPlayer->id) {
                atLeastOnePieceRemoveAble = true;
                break;
            }
        }
    }
    if (!atLeastOnePieceRemoveAble)
        field->pieceMustBeRemoved = 0;
}

//-----------------------------------------------------------------------------
// updatePossibleMoves()
//
//-----------------------------------------------------------------------------
inline void PerfectAI::ThreadVars::updatePossibleMoves(unsigned int piece,
                                                       Player *pieceOwner,
                                                       bool pieceRemoved,
                                                       unsigned int ignorePiece)
{
    // locals
    unsigned int neighbor, direction;

    // look into every direction
    for (direction = 0; direction < MD_NB; direction++) {
        neighbor = field->connectedSquare[piece][direction];

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
    if (field->curPlayer->pieceCount <= 3 && !field->placingPhase)
        field->curPlayer->possibleMovesCount = field->curPlayer->pieceCount *
                                               (SQUARE_NB -
                                                field->curPlayer->pieceCount -
                                                field->oppPlayer->pieceCount);
    if (field->oppPlayer->pieceCount <= 3 && !field->placingPhase)
        field->oppPlayer->possibleMovesCount = field->oppPlayer->pieceCount *
                                               (SQUARE_NB -
                                                field->curPlayer->pieceCount -
                                                field->oppPlayer->pieceCount);
}

//-----------------------------------------------------------------------------
// setPiece()
//
//-----------------------------------------------------------------------------
inline void PerfectAI::ThreadVars::setPiece(unsigned int to, Backup *backup)
{
    // backup
    backup->from = SQUARE_NB;
    backup->to = to;
    backup->fieldFrom = SQUARE_NB;
    backup->fieldTo = field->board[to];

    // set piece into board
    field->board[to] = field->curPlayer->id;
    field->curPlayer->pieceCount++;
    field->piecesSet++;

    // placing phase finished ?
    if (field->piecesSet == 18)
        field->placingPhase = false;

    // update possible moves
    updatePossibleMoves(to, field->curPlayer, false, SQUARE_NB);

    // update warnings
    updateWarning(to, SQUARE_NB);
}

//-----------------------------------------------------------------------------
// normalMove()
//
//-----------------------------------------------------------------------------
inline void PerfectAI::ThreadVars::normalMove(unsigned int from,
                                              unsigned int to, Backup *backup)
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
inline void PerfectAI::ThreadVars::removePiece(unsigned int from,
                                               Backup *backup)
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
    field->pieceMustBeRemoved--;

    // update possible moves
    updatePossibleMoves(from, field->oppPlayer, true, SQUARE_NB);

    // update warnings
    updateWarning(from, SQUARE_NB);

    // end of game ?
    if ((field->oppPlayer->pieceCount < 3) && (!field->placingPhase))
        gameHasFinished = true;
}

//-----------------------------------------------------------------------------
// move()
//
//-----------------------------------------------------------------------------
void PerfectAI::move(unsigned int threadNo, unsigned int idPossibility,
                     bool opponentsMove, void **pBackup, void *pPossibilities)
{
    // locals
    ThreadVars *tv = &threadVars[threadNo];
    Backup *oldState = &tv->oldStates[tv->curSearchDepth];
    Possibility *tmpPossibility = (Possibility *)pPossibilities;
    Player *tmpPlayer;
    unsigned int i;

    // calculate place of piece
    *pBackup = (void *)oldState;
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
    oldState->placingPhase = tv->field->placingPhase;
    oldState->piecesSet = tv->field->piecesSet;
    oldState->pieceMustBeRemoved = tv->field->pieceMustBeRemoved;
    tv->curSearchDepth++;

    // very expensive
    for (i = 0; i < SQUARE_NB; i++) {
        oldState->piecePartOfMill[i] = tv->field->piecePartOfMill[i];
    }

    // move
    if (tv->field->pieceMustBeRemoved) {
        tv->removePiece(idPossibility, oldState);
    } else if (tv->field->placingPhase) {
        tv->setPiece(idPossibility, oldState);
    } else {
        tv->normalMove(tmpPossibility->from[idPossibility],
                       tmpPossibility->to[idPossibility], oldState);
    }

    // when opponent is unable to move than current player has won
    if ((!tv->field->oppPlayer->possibleMovesCount) &&
        (!tv->field->placingPhase) && (!tv->field->pieceMustBeRemoved) &&
        (tv->field->oppPlayer->pieceCount > 3))
        tv->gameHasFinished = true;

    // when game has finished - perfect for the current player
    if (tv->gameHasFinished && !opponentsMove)
        tv->shortValue = SKV_VALUE_GAME_WON;
    if (tv->gameHasFinished && opponentsMove)
        tv->shortValue = SKV_VALUE_GAME_LOST;

    tv->floatValue = tv->shortValue;

    // calc value
    if (!opponentsMove)
        tv->floatValue = (float)tv->field->oppPlayer->removedPiecesCount -
                         tv->field->curPlayer->removedPiecesCount +
                         tv->field->pieceMustBeRemoved +
                         tv->field->curPlayer->possibleMovesCount * 0.1f -
                         tv->field->oppPlayer->possibleMovesCount * 0.1f;
    else
        tv->floatValue = (float)tv->field->curPlayer->removedPiecesCount -
                         tv->field->oppPlayer->removedPiecesCount -
                         tv->field->pieceMustBeRemoved +
                         tv->field->oppPlayer->possibleMovesCount * 0.1f -
                         tv->field->curPlayer->possibleMovesCount * 0.1f;

    // when game has finished - perfect for the current player
    if (tv->gameHasFinished && !opponentsMove)
        tv->floatValue = VALUE_GAME_WON - tv->curSearchDepth;
    if (tv->gameHasFinished && opponentsMove)
        tv->floatValue = VALUE_GAME_LOST + tv->curSearchDepth;

    // set next player
    if (!tv->field->pieceMustBeRemoved) {
        tmpPlayer = tv->field->curPlayer;
        tv->field->curPlayer = tv->field->oppPlayer;
        tv->field->oppPlayer = tmpPlayer;
    }
}

//-----------------------------------------------------------------------------
// storeValueOfMove()
//
//-----------------------------------------------------------------------------
void PerfectAI::storeValueOfMove(unsigned int threadNo,
                                 unsigned int idPossibility,
                                 void *pPossibilities, unsigned char value,
                                 unsigned int *freqValuesSubMoves,
                                 PlyInfoVarType plyInfo)
{
    // locals
    ThreadVars *tv = &threadVars[threadNo];
    unsigned int index;
    Possibility *tmpPossibility = (Possibility *)pPossibilities;

    if (tv->field->pieceMustBeRemoved)
        index = idPossibility;
    else if (tv->field->placingPhase)
        index = idPossibility;
    else
        index = tmpPossibility->from[idPossibility] * SQUARE_NB +
                tmpPossibility->to[idPossibility];

    plyInfoForOutput[index] = plyInfo;
    valueOfMove[index] = value;
    incidencesValuesSubMoves[index][SKV_VALUE_INVALID] =
        freqValuesSubMoves[SKV_VALUE_INVALID];
    incidencesValuesSubMoves[index][SKV_VALUE_GAME_LOST] =
        freqValuesSubMoves[SKV_VALUE_GAME_LOST];
    incidencesValuesSubMoves[index][SKV_VALUE_GAME_DRAWN] =
        freqValuesSubMoves[SKV_VALUE_GAME_DRAWN];
    incidencesValuesSubMoves[index][SKV_VALUE_GAME_WON] =
        freqValuesSubMoves[SKV_VALUE_GAME_WON];
}

//-----------------------------------------------------------------------------
// getValueOfMoves()
//
//-----------------------------------------------------------------------------
void PerfectAI::getValueOfMoves(unsigned char *moveValue,
                                unsigned int *freqValuesSubMoves,
                                PlyInfoVarType *plyInfo,
                                unsigned int *moveQuality,
                                unsigned char &knotValue,
                                PlyInfoVarType &bestAmountOfPlies)
{
    // locals
    unsigned int moveQualities[SQUARE_NB * SQUARE_NB]; // 0 is
                                                       // bad, 1
                                                       // is
                                                       // good
    unsigned int i, j;

    // set an invalid default value
    knotValue = SKV_VALUE_COUNT;

    // calc knotValue
    for (i = 0; i < SQUARE_NB; i++) {
        for (j = 0; j < SQUARE_NB; j++) {
            if (valueOfMove[i * SQUARE_NB + j] == SKV_VALUE_GAME_WON) {
                knotValue = SKV_VALUE_GAME_WON;
                i = SQUARE_NB;
                j = SQUARE_NB;
            } else if (valueOfMove[i * SQUARE_NB + j] == SKV_VALUE_GAME_DRAWN) {
                knotValue = SKV_VALUE_GAME_DRAWN;
            } else if (valueOfMove[i * SQUARE_NB + j] == SKV_VALUE_GAME_LOST &&
                       knotValue != SKV_VALUE_GAME_DRAWN) {
                knotValue = SKV_VALUE_GAME_LOST;
            }
        }
    }

    // calc move bestAmountOfPlies
    if (knotValue == SKV_VALUE_GAME_WON) {
        bestAmountOfPlies = PLYINFO_VALUE_INVALID;

        for (i = 0; i < SQUARE_NB; i++) {
            for (j = 0; j < SQUARE_NB; j++) {
                if (valueOfMove[i * SQUARE_NB + j] == SKV_VALUE_GAME_WON) {
                    if (bestAmountOfPlies >=
                        plyInfoForOutput[i * SQUARE_NB + j]) {
                        bestAmountOfPlies = plyInfoForOutput[i * SQUARE_NB + j];
                    }
                }
            }
        }
    } else if (knotValue == SKV_VALUE_GAME_LOST) {
        bestAmountOfPlies = 0;

        for (i = 0; i < SQUARE_NB; i++) {
            for (j = 0; j < SQUARE_NB; j++) {
                if (valueOfMove[i * SQUARE_NB + j] == SKV_VALUE_GAME_LOST) {
                    if (bestAmountOfPlies <=
                        plyInfoForOutput[i * SQUARE_NB + j]) {
                        bestAmountOfPlies = plyInfoForOutput[i * SQUARE_NB + j];
                    }
                }
            }
        }
    } else if (knotValue == SKV_VALUE_GAME_DRAWN) {
        bestAmountOfPlies = 0;

        for (i = 0; i < SQUARE_NB; i++) {
            for (j = 0; j < SQUARE_NB; j++) {
                if (valueOfMove[i * SQUARE_NB + j] == SKV_VALUE_GAME_DRAWN) {
                    if (bestAmountOfPlies <=
                        incidencesValuesSubMoves[i * SQUARE_NB + j]
                                                [SKV_VALUE_GAME_WON]) {
                        bestAmountOfPlies =
                            incidencesValuesSubMoves[i * SQUARE_NB + j]
                                                    [SKV_VALUE_GAME_WON];
                    }
                }
            }
        }
    }

    // zero move qualities
    for (i = 0; i < SQUARE_NB; i++) {
        for (j = 0; j < SQUARE_NB; j++) {
            if ((valueOfMove[i * SQUARE_NB + j] == knotValue &&
                 bestAmountOfPlies == plyInfoForOutput[i * SQUARE_NB + j] &&
                 knotValue != SKV_VALUE_GAME_DRAWN) ||
                (valueOfMove[i * SQUARE_NB + j] == knotValue &&
                 bestAmountOfPlies ==
                     incidencesValuesSubMoves[i * SQUARE_NB + j]
                                             [SKV_VALUE_GAME_WON] &&
                 knotValue == SKV_VALUE_GAME_DRAWN)) {
                moveQualities[i * SQUARE_NB + j] = 1;
            } else {
                moveQualities[i * SQUARE_NB + j] = 0;
            }
        }
    }

    // copy
    memcpy(moveQuality, moveQualities,
           sizeof(unsigned int) * SQUARE_NB * SQUARE_NB);
    memcpy(plyInfo, plyInfoForOutput,
           sizeof(PlyInfoVarType) * SQUARE_NB * SQUARE_NB);
    memcpy(moveValue, valueOfMove,
           sizeof(unsigned char) * SQUARE_NB * SQUARE_NB);
    memcpy(freqValuesSubMoves, incidencesValuesSubMoves,
           sizeof(unsigned int) * SQUARE_NB * SQUARE_NB * 4);
}

//-----------------------------------------------------------------------------
// printMoveInformation()
//
//-----------------------------------------------------------------------------
void PerfectAI::printMoveInformation(unsigned int threadNo,
                                     unsigned int idPossibility,
                                     void *pPossibilities)
{
    // locals
    ThreadVars *tv = &threadVars[threadNo];
    Possibility *tmpPossibility = (Possibility *)pPossibilities;

    // move
    if (tv->field->pieceMustBeRemoved)
        cout << "remove piece from " << (char)(idPossibility + 97);
    else if (tv->field->placingPhase)
        cout << "set piece to " << (char)(idPossibility + 97);
    else
        cout << "move from " << (char)(tmpPossibility->from[idPossibility] + 97)
             << " to " << (char)(tmpPossibility->to[idPossibility] + 97);
}

//-----------------------------------------------------------------------------
// getNumberOfLayers()
// called one time
//-----------------------------------------------------------------------------
unsigned int PerfectAI::getNumberOfLayers()
{
    return NUM_LAYERS;
}

//-----------------------------------------------------------------------------
// shallRetroAnalysisBeUsed()
// called one time for each layer time
//-----------------------------------------------------------------------------
bool PerfectAI::shallRetroAnalysisBeUsed(unsigned int layerNum)
{
    if (layerNum < 100)
        return true;
    else
        return false;
}

//-----------------------------------------------------------------------------
// getNumberOfKnotsInLayer()
// called one time
//-----------------------------------------------------------------------------
unsigned int PerfectAI::getNumberOfKnotsInLayer(unsigned int layerNum)
{
    // locals
    unsigned int nKnots =
        layer[layerNum].subLayer[layer[layerNum].subLayerCount - 1].maxIndex +
        1;

    // times two since either an own piece must be moved or an opponent piece
    // must be removed
    nKnots *= MAX_NUM_PIECES_REMOVED_MINUS_1;

    // return zero if layer is not reachable
    if (((layer[layerNum].blackPieceCount < 2 ||
          layer[layerNum].whitePieceCount < 2) &&
         layerNum < 100) // moving phase
        || (layerNum < NUM_LAYERS && layer[layerNum].blackPieceCount == 2 &&
            layer[layerNum].whitePieceCount == 2 && layerNum < 100) ||
        (layerNum == 100))
        return 0;

    // another way
    return (unsigned int)nKnots;
}

//-----------------------------------------------------------------------------
// nOverN()
// called seldom
//-----------------------------------------------------------------------------
int64_t PerfectAI::mOverN_Function(unsigned int m, unsigned int n)
{
    // locals
    int64_t result = 1;
    int64_t fakN = 1;
    unsigned int i;

    // invalid params ?
    if (n > m)
        return 0;

    // flip, since then the result value won't get so high
    if (n > m / 2)
        n = m - n;

    // calc number of possibilities one can put n different pieces in m holes
    for (i = m - n + 1; i <= m; i++)
        result *= i;

    // calc number of possibilities one can sort n different pieces
    for (i = 1; i <= n; i++)
        fakN *= i;

    // divide
    result /= fakN;

    return result;
}

//-----------------------------------------------------------------------------
// applySymmetryOperationOnField()
// called very often
//-----------------------------------------------------------------------------
void PerfectAI::applySymmetryOperationOnField(
    unsigned char symmetryOperationNumber, unsigned int *sourceField,
    unsigned int *destField)
{
    for (unsigned int i = 0; i < SQUARE_NB; i++) {
        destField[i] =
            sourceField[symmetryOperationTable[symmetryOperationNumber][i]];
    }
}

//-----------------------------------------------------------------------------
// getLayerNumber()
//
//-----------------------------------------------------------------------------
unsigned int PerfectAI::getLayerNumber(unsigned int threadNo)
{
    ThreadVars *tv = &threadVars[threadNo];
    unsigned int blackPieceCount = tv->field->oppPlayer->pieceCount;
    unsigned int whitePieceCount = tv->field->curPlayer->pieceCount;
    unsigned int phaseIndex = (tv->field->placingPhase == true) ?
                                  LAYER_INDEX_PLACING_PHASE :
                                  LAYER_INDEX_MOVING_PHASE;
    return layerIndex[phaseIndex][whitePieceCount][blackPieceCount];
}

//-----------------------------------------------------------------------------
// getLayerAndStateNumber()
//
//-----------------------------------------------------------------------------
unsigned int PerfectAI::getLayerAndStateNumber(unsigned int threadNo,
                                               unsigned int &layerNum,
                                               unsigned int &stateNumber)
{
    ThreadVars *tv = &threadVars[threadNo];
    return tv->getLayerAndStateNumber(layerNum, stateNumber);
}

//-----------------------------------------------------------------------------
// getLayerAndStateNumber()
// Current player has white pieces, the opponent the black ones.
//-----------------------------------------------------------------------------
unsigned int
PerfectAI::ThreadVars::getLayerAndStateNumber(unsigned int &layerNum,
                                              unsigned int &stateNumber)
{
    // locals
    unsigned int myField[SQUARE_NB];
    unsigned int symField[SQUARE_NB];
    unsigned int blackPieceCount = field->oppPlayer->pieceCount;
    unsigned int whitePieceCount = field->curPlayer->pieceCount;
    unsigned int phaseIndex = (field->placingPhase == true) ?
                                  LAYER_INDEX_PLACING_PHASE :
                                  LAYER_INDEX_MOVING_PHASE;
    unsigned int wCD = 0, bCD = 0;
    unsigned int stateAB, stateCD;
    unsigned int i;

    // layer number
    layerNum = parent->layerIndex[phaseIndex][whitePieceCount][blackPieceCount];

    // make white and black fields
    for (i = 0; i < SQUARE_NB; i++) {
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

    // calc stateCD
    stateCD = myField[squareIndexGroupC[0]] * parent->powerOfThree[15] +
              myField[squareIndexGroupC[1]] * parent->powerOfThree[14] +
              myField[squareIndexGroupC[2]] * parent->powerOfThree[13] +
              myField[squareIndexGroupC[3]] * parent->powerOfThree[12] +
              myField[squareIndexGroupC[4]] * parent->powerOfThree[11] +
              myField[squareIndexGroupC[5]] * parent->powerOfThree[10] +
              myField[squareIndexGroupC[6]] * parent->powerOfThree[9] +
              myField[squareIndexGroupC[7]] * parent->powerOfThree[8] +
              myField[squareIndexGroupD[0]] * parent->powerOfThree[7] +
              myField[squareIndexGroupD[1]] * parent->powerOfThree[6] +
              myField[squareIndexGroupD[2]] * parent->powerOfThree[5] +
              myField[squareIndexGroupD[3]] * parent->powerOfThree[4] +
              myField[squareIndexGroupD[4]] * parent->powerOfThree[3] +
              myField[squareIndexGroupD[5]] * parent->powerOfThree[2] +
              myField[squareIndexGroupD[6]] * parent->powerOfThree[1] +
              myField[squareIndexGroupD[7]] * parent->powerOfThree[0];

    // apply symmetry operation on group A&B
    parent->applySymmetryOperationOnField(parent->symmetryOperationCD[stateCD],
                                          myField, symField);

    // calc stateAB
    stateAB = symField[squareIndexGroupA[0]] * parent->powerOfThree[7] +
              symField[squareIndexGroupA[1]] * parent->powerOfThree[6] +
              symField[squareIndexGroupA[2]] * parent->powerOfThree[5] +
              symField[squareIndexGroupA[3]] * parent->powerOfThree[4] +
              symField[squareIndexGroupB[0]] * parent->powerOfThree[3] +
              symField[squareIndexGroupB[1]] * parent->powerOfThree[2] +
              symField[squareIndexGroupB[2]] * parent->powerOfThree[1] +
              symField[squareIndexGroupB[3]] * parent->powerOfThree[0];

    // calc index
    stateNumber =
        parent->layer[layerNum]
                .subLayer[parent->layer[layerNum].subLayerIndexCD[wCD][bCD]]
                .minIndex *
            MAX_NUM_PIECES_REMOVED_MINUS_1 +
        parent->indexAB[stateAB] * parent->nPositionsCD[wCD][bCD] *
            MAX_NUM_PIECES_REMOVED_MINUS_1 +
        parent->indexCD[stateCD] * MAX_NUM_PIECES_REMOVED_MINUS_1 +
        field->pieceMustBeRemoved;

    return parent->symmetryOperationCD[stateCD];
}

//-----------------------------------------------------------------------------
// setSituation()
// Current player has white pieces, the opponent the black ones.
//     Sets up the game situation corresponding to the passed layer number and
//     state.
//-----------------------------------------------------------------------------
bool PerfectAI::setSituation(unsigned int threadNo, unsigned int layerNum,
                             unsigned int stateNumber)
{
    // params ok ?
    if (getNumberOfLayers() <= layerNum)
        return false;
    if (getNumberOfKnotsInLayer(layerNum) <= stateNumber)
        return false;

    // locals
    ThreadVars *tv = &threadVars[threadNo];
    unsigned int stateNumberWithInSubLayer;
    unsigned int stateNumberWithInAB;
    unsigned int stateNumberWithInCD;
    unsigned int stateAB, stateCD;
    unsigned int myField[SQUARE_NB];
    unsigned int symField[SQUARE_NB];
    unsigned int whitePieceCount = layer[layerNum].whitePieceCount;
    unsigned int blackPieceCount = layer[layerNum].blackPieceCount;
    unsigned int nMillsCurrentPlayer = 0;
    unsigned int nMillsOpponentPlayer = 0;
    unsigned int wCD = 0, bCD = 0, wAB = 0, bAB = 0;
    unsigned int i;
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

    tv->field->placingPhase = (layerNum >= NUM_LAYERS / 2) ?
                                  LAYER_INDEX_PLACING_PHASE :
                                  LAYER_INDEX_MOVING_PHASE;
    tv->field->pieceMustBeRemoved = stateNumber %
                                    MAX_NUM_PIECES_REMOVED_MINUS_1;
    tv->field->curPlayer->pieceCount = whitePieceCount;
    tv->field->oppPlayer->pieceCount = blackPieceCount;

    // reconstruct board->board[]
    stateNumberWithInSubLayer =
        (stateNumber / MAX_NUM_PIECES_REMOVED_MINUS_1) -
        layer[layerNum]
            .subLayer[layer[layerNum].subLayerIndexCD[wCD][bCD]]
            .minIndex;
    stateNumberWithInAB = stateNumberWithInSubLayer / nPositionsCD[wCD][bCD];
    stateNumberWithInCD = stateNumberWithInSubLayer % nPositionsCD[wCD][bCD];

    // get stateCD
    stateCD = originalStateCD[wCD][bCD][stateNumberWithInCD];
    stateAB = originalStateAB[wAB][bAB][stateNumberWithInAB];

    // set myField from stateCD and stateAB
    myField[squareIndexGroupA[0]] = (stateAB / powerOfThree[7]) % 3;
    myField[squareIndexGroupA[1]] = (stateAB / powerOfThree[6]) % 3;
    myField[squareIndexGroupA[2]] = (stateAB / powerOfThree[5]) % 3;
    myField[squareIndexGroupA[3]] = (stateAB / powerOfThree[4]) % 3;
    myField[squareIndexGroupB[0]] = (stateAB / powerOfThree[3]) % 3;
    myField[squareIndexGroupB[1]] = (stateAB / powerOfThree[2]) % 3;
    myField[squareIndexGroupB[2]] = (stateAB / powerOfThree[1]) % 3;
    myField[squareIndexGroupB[3]] = (stateAB / powerOfThree[0]) % 3;

    myField[squareIndexGroupC[0]] = (stateCD / powerOfThree[15]) % 3;
    myField[squareIndexGroupC[1]] = (stateCD / powerOfThree[14]) % 3;
    myField[squareIndexGroupC[2]] = (stateCD / powerOfThree[13]) % 3;
    myField[squareIndexGroupC[3]] = (stateCD / powerOfThree[12]) % 3;
    myField[squareIndexGroupC[4]] = (stateCD / powerOfThree[11]) % 3;
    myField[squareIndexGroupC[5]] = (stateCD / powerOfThree[10]) % 3;
    myField[squareIndexGroupC[6]] = (stateCD / powerOfThree[9]) % 3;
    myField[squareIndexGroupC[7]] = (stateCD / powerOfThree[8]) % 3;
    myField[squareIndexGroupD[0]] = (stateCD / powerOfThree[7]) % 3;
    myField[squareIndexGroupD[1]] = (stateCD / powerOfThree[6]) % 3;
    myField[squareIndexGroupD[2]] = (stateCD / powerOfThree[5]) % 3;
    myField[squareIndexGroupD[3]] = (stateCD / powerOfThree[4]) % 3;
    myField[squareIndexGroupD[4]] = (stateCD / powerOfThree[3]) % 3;
    myField[squareIndexGroupD[5]] = (stateCD / powerOfThree[2]) % 3;
    myField[squareIndexGroupD[6]] = (stateCD / powerOfThree[1]) % 3;
    myField[squareIndexGroupD[7]] = (stateCD / powerOfThree[0]) % 3;

    // apply symmetry operation on group A&B
    applySymmetryOperationOnField(
        reverseSymOperation[symmetryOperationCD[stateCD]], myField, symField);

    // translate symField[] to board->board[]
    for (i = 0; i < SQUARE_NB; i++) {
        if (symField[i] == FREE_SQUARE)
            tv->field->board[i] = fieldStruct::squareIsFree;
        else if (symField[i] == WHITE_PIECE)
            tv->field->board[i] = tv->field->curPlayer->id;
        else
            tv->field->board[i] = tv->field->oppPlayer->id;
    }

    // calc possible moves
    tv->generateMoves(tv->field->curPlayer);
    tv->generateMoves(tv->field->oppPlayer);

    // zero
    for (i = 0; i < SQUARE_NB; i++) {
        tv->field->piecePartOfMill[i] = 0;
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
        tv->field->piecePartOfMill[i] /= 3;

    // count completed mills
    for (i = 0; i < SQUARE_NB; i++) {
        if (tv->field->board[i] == tv->field->curPlayer->id)
            nMillsCurrentPlayer += tv->field->piecePartOfMill[i];
        else
            nMillsOpponentPlayer += tv->field->piecePartOfMill[i];
    }

    nMillsCurrentPlayer /= 3;
    nMillsOpponentPlayer /= 3;

    // piecesSet & removedPiecesCount
    if (tv->field->placingPhase) {
        // BUG: ... This calculation is not correct! It is possible that some
        // mills did not cause a piece removal.
        tv->field->curPlayer->removedPiecesCount = nMillsOpponentPlayer;
        tv->field->oppPlayer->removedPiecesCount = nMillsCurrentPlayer -
                                                   tv->field->pieceMustBeRemoved;
        tv->field->piecesSet = tv->field->curPlayer->pieceCount +
                               tv->field->oppPlayer->pieceCount +
                               tv->field->curPlayer->removedPiecesCount +
                               tv->field->oppPlayer->removedPiecesCount;
    } else {
        tv->field->piecesSet = 18;
        tv->field->curPlayer->removedPiecesCount = 9 - tv->field->curPlayer
                                                           ->pieceCount;
        tv->field->oppPlayer->removedPiecesCount = 9 - tv->field->oppPlayer
                                                           ->pieceCount;
    }

    // when opponent is unable to move than current player has won
    if ((!tv->field->curPlayer->possibleMovesCount) &&
        (!tv->field->placingPhase) && (!tv->field->pieceMustBeRemoved) &&
        (tv->field->curPlayer->pieceCount > 3)) {
        tv->gameHasFinished = true;
        tv->shortValue = SKV_VALUE_GAME_LOST;
    }
    if ((tv->field->curPlayer->pieceCount < 3) && (!tv->field->placingPhase)) {
        tv->gameHasFinished = true;
        tv->shortValue = SKV_VALUE_GAME_LOST;
    }
    if ((tv->field->oppPlayer->pieceCount < 3) && (!tv->field->placingPhase)) {
        tv->gameHasFinished = true;
        tv->shortValue = SKV_VALUE_GAME_WON;
    }

    tv->floatValue = tv->shortValue;

    // precalc aPieceCanBeRemovedFromCurPlayer
    for (aPieceCanBeRemovedFromCurPlayer = false, i = 0; i < SQUARE_NB; i++) {
        if (tv->field->piecePartOfMill[i] == 0 &&
            tv->field->board[i] == tv->field->curPlayer->id) {
            aPieceCanBeRemovedFromCurPlayer = true;
            break;
        }
    }

    // test if board is ok
    return tv->fieldIntegrityOK(nMillsCurrentPlayer, nMillsOpponentPlayer,
                                aPieceCanBeRemovedFromCurPlayer);
}

//-----------------------------------------------------------------------------
// generateMoves()
//
//-----------------------------------------------------------------------------
void PerfectAI::ThreadVars::generateMoves(Player *player)
{
    // locals
    unsigned int i, j, k, movingDirection;

    for (player->possibleMovesCount = 0, i = 0; i < SQUARE_NB; i++) {
        for (j = 0; j < SQUARE_NB; j++) {
            // is piece from player ?
            if (field->board[i] != player->id)
                continue;

            // is destination free ?
            if (field->board[j] != field->squareIsFree)
                continue;

            // when current player has only 3 pieces he is allowed to spring his
            // piece
            if (player->pieceCount > 3 || field->placingPhase) {
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
void PerfectAI::ThreadVars::setWarningAndMill(unsigned int piece,
                                              unsigned int firstNeighbor,
                                              unsigned int secondNeighbor)
{
    // locals
    int rowOwner = field->board[piece];

    // mill closed ?
    if (rowOwner != field->squareIsFree &&
        field->board[firstNeighbor] == rowOwner &&
        field->board[secondNeighbor] == rowOwner) {
        field->piecePartOfMill[piece]++;
        field->piecePartOfMill[firstNeighbor]++;
        field->piecePartOfMill[secondNeighbor]++;
    }
}

//-----------------------------------------------------------------------------
// getOutputInformation()
//
//-----------------------------------------------------------------------------
string PerfectAI::getOutputInformation(unsigned int layerNum)
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
void PerfectAI::printBoard(unsigned int threadNo, unsigned char value)
{
    ThreadVars *tv = &threadVars[threadNo];
    char wonStr[] = "WON";
    char lostStr[] = "LOST";
    char drawStr[] = "DRAW";
    char invStr[] = "INVALID";
    char *table[4] = {invStr, lostStr, drawStr, wonStr};

    cout << "\nstate value             : " << table[value];
    cout << "\npieces set              : " << tv->field->piecesSet << "\n";
    tv->field->printBoard();
}

//-----------------------------------------------------------------------------
// getField()
//
//-----------------------------------------------------------------------------
void PerfectAI::getField(unsigned int layerNum, unsigned int stateNumber,
                         fieldStruct *field, bool *gameHasFinished)
{
    // set current desired state on thread zero
    setSituation(0, layerNum, stateNumber);

    // copy content of fieldStruct
    threadVars[0].field->copyBoard(field);
    if (gameHasFinished != nullptr)
        *gameHasFinished = threadVars[0].gameHasFinished;
}

//-----------------------------------------------------------------------------
// getLayerAndStateNumber()
//
//-----------------------------------------------------------------------------
void PerfectAI::getLayerAndStateNumber(
    unsigned int &layerNum,
    unsigned int &stateNumber /*, unsigned int& symmetryOperation*/)
{
    /*symmetryOperation = */ threadVars[0].getLayerAndStateNumber(layerNum,
                                                                  stateNumber);
}

//-----------------------------------------------------------------------------
// setOpponentLevel()
//
//-----------------------------------------------------------------------------
void PerfectAI::setOpponentLevel(unsigned int threadNo, bool isOpponentLevel)
{
    ThreadVars *tv = &threadVars[threadNo];
    tv->ownId = isOpponentLevel ? tv->field->oppPlayer->id :
                                  tv->field->curPlayer->id;
}

//-----------------------------------------------------------------------------
// getOpponentLevel()
//
//-----------------------------------------------------------------------------
bool PerfectAI::getOpponentLevel(unsigned int threadNo)
{
    ThreadVars *tv = &threadVars[threadNo];
    return (tv->ownId == tv->field->oppPlayer->id);
}

//-----------------------------------------------------------------------------
// getPartnerLayer()
//
//-----------------------------------------------------------------------------
unsigned int PerfectAI::getPartnerLayer(unsigned int layerNum)
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
void PerfectAI::getSuccLayers(unsigned int layerNum,
                              unsigned int *amountOfSuccLayers,
                              unsigned int *succeedingLayers)
{
    // locals
    unsigned int i;
    unsigned int shift = (layerNum >= 100) ? 100 : 0;
    int diff = (layerNum >= 100) ? 1 : -1;

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
void PerfectAI::getSymStateNumWithDoubles(unsigned int threadNo,
                                          unsigned int *nSymmetricStates,
                                          unsigned int **symStateNumbers)
{
    // locals
    ThreadVars *tv = &threadVars[threadNo];
    int originalField[SQUARE_NB];
    unsigned int originalPartOfMill[SQUARE_NB];
    unsigned int i, symmetryOperation;
    unsigned int layerNum, stateNum;

    *nSymmetricStates = 0;
    *symStateNumbers = symmetricStateNumberArray;

    // save current board
    for (i = 0; i < SQUARE_NB; i++) {
        originalField[i] = tv->field->board[i];
        originalPartOfMill[i] = tv->field->piecePartOfMill[i];
    }

    // add all symmetric states
    for (symmetryOperation = 0; symmetryOperation < SO_COUNT;
         symmetryOperation++) {
        // apply symmetry operation
        applySymmetryOperationOnField(symmetryOperation,
                                      (unsigned int *)originalField,
                                      (unsigned int *)tv->field->board);
        applySymmetryOperationOnField(
            symmetryOperation, (unsigned int *)originalPartOfMill,
            (unsigned int *)tv->field->piecePartOfMill);

        getLayerAndStateNumber(threadNo, layerNum, stateNum);
        symmetricStateNumberArray[*nSymmetricStates] = stateNum;
        (*nSymmetricStates)++;
    }

    // restore original board
    for (i = 0; i < SQUARE_NB; i++) {
        tv->field->board[i] = originalField[i];
        tv->field->piecePartOfMill[i] = originalPartOfMill[i];
    }
}

//-----------------------------------------------------------------------------
// fieldIntegrityOK()
//
//-----------------------------------------------------------------------------
bool PerfectAI::ThreadVars::fieldIntegrityOK(
    unsigned int nMillsCurrentPlayer, unsigned int nMillsOpponentPlayer,
    bool aPieceCanBeRemovedFromCurPlayer)
{
    // locals
    int i, j;
    bool noneFullFilled;

    // when piece is going to be removed than at least one opponent piece
    // mustn't be part of a mill
    if (nMillsOpponentPlayer > 0 && field->pieceMustBeRemoved) {
        for (i = 0; i < SQUARE_NB; i++)
            if (field->piecePartOfMill[i] == 0 &&
                field->oppPlayer->id == field->board[i])
                break;
        if (i == SQUARE_NB)
            return false;
    }

    // when no mill is closed than no piece can be removed
    if (field->pieceMustBeRemoved && nMillsCurrentPlayer == 0) {
        return false;

        // when in placing phase and difference in number of pieces between the
        // two players is not
    } else if (field->placingPhase) {
        // Version 8: added for-loop
        noneFullFilled = true;

        for (i = 0; noneFullFilled && i <= (int)nMillsOpponentPlayer &&
                    i <= (int)nMillsCurrentPlayer;
             i++) {
            for (j = 0;
                 noneFullFilled && j <= (int)nMillsOpponentPlayer &&
                 j <= (int)nMillsCurrentPlayer - (int)field->pieceMustBeRemoved;
                 j++) {
                if (field->curPlayer->pieceCount + nMillsOpponentPlayer + 0 -
                        field->pieceMustBeRemoved - j ==
                    field->oppPlayer->pieceCount + nMillsCurrentPlayer -
                        field->pieceMustBeRemoved - i)
                    noneFullFilled = false;
                if (field->curPlayer->pieceCount + nMillsOpponentPlayer + 1 -
                        field->pieceMustBeRemoved - j ==
                    field->oppPlayer->pieceCount + nMillsCurrentPlayer -
                        field->pieceMustBeRemoved - i)
                    noneFullFilled = false;
            }
        }

        if (noneFullFilled || field->piecesSet >= 18) {
            return false;
        }

        // moving phase
    } else if (!field->placingPhase && (field->curPlayer->pieceCount < 2 ||
                                        field->oppPlayer->pieceCount < 2)) {
        return false;
    }

    return true;
}

//-----------------------------------------------------------------------------
// isSymOperationInvariantOnGroupCD()
//
//-----------------------------------------------------------------------------
bool PerfectAI::isSymOperationInvariantOnGroupCD(unsigned int symmetryOperation,
                                                 int *theField)
{
    // locals
    unsigned int i;

    i = squareIndexGroupC[0];
    if (theField[i] != theField[symmetryOperationTable[symmetryOperation][i]])
        return false;
    i = squareIndexGroupC[1];
    if (theField[i] != theField[symmetryOperationTable[symmetryOperation][i]])
        return false;
    i = squareIndexGroupC[2];
    if (theField[i] != theField[symmetryOperationTable[symmetryOperation][i]])
        return false;
    i = squareIndexGroupC[3];
    if (theField[i] != theField[symmetryOperationTable[symmetryOperation][i]])
        return false;
    i = squareIndexGroupC[4];
    if (theField[i] != theField[symmetryOperationTable[symmetryOperation][i]])
        return false;
    i = squareIndexGroupC[5];
    if (theField[i] != theField[symmetryOperationTable[symmetryOperation][i]])
        return false;
    i = squareIndexGroupC[6];
    if (theField[i] != theField[symmetryOperationTable[symmetryOperation][i]])
        return false;
    i = squareIndexGroupC[7];
    if (theField[i] != theField[symmetryOperationTable[symmetryOperation][i]])
        return false;
    i = squareIndexGroupD[0];
    if (theField[i] != theField[symmetryOperationTable[symmetryOperation][i]])
        return false;
    i = squareIndexGroupD[1];
    if (theField[i] != theField[symmetryOperationTable[symmetryOperation][i]])
        return false;
    i = squareIndexGroupD[2];
    if (theField[i] != theField[symmetryOperationTable[symmetryOperation][i]])
        return false;
    i = squareIndexGroupD[3];
    if (theField[i] != theField[symmetryOperationTable[symmetryOperation][i]])
        return false;
    i = squareIndexGroupD[4];
    if (theField[i] != theField[symmetryOperationTable[symmetryOperation][i]])
        return false;
    i = squareIndexGroupD[5];
    if (theField[i] != theField[symmetryOperationTable[symmetryOperation][i]])
        return false;
    i = squareIndexGroupD[6];
    if (theField[i] != theField[symmetryOperationTable[symmetryOperation][i]])
        return false;
    i = squareIndexGroupD[7];
    if (theField[i] != theField[symmetryOperationTable[symmetryOperation][i]])
        return false;

    return true;
}

//-----------------------------------------------------------------------------
// storePredecessor()
//
//-----------------------------------------------------------------------------
void PerfectAI::ThreadVars::storePredecessor(unsigned int nMillsCurrentPlayer,
                                             unsigned int nMillsOpponentPlayer,
                                             unsigned int *amountOfPred,
                                             RetroAnalysisPredVars *predVars)
{
    // locals
    int originalField[SQUARE_NB];
    unsigned int i, symmetryOperation, symOpApplied;
    unsigned int predLayerNum, predStateNum;
    unsigned int originalAmountOfPred = *amountOfPred;

    // store only if state is valid
    if (fieldIntegrityOK(nMillsCurrentPlayer, nMillsOpponentPlayer, false)) {
        // save current board
        for (i = 0; i < SQUARE_NB; i++)
            originalField[i] = field->board[i];

        // add all symmetric states
        for (symmetryOperation = 0; symmetryOperation < SO_COUNT;
             symmetryOperation++) {
            // ...
            if (symmetryOperation == SO_DO_NOTHING ||
                parent->isSymOperationInvariantOnGroupCD(symmetryOperation,
                                                         originalField)) {
                // apply symmetry operation
                parent->applySymmetryOperationOnField(
                    symmetryOperation, (unsigned int *)originalField,
                    (unsigned int *)field->board);

                symOpApplied = getLayerAndStateNumber(predLayerNum,
                                                      predStateNum);
                predVars[*amountOfPred].predSymOperation =
                    parent->concSymOperation[symmetryOperation][symOpApplied];
                predVars[*amountOfPred].predLayerNumbers = predLayerNum;
                predVars[*amountOfPred].predStateNumbers = predStateNum;
                predVars[*amountOfPred].playerToMoveChanged =
                    predVars[originalAmountOfPred].playerToMoveChanged;

                // add only if not already in list
                for (i = 0; i < (*amountOfPred); i++)
                    if (predVars[i].predLayerNumbers == predLayerNum &&
                        predVars[i].predStateNumbers == predStateNum)
                        break;
                if (i == *amountOfPred)
                    (*amountOfPred)++;
            }
        }

        // restore original board
        for (i = 0; i < SQUARE_NB; i++)
            field->board[i] = originalField[i];
    }
}

//-----------------------------------------------------------------------------
// getPredecessors()
// CAUTION: States mustn't be returned twice.
//-----------------------------------------------------------------------------
void PerfectAI::getPredecessors(unsigned int threadNo,
                                unsigned int *amountOfPred,
                                RetroAnalysisPredVars *predVars)
{
    ////////////////////////////////////////////////////////////////////////////
    // the important variables, which much be updated for the
    // getLayerAndStateNumber function are the following ones:
    // - board->curPlayer->pieceCount
    // - board->oppPlayer->pieceCount
    // - board->curPlayer->id
    // - board->board
    // - board->pieceMustBeRemoved
    // - board->placingPhase
    ////////////////////////////////////////////////////////////////////////////

    // locals
    ThreadVars *tv = &threadVars[threadNo];
    bool aPieceCanBeRemovedFromCurPlayer;
    bool millWasClosed;
    unsigned int from, to, dir, i;
    Player *tmpPlayer;
    unsigned int nMillsCurrentPlayer = 0;
    unsigned int nMillsOpponentPlayer = 0;

    // zero
    *amountOfPred = 0;

    // count completed mills
    for (i = 0; i < SQUARE_NB; i++) {
        if (tv->field->board[i] == tv->field->curPlayer->id)
            nMillsCurrentPlayer += tv->field->piecePartOfMill[i];
        else
            nMillsOpponentPlayer += tv->field->piecePartOfMill[i];
    }

    nMillsCurrentPlayer /= 3;
    nMillsOpponentPlayer /= 3;

    // precalc aPieceCanBeRemovedFromCurPlayer
    for (aPieceCanBeRemovedFromCurPlayer = false, i = 0; i < SQUARE_NB; i++) {
        if (tv->field->piecePartOfMill[i] == 0 &&
            tv->field->board[i] == tv->field->curPlayer->id) {
            aPieceCanBeRemovedFromCurPlayer = true;
            break;
        }
    }

    // was a mill closed?
    if (tv->field->pieceMustBeRemoved)
        millWasClosed = true;
    else
        millWasClosed = false;

    // in moving phase
    if (!tv->field->placingPhase && tv->field->curPlayer->pieceCount >= 3 &&
        tv->field->oppPlayer->pieceCount >= 3) {
        // normal move
        if ((tv->field->pieceMustBeRemoved &&
             tv->field->curPlayer->pieceCount > 3) ||
            (!tv->field->pieceMustBeRemoved &&
             tv->field->oppPlayer->pieceCount > 3)) {
            // when game has finished then because current player can't move
            // anymore or has less then 3 pieces
            if (!tv->gameHasFinished ||
                tv->field->curPlayer->possibleMovesCount == 0) {
                // test each destination
                for (to = 0; to < SQUARE_NB; to++) {
                    // was opponent player piece owner?
                    if (tv->field->board[to] != (tv->field->pieceMustBeRemoved ?
                                                     tv->field->curPlayer->id :
                                                     tv->field->oppPlayer->id))
                        continue;

                    // when piece is going to be removed than a mill must be
                    // closed
                    if (tv->field->pieceMustBeRemoved &&
                        tv->field->piecePartOfMill[to] == 0)
                        continue;

                    // when piece is part of a mill then a piece must be removed
                    if (aPieceCanBeRemovedFromCurPlayer &&
                        tv->field->pieceMustBeRemoved == 0 &&
                        tv->field->piecePartOfMill[to])
                        continue;

                    // test each direction
                    for (dir = 0; dir < MD_NB; dir++) {
                        // origin
                        from = tv->field->connectedSquare[to][dir];

                        // move possible ?
                        if (from < SQUARE_NB &&
                            tv->field->board[from] == tv->field->squareIsFree) {
                            if (millWasClosed) {
                                nMillsCurrentPlayer -=
                                    tv->field->piecePartOfMill[to];
                                tv->field->pieceMustBeRemoved = 0;
                                predVars[*amountOfPred].playerToMoveChanged =
                                    false;
                            } else {
                                predVars[*amountOfPred].playerToMoveChanged =
                                    true;
                                tmpPlayer = tv->field->curPlayer;
                                tv->field->curPlayer = tv->field->oppPlayer;
                                tv->field->oppPlayer = tmpPlayer;
                                i = nMillsCurrentPlayer;
                                nMillsCurrentPlayer = nMillsOpponentPlayer;
                                nMillsOpponentPlayer = i;
                                nMillsCurrentPlayer -=
                                    tv->field->piecePartOfMill[to];
                            }

                            // make move
                            tv->field->board[from] = tv->field->board[to];
                            tv->field->board[to] = tv->field->squareIsFree;

                            // store predecessor
                            tv->storePredecessor(nMillsCurrentPlayer,
                                                 nMillsOpponentPlayer,
                                                 amountOfPred, predVars);

                            // undo move
                            tv->field->board[to] = tv->field->board[from];
                            tv->field->board[from] = tv->field->squareIsFree;

                            if (millWasClosed) {
                                nMillsCurrentPlayer +=
                                    tv->field->piecePartOfMill[to];
                                tv->field->pieceMustBeRemoved = 1;
                            } else {
                                tmpPlayer = tv->field->curPlayer;
                                tv->field->curPlayer = tv->field->oppPlayer;
                                tv->field->oppPlayer = tmpPlayer;
                                nMillsCurrentPlayer +=
                                    tv->field->piecePartOfMill[to];
                                i = nMillsCurrentPlayer;
                                nMillsCurrentPlayer = nMillsOpponentPlayer;
                                nMillsOpponentPlayer = i;
                            }

                            // current or opponent player were allowed to spring
                        }
                    }
                }
            }

        } else if (!tv->gameHasFinished) {
            // test each destination
            for (to = 0; to < SQUARE_NB; to++) {
                // when piece must be removed than current player closed a mill,
                // otherwise the opponent did a common spring move
                if (tv->field->board[to] != (tv->field->pieceMustBeRemoved ?
                                                 tv->field->curPlayer->id :
                                                 tv->field->oppPlayer->id))
                    continue;

                // when piece is going to be removed than a mill must be closed
                if (tv->field->pieceMustBeRemoved &&
                    tv->field->piecePartOfMill[to] == 0)
                    continue;

                // when piece is part of a mill then a piece must be removed
                if (aPieceCanBeRemovedFromCurPlayer &&
                    tv->field->pieceMustBeRemoved == 0 &&
                    tv->field->piecePartOfMill[to])
                    continue;

                // test each direction
                for (from = 0; from < SQUARE_NB; from++) {
                    // move possible ?
                    if (tv->field->board[from] == tv->field->squareIsFree) {
                        // was a mill closed?
                        if (millWasClosed) {
                            nMillsCurrentPlayer -= tv->field
                                                       ->piecePartOfMill[to];
                            tv->field->pieceMustBeRemoved = 0;
                            predVars[*amountOfPred].playerToMoveChanged = false;
                        } else {
                            predVars[*amountOfPred].playerToMoveChanged = true;
                            tmpPlayer = tv->field->curPlayer;
                            tv->field->curPlayer = tv->field->oppPlayer;
                            tv->field->oppPlayer = tmpPlayer;
                            i = nMillsCurrentPlayer;
                            nMillsCurrentPlayer = nMillsOpponentPlayer;
                            nMillsOpponentPlayer = i;
                            nMillsCurrentPlayer -= tv->field
                                                       ->piecePartOfMill[to];
                        }

                        // make move
                        tv->field->board[from] = tv->field->board[to];
                        tv->field->board[to] = tv->field->squareIsFree;

                        // store predecessor
                        tv->storePredecessor(nMillsCurrentPlayer,
                                             nMillsOpponentPlayer, amountOfPred,
                                             predVars);

                        // undo move
                        tv->field->board[to] = tv->field->board[from];
                        tv->field->board[from] = tv->field->squareIsFree;

                        if (millWasClosed) {
                            nMillsCurrentPlayer += tv->field
                                                       ->piecePartOfMill[to];
                            tv->field->pieceMustBeRemoved = 1;
                        } else {
                            tmpPlayer = tv->field->curPlayer;
                            tv->field->curPlayer = tv->field->oppPlayer;
                            tv->field->oppPlayer = tmpPlayer;
                            nMillsCurrentPlayer += tv->field
                                                       ->piecePartOfMill[to];
                            i = nMillsCurrentPlayer;
                            nMillsCurrentPlayer = nMillsOpponentPlayer;
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
        tv->field->pieceMustBeRemoved == 0) {
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
                        tv->field->pieceMustBeRemoved = 1;
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
                                             nMillsCurrentPlayer, amountOfPred,
                                             predVars);

                        tmpPlayer = tv->field->curPlayer;
                        tv->field->curPlayer = tv->field->oppPlayer;
                        tv->field->oppPlayer = tmpPlayer;

                        // remove piece again
                        tv->field->pieceMustBeRemoved = 0;
                        tv->field->board[from] = tv->field->squareIsFree;
                        tv->field->curPlayer->pieceCount--;
                        tv->field->curPlayer->removedPiecesCount++;
                    }
                }
            }
        }
    }
}

//-----------------------------------------------------------------------------
// checkMoveAndSetSituation()
//
//-----------------------------------------------------------------------------
bool PerfectAI::checkMoveAndSetSituation()
{
    // locals
    bool aPieceCanBeRemovedFromCurPlayer;
    unsigned int nMillsCurrentPlayer, nMillsOpponentPlayer;
    unsigned int stateNum, layerNum, curMove, i;
    unsigned int *idPossibility;
    unsigned int possibilityCount;
    bool isOpponentLevel;
    void *pPossibilities;
    void *pBackup;
    unsigned int threadNo = 0;
    ThreadVars *tv = &threadVars[threadNo];

    // output
    cout << endl << "checkMoveAndSetSituation()" << endl;

    // test if each successor from getPossibilities() leads to the original
    // state using getPredecessors()
    for (layerNum = 0; layerNum < NUM_LAYERS; layerNum++) {
        // generate random state
        cout << endl << "TESTING LAYER: " << layerNum;
        if (layer[layerNum]
                .subLayer[layer[layerNum].subLayerCount - 1]
                .maxIndex == 0)
            continue;

        // test each state of layer
        for (stateNum = 0;
             stateNum < (layer[layerNum]
                             .subLayer[layer[layerNum].subLayerCount - 1]
                             .maxIndex +
                         1) *
                            MAX_NUM_PIECES_REMOVED_MINUS_1;
             stateNum++) {
            // set situation
            if (stateNum % OUTPUT_EVERY_N_STATES == 0)
                cout << endl
                     << "TESTING STATE " << stateNum << " OF "
                     << (layer[layerNum]
                             .subLayer[layer[layerNum].subLayerCount - 1]
                             .maxIndex +
                         1) *
                            MAX_NUM_PIECES_REMOVED_MINUS_1;
            if (!setSituation(threadNo, layerNum, stateNum))
                continue;

            // get all possible moves
            idPossibility = getPossibilities(threadNo, &possibilityCount,
                                             &isOpponentLevel, &pPossibilities);

            // go to each successor state
            for (curMove = 0; curMove < possibilityCount; curMove++) {
                // move
                move(threadNo, idPossibility[curMove], isOpponentLevel,
                     &pBackup, pPossibilities);

                // count completed mills
                nMillsCurrentPlayer = 0;
                nMillsOpponentPlayer = 0;

                for (i = 0; i < SQUARE_NB; i++) {
                    if (tv->field->board[i] == tv->field->curPlayer->id)
                        nMillsCurrentPlayer += tv->field->piecePartOfMill[i];
                    else
                        nMillsOpponentPlayer += tv->field->piecePartOfMill[i];
                }

                nMillsCurrentPlayer /= 3;
                nMillsOpponentPlayer /= 3;

                // precalc aPieceCanBeRemovedFromCurPlayer
                for (aPieceCanBeRemovedFromCurPlayer = false, i = 0;
                     i < SQUARE_NB; i++) {
                    if (tv->field->piecePartOfMill[i] == 0 &&
                        tv->field->board[i] == tv->field->curPlayer->id) {
                        aPieceCanBeRemovedFromCurPlayer = true;
                        break;
                    }
                }

                //
                if (tv->fieldIntegrityOK(
                        nMillsCurrentPlayer, nMillsOpponentPlayer,
                        aPieceCanBeRemovedFromCurPlayer) == false) {
                    cout << endl
                         << "ERROR: STATE " << stateNum
                         << " REACHED WITH move(), BUT IS INVALID!";
                    // return false;
                }

                // undo move
                undo(threadNo, idPossibility[curMove], isOpponentLevel, pBackup,
                     pPossibilities);
            }
        }
        cout << endl << "LAYER OK: " << layerNum << endl;
    }

    // free mem
    return true;
}

//-----------------------------------------------------------------------------
// checkGetPossThanGetPred()
//
//-----------------------------------------------------------------------------
bool PerfectAI::checkGetPossThanGetPred()
{
    // locals
    unsigned int stateNum, layerNum, i, j;
    unsigned int *idPossibility;
    unsigned int possibilityCount;
    unsigned int amountOfPred;
    bool isOpponentLevel;
    void *pPossibilities;
    void *pBackup;
    RetroAnalysisPredVars predVars[PREDECESSOR_COUNT_MAX];
    unsigned int threadNo = 0;
    // ThreadVars *tv = &threadVars[threadNo];

    // test if each successor from getPossibilities() leads to the original
    // state using getPredecessors()
    for (layerNum = 0; layerNum < NUM_LAYERS; layerNum++) {
        // generate random state
        cout << endl << "TESTING LAYER: " << layerNum;
        if (layer[layerNum]
                .subLayer[layer[layerNum].subLayerCount - 1]
                .maxIndex == 0)
            continue;

        // test each state of layer
        for (stateNum = 0;
             stateNum < (layer[layerNum]
                             .subLayer[layer[layerNum].subLayerCount - 1]
                             .maxIndex +
                         1) *
                            MAX_NUM_PIECES_REMOVED_MINUS_1;
             stateNum++) {
            // set situation
            if (stateNum % 10000 == 0)
                cout << endl
                     << "TESTING STATE " << stateNum << " OF "
                     << (layer[layerNum]
                             .subLayer[layer[layerNum].subLayerCount - 1]
                             .maxIndex +
                         1) *
                            MAX_NUM_PIECES_REMOVED_MINUS_1;
            if (!setSituation(threadNo, layerNum, stateNum))
                continue;

            // get all possible moves
            idPossibility = getPossibilities(threadNo, &possibilityCount,
                                             &isOpponentLevel, &pPossibilities);

            // go to each successor state
            for (i = 0; i < possibilityCount; i++) {
                // move
                move(threadNo, idPossibility[i], isOpponentLevel, &pBackup,
                     pPossibilities);

                // get predecessors1
                getPredecessors(threadNo, &amountOfPred, predVars);

                // does it match ?
                for (j = 0; j < amountOfPred; j++) {
                    if (predVars[j].predStateNumbers == stateNum &&
                        predVars[j].predLayerNumbers == layerNum)
                        break;
                }

                // error?
                if (j == amountOfPred) {
                    cout << endl
                         << "ERROR: STATE " << stateNum
                         << " NOT FOUND IN PREDECESSOR LIST";
                    return false;

#if 0
                    // perform several commands to see in debug mode where the error occurs
                    undo(threadNo, idPossibility[i], isOpponentLevel, pBackup, pPossibilities);
                    setSituation(threadNo, layerNum, stateNum);
                    cout << "current state" << endl;
                    cout << "   layerNum: " << layerNum << "\tstateNum: " << stateNum << endl;
                    printBoard(threadNo, 0);
                    move(threadNo, idPossibility[i], isOpponentLevel, &pBackup, pPossibilities);
                    cout << "successor" << endl;
                    printBoard(threadNo, 0);
                    getPredecessors(threadNo, &amountOfPred, predVars);
                    getPredecessors(threadNo, &amountOfPred, predVars);
#endif
                }

                // undo move
                undo(threadNo, idPossibility[i], isOpponentLevel, pBackup,
                     pPossibilities);
            }
        }
        cout << endl << "LAYER OK: " << layerNum << endl;
    }

    // everything fine
    return true;
}

//-----------------------------------------------------------------------------
// checkGetPredThanGetPoss()
//
//-----------------------------------------------------------------------------
bool PerfectAI::checkGetPredThanGetPoss()
{
    // locals
    unsigned int threadNo = 0;
    ThreadVars *tv = &threadVars[threadNo];
    unsigned int stateNum, layerNum, i, j, k;
    unsigned int stateNumB, layerNumB;
    unsigned int *idPossibility;
    unsigned int possibilityCount;
    unsigned int amountOfPred;
    bool isOpponentLevel;
    void *pPossibilities;
    void *pBackup;
    int symField[SQUARE_NB];
    RetroAnalysisPredVars predVars[PREDECESSOR_COUNT_MAX];

    // test if each predecessor from getPredecessors() leads to the original
    // state using getPossibilities()
    for (layerNum = 0; layerNum < NUM_LAYERS; layerNum++) {
        // generate random state
        cout << endl << "TESTING LAYER: " << layerNum;
        if (layer[layerNum]
                .subLayer[layer[layerNum].subLayerCount - 1]
                .maxIndex == 0)
            continue;

        // test each state of layer
        for (stateNum = 0;
             stateNum < (layer[layerNum]
                             .subLayer[layer[layerNum].subLayerCount - 1]
                             .maxIndex +
                         1) *
                            MAX_NUM_PIECES_REMOVED_MINUS_1;
             stateNum++) {
            // set situation
            if (stateNum % 10000000 == 0)
                cout << endl
                     << "TESTING STATE " << stateNum << " OF "
                     << (layer[layerNum]
                             .subLayer[layer[layerNum].subLayerCount - 1]
                             .maxIndex +
                         1) *
                            MAX_NUM_PIECES_REMOVED_MINUS_1;
            if (!setSituation(threadNo, layerNum, stateNum))
                continue;

            // get predecessors
            getPredecessors(threadNo, &amountOfPred, predVars);

            // test each returned predecessor
            for (j = 0; j < amountOfPred; j++) {
                // set situation
                if (!setSituation(threadNo, predVars[j].predLayerNumbers,
                                  predVars[j].predStateNumbers)) {
                    cout << endl << "ERROR PLACING SITUATION";
                    return false;

#if 0
                    // perform several commands to see in debug mode where the
                    // error occurs
                    for (k = 0; k < SQUARE_NB; k++)
                        symField[k] = tv->field->board[k];

                    applySymmetryOperationOnField(
                        reverseSymOperation[predVars[j].predSymOperation],
                        (unsigned int*)symField,
                        (unsigned int*)tv->field->board);

                    for (k = 0; k < SQUARE_NB; k++)
                        symField[k] = tv->field->piecePartOfMill[k];

                    applySymmetryOperationOnField(
                        reverseSymOperation[predVars[j].predSymOperation],
                        (unsigned int*)symField,
                        (unsigned int*)tv->field->piecePartOfMill);
                    cout << "predecessor" << endl;
                    cout << "   layerNum: " << predVars[j].predLayerNumbers
                         << "\tstateNum: " << predVars[j].predStateNumbers
                         << endl;
                    printBoard(threadNo, 0);

                    if (predVars[j].playerToMoveChanged) {
                        k = tv->field->curPlayer->id;
                        tv->field->curPlayer->id = tv->field->oppPlayer->id;
                        tv->field->oppPlayer->id = k;
                        for (k = 0; k < SQUARE_NB; k++)
                            tv->field->board[k] = -1 * tv->field->board[k];
                    }

                    idPossibility = getPossibilities(threadNo,
                        &possibilityCount, &isOpponentLevel, &pPossibilities);
                    setSituation(threadNo, layerNum, stateNum);
                    cout << "current state" << endl;
                    cout << "   layerNum: " << layerNum
                         << "\tstateNum: " << stateNum << endl;
                    printBoard(threadNo, 0);
                    getPredecessors(threadNo, &amountOfPred, predVars);
#endif
                }

                // regard used symmetry operation
                for (k = 0; k < SQUARE_NB; k++)
                    symField[k] = tv->field->board[k];

                applySymmetryOperationOnField(
                    reverseSymOperation[predVars[j].predSymOperation],
                    (unsigned int *)symField, (unsigned int *)tv->field->board);

                for (k = 0; k < SQUARE_NB; k++)
                    symField[k] = tv->field->piecePartOfMill[k];

                applySymmetryOperationOnField(
                    reverseSymOperation[predVars[j].predSymOperation],
                    (unsigned int *)symField,
                    (unsigned int *)tv->field->piecePartOfMill);

                if (predVars[j].playerToMoveChanged) {
                    k = tv->field->curPlayer->id;
                    tv->field->curPlayer->id = tv->field->oppPlayer->id;
                    tv->field->oppPlayer->id = k;
                    for (k = 0; k < SQUARE_NB; k++)
                        tv->field->board[k] = -1 * tv->field->board[k];
                }

                // get all possible moves
                idPossibility = getPossibilities(threadNo, &possibilityCount,
                                                 &isOpponentLevel,
                                                 &pPossibilities);

                // go to each successor state
                for (i = 0; i < possibilityCount; i++) {
                    // move
                    move(threadNo, idPossibility[i], isOpponentLevel, &pBackup,
                         pPossibilities);

                    // get numbers
                    getLayerAndStateNumber(threadNo, layerNumB, stateNumB);

                    // does states match ?
                    if (stateNum == stateNumB && layerNum == layerNumB)
                        break;

                    // undo move
                    undo(threadNo, idPossibility[i], isOpponentLevel, pBackup,
                         pPossibilities);
                }

                // error?
                if (i == possibilityCount) {
                    cout << endl
                         << "ERROR: Not all predecessors lead to state "
                         << stateNum << " calling move()" << endl;
                    // return false;

                    // perform several commands to see in debug mode where the
                    // error occurs
                    setSituation(threadNo, predVars[j].predLayerNumbers,
                                 predVars[j].predStateNumbers);

                    for (k = 0; k < SQUARE_NB; k++)
                        symField[k] = tv->field->board[k];

                    applySymmetryOperationOnField(
                        reverseSymOperation[predVars[j].predSymOperation],
                        (unsigned int *)symField,
                        (unsigned int *)tv->field->board);

                    for (k = 0; k < SQUARE_NB; k++)
                        symField[k] = tv->field->piecePartOfMill[k];

                    applySymmetryOperationOnField(
                        reverseSymOperation[predVars[j].predSymOperation],
                        (unsigned int *)symField,
                        (unsigned int *)tv->field->piecePartOfMill);

                    cout << "predecessor" << endl;
                    cout << "   layerNum: " << predVars[j].predLayerNumbers
                         << "\tstateNum: " << predVars[j].predStateNumbers
                         << endl;

                    printBoard(threadNo, 0);

                    if (predVars[j].playerToMoveChanged) {
                        k = tv->field->curPlayer->id;
                        tv->field->curPlayer->id = tv->field->oppPlayer->id;
                        tv->field->oppPlayer->id = k;
                        for (k = 0; k < SQUARE_NB; k++)
                            tv->field->board[k] = -1 * tv->field->board[k];
                    }

                    idPossibility = getPossibilities(threadNo,
                                                     &possibilityCount,
                                                     &isOpponentLevel,
                                                     &pPossibilities);
                    setSituation(threadNo, layerNum, stateNum);
                    cout << "current state" << endl;
                    cout << "   layerNum: " << layerNum
                         << "\tstateNum: " << stateNum << endl;
                    printBoard(threadNo, 0);
                    getPredecessors(threadNo, &amountOfPred, predVars);

                    k = tv->field->curPlayer->id;
                    tv->field->curPlayer->id = tv->field->oppPlayer->id;
                    tv->field->oppPlayer->id = k;

                    for (k = 0; k < SQUARE_NB; k++)
                        tv->field->board[k] = -1 * tv->field->board[k];

                    setSituation(threadNo, predVars[j].predLayerNumbers,
                                 predVars[j].predStateNumbers);

                    for (k = 0; k < SQUARE_NB; k++)
                        symField[k] = tv->field->board[k];

                    applySymmetryOperationOnField(
                        reverseSymOperation[predVars[j].predSymOperation],
                        (unsigned int *)symField,
                        (unsigned int *)tv->field->board);

                    for (k = 0; k < SQUARE_NB; k++)
                        symField[k] = tv->field->piecePartOfMill[k];

                    applySymmetryOperationOnField(
                        reverseSymOperation[predVars[j].predSymOperation],
                        (unsigned int *)symField,
                        (unsigned int *)tv->field->piecePartOfMill);

                    printBoard(threadNo, 0);
                    idPossibility = getPossibilities(threadNo,
                                                     &possibilityCount,
                                                     &isOpponentLevel,
                                                     &pPossibilities);
                    move(threadNo, idPossibility[1], isOpponentLevel, &pBackup,
                         pPossibilities);
                    printBoard(threadNo, 0);
                    getLayerAndStateNumber(threadNo, layerNumB, stateNumB);
                }
            }
        }
        cout << endl << "LAYER OK: " << layerNum << endl;
    }

    // free mem
    return true;
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
