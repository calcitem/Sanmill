// This file is part of Sanmill.
// Copyright (C) 2019-2022 The Sanmill developers (see AUTHORS file)
//
// Sanmill is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Sanmill is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

#ifndef OPTION_H_INCLUDED
#define OPTION_H_INCLUDED

#include "config.h"

class GameOptions
{
public:
    GameOptions() { }

    void setSkillLevel(int val) noexcept { skillLevel = val; }

    [[nodiscard]] int getSkillLevel() const noexcept { return skillLevel; }

    void setMoveTime(int val) noexcept { moveTime = val; }

    [[nodiscard]] int getMoveTime() const noexcept { return moveTime; }

    void setAiIsLazy(bool enabled) noexcept { aiIsLazy = enabled; }

    [[nodiscard]] bool getAiIsLazy() const noexcept { return aiIsLazy; }

    void setAutoRestart(bool enabled) noexcept { isAutoRestart = enabled; }

    [[nodiscard]] bool getAutoRestart() const noexcept { return isAutoRestart; }

    void setAutoChangeFirstMove(bool enabled) noexcept
    {
        isAutoChangeFirstMove = enabled;
    }

    [[nodiscard]] bool getAutoChangeFirstMove() const noexcept
    {
        return isAutoChangeFirstMove;
    }

    void setResignIfMostLose(bool enabled) noexcept
    {
        resignIfMostLose = enabled;
    }

    [[nodiscard]] bool getResignIfMostLose() const noexcept
    {
        return resignIfMostLose;
    }

    // Specify whether the successors of a given state should be shuffled if a
    // re-evaluation is required so that the AI algorithm is not favoring one
    // state if multiple ones have equal evaluations. This introduces some
    // variation between different games against an opponent that tries to do
    // the same sequence of moves. By default, shuffling is enabled.

    [[nodiscard]] bool getShufflingEnabled() const noexcept
    {
        return shufflingEnabled;
    }

    void setShufflingEnabled(bool enabled) noexcept
    {
        shufflingEnabled = enabled;
    }

    [[nodiscard]] bool getLearnEndgameEnabled() const noexcept
    {
        return learnEndgame;
    }

    void setLearnEndgameEnabled(bool enabled) noexcept
    {
#ifdef ENDGAME_LEARNING_FORCE
        learnEndgame = true;
#else
        learnEndgame = enabled;
#endif
    }

    [[nodiscard]] bool isEndgameLearningEnabled() const noexcept
    {
#ifdef ENDGAME_LEARNING_FORCE
        return true;
#else
        return learnEndgame;
#endif
    }

    void setPerfectAiEnabled(bool enabled) noexcept
    {
        perfectAiEnabled = enabled;
    }

    [[nodiscard]] bool getPerfectAiEnabled() const noexcept
    {
        return perfectAiEnabled;
    }

    void setIDSEnabled(bool enabled) noexcept { IDSEnabled = enabled; }

    [[nodiscard]] bool getIDSEnabled() const noexcept { return IDSEnabled; }

    // DepthExtension

    void setDepthExtension(bool enabled) noexcept { depthExtension = enabled; }

    [[nodiscard]] bool getDepthExtension() const noexcept
    {
        return depthExtension;
    }

    // OpeningBook

    void setOpeningBook(bool enabled) noexcept { openingBook = enabled; }

    [[nodiscard]] bool getOpeningBook() const noexcept { return openingBook; }

    // Algorithm

    void setAlphaBetaAlgorithm(bool enabled) noexcept
    {
        if (enabled) {
            algorithm = 0;
        }
    }

    [[nodiscard]] bool getAlphaBetaAlgorithm() const noexcept
    {
        return algorithm == 0;
    }

    void setPvsAlgorithm(bool enabled) noexcept
    {
        if (enabled) {
            algorithm = 1;
        }
    }

    [[nodiscard]] bool getPvsAlgorithm() const noexcept
    {
        return algorithm == 1;
    }

    void setMtdfAlgorithm(bool enabled) noexcept
    {
        if (enabled) {
            algorithm = 2;
        }
    }

    [[nodiscard]] bool getMtdfAlgorithm() const noexcept
    {
        return algorithm == 2;
    }

    void setAlgorithm(int val) noexcept
    {
        algorithm = val;

#if 0
        switch (val) {
        case 0:
            setAlphaBetaAlgorithm(true);
            setPvsAlgorithm(false);
            setMtdfAlgorithm(false);
            setPerfectAiEnabled(false);
            break;
        case 1:
            setAlphaBetaAlgorithm(false);
            setPvsAlgorithm(true);
            setMtdfAlgorithm(false);
            setPerfectAiEnabled(false);
            break;
        case 2:
            setAlphaBetaAlgorithm(false);
            setPvsAlgorithm(false);
            setMtdfAlgorithm(true);
            setPerfectAiEnabled(false);
            break;
        default:
            setAlphaBetaAlgorithm(false);
            setPvsAlgorithm(false);
            setMtdfAlgorithm(false);
            setPerfectAiEnabled(true);
            break;
        }
#endif
    }

    [[nodiscard]] int getAlgorithm() const noexcept { return algorithm; }

    // DrawOnHumanExperience

    void setDrawOnHumanExperience(bool enabled) noexcept
    {
        drawOnHumanExperience = enabled;
    }

    [[nodiscard]] bool getDrawOnHumanExperience() const noexcept
    {
        return drawOnHumanExperience;
    }

    // ConsiderMobility

    void setConsiderMobility(bool enabled) noexcept
    {
        considerMobility = enabled;
    }

    [[nodiscard]] bool getConsiderMobility() const noexcept
    {
        return considerMobility;
    }

    // Developer Mode

    void setDeveloperMode(bool enabled) noexcept { developerMode = enabled; }

    [[nodiscard]] bool getDeveloperMode() const noexcept
    {
        return developerMode;
    }

private:
    int skillLevel {1};
    int moveTime {1};
    bool aiIsLazy {false};
    bool isAutoRestart {false};
    bool isAutoChangeFirstMove {false};
    bool resignIfMostLose {false};
    bool shufflingEnabled {true};
#ifdef ENDGAME_LEARNING_FORCE
    bool learnEndgame {true};
#else
    bool learnEndgame {false};
#endif
    int algorithm {2};
    bool perfectAiEnabled {false};
    bool IDSEnabled {false};
    bool depthExtension {true};
    bool openingBook {false};
    bool drawOnHumanExperience {true};
    bool considerMobility {true};
    bool developerMode {false};
};

extern GameOptions gameOptions;

#endif /* OPTION_H_INCLUDED */
