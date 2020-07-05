/*
  Sanmill, a mill game playing engine derived from NineChess 1.5
  Copyright (C) 2015-2018 liuweilhy (NineChess author)
  Copyright (C) 2019-2020 Calcitem <calcitem@outlook.com>

  Sanmill is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  Sanmill is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

#ifndef POSITION_H
#define POSITION_H

#include <cassert>
#include <deque>
#include <memory> // For std::unique_ptr
#include <string>
#include <cstring>

#include "config.h"
#include "types.h"
#include "rule.h"
#include "board.h"
#include "search.h"

using namespace std;

class AIAlgorithm;
class Node;

extern string tips;

/// StateInfo struct stores information needed to restore a Position object to
/// its previous state when we retract a move. Whenever a move is made on the
/// board (by calling Position::do_move), a StateInfo object must be passed.

struct StateInfo
{

    // Copied when making a move
    int    rule50;
    int    pliesFromNull;

    // Not copied when making a move (will be recomputed anyhow)
    Key        key;
    Piece      capturedPiece;
    StateInfo *previous;
    int        repetition;
};

/// A list to keep track of the position states along the setup moves (from the
/// start position to the position just before the search starts). Needed by
/// 'draw by repetition' detection. Use a std::deque because pointers to
/// elements are not invalidated upon list resizing.
typedef std::unique_ptr<std::deque<StateInfo>> StateListPtr;

class Position
{
public:
    Position();
    virtual ~Position();

    Position(const Position &) = delete;
    Position &operator=(const Position &) = delete;

    // Properties of moves
    bool select_piece(Square s);
    bool place_piece(Square s, bool updateCmdlist = false);
    bool remove_piece(Square s, bool updateCmdlist = false);

    bool _selectPiece(File file, Rank rank);
    bool _placePiece(File file, Rank rank);
    bool _removePiece(File file, Rank rank);

    // Doing and undoing moves
    bool do_move(Move m);
    bool do_null_move();
    bool undo_null_move();

    // Accessing hash keys
    Key key();
    Key revertKey(Square square);
    Key updateKey(Square square);
    Key updateKeyMisc();
    Key getNextPrimaryKey(Move m);

    Board board;

    // Other properties of the position

    enum Phase phase {PHASE_NONE};

    Color sideToMove {NOCOLOR};
    Color them { NOCOLOR };

    enum Action action { };

    // Note: [0] is sum of Black and White
    int nPiecesInHand[COLOR_NB]{0};
    int nPiecesOnBoard[COLOR_NB] {0};
    int nPiecesNeedRemove {0};

    //////////////////////////////////////

    bool setPosition(const struct Rule *rule);

    Piece *getBoardLocations() const
    {
        return (Piece *)board.locations;
    }

    Square getCurrentSquare() const
    {
        return currentSquare;
    }

    int getStep() const
    {
        return currentStep;
    }

    enum Phase getPhase() const
    {
        return phase;
    }

    enum Action getAction() const
    {
        return action;
    }

    time_t getElapsedTime(int us);

    const string getTips() const
    {
        return tips;
    }

    const char *getCmdLine() const
    {
        return cmdline;
    }

    const vector<string> *getCmdList() const
    {
        return &cmdlist;
    }

    time_t getStartTimeb() const
    {
        return startTime;
    }

    void setStartTime(int stimeb)
    {
        startTime = stimeb;
    }

    int getPiecesInHandCount(Color c) const
    {
        return nPiecesInHand[c];
    }

    int getPiecesOnBoardCount(Color c) const
    {
        return nPiecesOnBoard[c];
    }

    int getMobilityDiff(Color turn, int nPiecesOnBoard[], bool includeFobidden);

    bool reset();

    bool start();

    bool giveup(Color loser);

    bool command(const char *cmd);

    int update();

    bool checkGameOverCondition(int8_t cp = 0);

    void cleanBannedLocations();

    void setSideToMove(Color c);

    Color getSideToMove();

    void changeSideToMove();

    void setTips();

    Color getWinner() const;

    int score[COLOR_NB] = { 0 };
    int score_draw { 0 };
    int nPlayed { 0 };

    int tm { -1 };

    vector <string> cmdlist;

    // 着法命令行用于棋谱的显示和解析, 当前着法的命令行指令，即一招棋谱
    char cmdline[64]{ '\0' };

    /*
        0x   00    00
            square1  square2
        Placing：0x00??，?? is place location
        Moving：0x__??，__ is from，?? is to
        Removing：0xFF??，?? is neg

        31 ----- 24 ----- 25
        | \       |      / |
        |  23 -- 16 -- 17  |
        |  | \    |   / |  |
        |  |  15 08 09  |  |
        30-22-14    10-18-26
        |  |  13 12 11  |  |
        |  | /    |   \ |  |
        |  21 -- 20 -- 19  |
        | /       |     \  |
        29 ----- 28 ----- 27
    */
    Move move { MOVE_NONE };

    Square currentSquare{};

private:

    void constructKey();

    int countPiecesOnBoard();

    int countPiecesInHand();

    inline static char colorToCh(Color color)
    {
        return static_cast<char>('0' + color);
    }

    inline static std::string chToStr(char ch)
    {
        if (ch == '1') {
            return "1";
        } else {
            return "2";
        }
    }

    Color winner;

    Step currentStep {};

    int moveStep {};

    time_t startTime {};

    time_t currentTime {};

    time_t elapsedSeconds[COLOR_NB];

    StateInfo st;
};

#endif /* POSITION_H */
