#include <iostream>
#include <stdexcept>
#include <string>

class MalomSolutionAccess
{
private:
    static PerfectPlayer *pp;
    static std::exception lastError;

public:
    static int GetBestMove(int whiteBitboard, int blackBitboard,
                           int whiteStonesToPlace, int blackStonesToPlace,
                           int playerToMove, bool onlyStoneTaking)
    {
        InitializeIfNeeded();

        GameState s;

        const int W = 0;
        const int B = 1;

        if ((whiteBitboard & blackBitboard) != 0)
            throw std::invalid_argument("whiteBitboard and blackBitboard "
                                        "shouldn't have any overlap");

        for (int i = 0; i < 24; i++) {
            if ((whiteBitboard & (1 << i)) != 0) {
                s.T[i] = W;
                s.StoneCount[W]++;
            }
            if ((blackBitboard & (1 << i)) != 0) {
                s.T[i] = B;
                s.StoneCount[B]++;
            }
        }

        s.phase = (whiteStonesToPlace == 0 && blackStonesToPlace == 0) ? 2 : 1;
        MustBeBetween("whiteStonesToPlace", whiteStonesToPlace, 0,
                      Rules.MaxKSZ);
        MustBeBetween("blackStonesToPlace", blackStonesToPlace, 0,
                      Rules.MaxKSZ);
        s.SetStoneCount[W] = Rules.MaxKSZ - whiteStonesToPlace;
        s.SetStoneCount[B] = Rules.MaxKSZ - blackStonesToPlace;
        s.KLE = onlyStoneTaking;
        MustBeBetween("playerToMove", playerToMove, 0, 1);
        s.SideToMove = playerToMove;
        s.MoveCount = 10;

        // Check future stone count
        // ...
        // Set over and check valid setup
        // ...

        s.LastIrrev = 0;

        try {
            return pp->ChooseRandom(pp->GoodMoves(s)).ToBitBoard();
        } catch (const std::out_of_range &e) {
            throw std::runtime_error("We don't have a database entry for this "
                                     "position. This can happen either if the "
                                     "database is corrupted (missing files), "
                                     "or sometimes when the position is not "
                                     "reachable from the starting position.");
        }
    }

    static int GetBestMoveNoException(int whiteBitboard, int blackBitboard,
                                      int whiteStonesToPlace,
                                      int blackStonesToPlace, int playerToMove,
                                      bool onlyStoneTaking)
    {
        try {
            return GetBestMove(whiteBitboard, blackBitboard, whiteStonesToPlace,
                               blackStonesToPlace, playerToMove,
                               onlyStoneTaking);
        } catch (const std::exception &e) {
            lastError = e;
            return 0;
        }
    }

    static std::string GetLastError()
    {
        if (lastError == nullptr)
            return "No error";
        return lastError.what();
    }

    // Remaining methods go here
};

PerfectPlayer *MalomSolutionAccess::pp = nullptr;
std::exception MalomSolutionAccess::lastError;
