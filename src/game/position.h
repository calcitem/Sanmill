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

#include <string>
#include <cstring>

#include "config.h"
#include "types.h"
#include "rule.h"
#include "board.h"
#include "search.h"

using namespace std;

class AIAlgorithm;
class StateInfo;
class Node;

extern string tips;

class Position
{
public:
    Position();
    virtual ~Position();

    Position(const Position &) = delete;
    Position &operator=(const Position &) = delete;

    Board board;

    Key key {0};

    enum Phase phase {PHASE_NONE};

    player_t sideToMove {PLAYER_NOBODY};
    int sideId {0};
    char chSide {'0'};
    //string turnStr;
    player_t opponent {PLAYER_NOBODY};
    int opponentId {0};
    char chOpponent {'0'};
    //string opponentStr;

    enum Action action { };

    // Note: [0] is sum of Black and White
    int nPiecesInHand[COLOR_NB]{0};
    int nPiecesOnBoard[COLOR_NB] {0};
    int nPiecesNeedRemove {0};

    //////////////////////////////////////

    bool setPosition(const struct Rule *rule);

    Location *getBoardLocations() const
    {
        return (Location *)board.locations;
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

    time_t getElapsedTime(int playerId);

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

    int getPiecesInHandCount(int playerId) const
    {
        return nPiecesInHand[playerId];
    }

    int getPiecesOnBoardCount(int playerId) const
    {
        return nPiecesOnBoard[playerId];
    }

    int getNum_NeedRemove() const
    {
        return nPiecesNeedRemove;
    }

    int getMobilityDiff(player_t turn, int nPiecesOnBoard[], bool includeFobidden);

    bool reset();

    bool start();

    bool giveup(player_t loser);

    bool command(const char *cmd);

    int update();

    bool checkGameOverCondition(int8_t cp = 0);

    void cleanBannedLocations();

    void setSideToMove(player_t player);

    player_t getSideToMove();

    void changeSideToMove();

    void setTips();

    bool doNullMove();
    bool undoNullMove();

    player_t getWinner() const;

    bool selectPiece(File file, Rank rank);
    bool _placePiece(File file, Rank rank);
    bool _removePiece(File file, Rank rank);

    bool doMove(Move move);
    bool selectPiece(Square square);
    bool placePiece(Square square, bool updateCmdlist = false);
    bool removePiece(Square square, bool updateCmdlist = false);

    Key getPosKey();
    Key revertKey(Square square);
    Key updateKey(Square square);
    Key updateKeyMisc();
    Key getNextPrimaryKey(Move m);

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

    player_t winner;

    Step currentStep {};

    int moveStep {};

    time_t startTime {};

    time_t currentTime {};

    time_t elapsedSeconds[COLOR_NB];
};

class StateInfo
{
    friend class AIAlgorithm;

public:

    StateInfo();
    virtual ~StateInfo();

    StateInfo(StateInfo &);
    StateInfo(const StateInfo &);

    StateInfo &operator=(const StateInfo &);
    StateInfo &operator=(StateInfo &);

    Position *position { nullptr };
};

#endif /* POSITION_H */
