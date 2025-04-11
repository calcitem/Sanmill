// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// option.h

#ifndef OPTION_H_INCLUDED
#define OPTION_H_INCLUDED

#include "config.h"

#include <string>

class GameOptions
{
public:
    GameOptions() { }

    void setSkillLevel(int val) noexcept { skillLevel = val; }

    int getSkillLevel() const noexcept { return skillLevel; }

    void setMoveTime(int val) noexcept { moveTime = val; }

    int getMoveTime() const noexcept { return moveTime; }

    void setAiIsLazy(bool enabled) noexcept { aiIsLazy = enabled; }

    bool getAiIsLazy() const noexcept { return aiIsLazy; }

    void setAutoRestart(bool enabled) noexcept { isAutoRestart = enabled; }

    bool getAutoRestart() const noexcept { return isAutoRestart; }

    void setAutoChangeFirstMove(bool enabled) noexcept
    {
        isAutoChangeFirstMove = enabled;
    }

    bool getAutoChangeFirstMove() const noexcept
    {
        return isAutoChangeFirstMove;
    }

    void setResignIfMostLose(bool enabled) noexcept
    {
        resignIfMostLose = enabled;
    }

    bool getResignIfMostLose() const noexcept { return resignIfMostLose; }

    // Specify whether the successors of a given state should be shuffled if a
    // re-evaluation is required so that the AI algorithm is not favoring one
    // state if multiple ones have equal evaluations. This introduces some
    // variation between different games against an opponent that tries to do
    // the same sequence of moves. By default, shuffling is enabled.

    bool getShufflingEnabled() const noexcept { return shufflingEnabled; }

    void setShufflingEnabled(bool enabled) noexcept
    {
        shufflingEnabled = enabled;
    }

    bool getLearnEndgameEnabled() const noexcept { return learnEndgame; }

    void setLearnEndgameEnabled(bool enabled) noexcept
    {
#ifdef ENDGAME_LEARNING_FORCE
        learnEndgame = true;
#else
        learnEndgame = enabled;
#endif
    }

    bool isEndgameLearningEnabled() const noexcept
    {
#ifdef ENDGAME_LEARNING_FORCE
        return true;
#else
        return learnEndgame;
#endif
    }

    void setIDSEnabled(bool enabled) noexcept { IDSEnabled = enabled; }

    bool getIDSEnabled() const noexcept { return IDSEnabled; }

    // DepthExtension

    void setDepthExtension(bool enabled) noexcept { depthExtension = enabled; }

    bool getDepthExtension() const noexcept { return depthExtension; }

    // OpeningBook

    void setOpeningBook(bool enabled) noexcept { openingBook = enabled; }

    bool getOpeningBook() const noexcept { return openingBook; }

    // Algorithm

    void setAlphaBetaAlgorithm(bool enabled) noexcept
    {
        if (enabled) {
            algorithm = 0;
        }
    }

    bool getAlphaBetaAlgorithm() const noexcept { return algorithm == 0; }

    void setPvsAlgorithm(bool enabled) noexcept
    {
        if (enabled) {
            algorithm = 1;
        }
    }

    bool getPvsAlgorithm() const noexcept { return algorithm == 1; }

    void setMtdfAlgorithm(bool enabled) noexcept
    {
        if (enabled) {
            algorithm = 2;
        }
    }

    bool getMtdfAlgorithm() const noexcept { return algorithm == 2; }

    void setMctsAlgorithm(bool enabled) noexcept
    {
        if (enabled) {
            algorithm = 3;
        }
    }

    bool getMctsAlgorithm() const noexcept { return algorithm == 3; }

    void setRandomAlgorithm(bool enabled) noexcept
    {
        if (enabled) {
            algorithm = 4;
        }
    }

    bool getRandomAlgorithm() const noexcept { return algorithm == 4; }

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
            setMctsEnabled(false);
            setRandomEnabled(false);
            break;
        case 1:
            setAlphaBetaAlgorithm(false);
            setPvsAlgorithm(true);
            setMtdfAlgorithm(false);
            setPerfectAiEnabled(false);
            setMctsEnabled(false);
            setRandomEnabled(false);
            break;
        case 2:
            setAlphaBetaAlgorithm(false);
            setPvsAlgorithm(false);
            setMtdfAlgorithm(true);
            setPerfectAiEnabled(false);
            setMctsEnabled(false);
            setRandomEnabled(false);
            break;
        case 3:
            setAlphaBetaAlgorithm(false);
            setPvsAlgorithm(false);
            setMtdfAlgorithm(false);
            setPerfectAiEnabled(false);
            setMctsEnabled(true);
            setRandomEnabled(false);
            break;
        case 4:
            setAlphaBetaAlgorithm(false);
            setPvsAlgorithm(false);
            setMtdfAlgorithm(false);
            setPerfectAiEnabled(false);
            setMctsEnabled(false);
            setRandomEnabled(true);
            break;
        default:
            setAlphaBetaAlgorithm(false);
            setPvsAlgorithm(false);
            setMtdfAlgorithm(false);
            setPerfectAiEnabled(true);
            setMctsEnabled(false);
            setRandomEnabled(false);
            break;
        }
#endif
    }

    int getAlgorithm() const noexcept { return algorithm; }

    // Perfect Database

    void setUsePerfectDatabase(bool enabled) noexcept
    {
        usePerfectDatabase = enabled;
    }

    bool getUsePerfectDatabase() const noexcept { return usePerfectDatabase; }

    void setPerfectDatabasePath(std::string val) noexcept
    {
        perfectDatabasePath = val;
    }

    std::string getPerfectDatabasePath() const noexcept
    {
        return perfectDatabasePath;
    }

    // DrawOnHumanExperience

    void setDrawOnHumanExperience(bool enabled) noexcept
    {
        drawOnHumanExperience = enabled;
    }

    bool getDrawOnHumanExperience() const noexcept
    {
        return drawOnHumanExperience;
    }

    // ConsiderMobility

    void setConsiderMobility(bool enabled) noexcept
    {
        considerMobility = enabled;
    }

    bool getConsiderMobility() const noexcept { return considerMobility; }

    // focusOnBlockingPaths

    void setFocusOnBlockingPaths(bool enabled) noexcept
    {
        focusOnBlockingPaths = enabled;
    }

    bool getFocusOnBlockingPaths() const noexcept
    {
        return focusOnBlockingPaths;
    }

    // Developer Mode

    void setDeveloperMode(bool enabled) noexcept { developerMode = enabled; }

    bool getDeveloperMode() const noexcept { return developerMode; }

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
    bool usePerfectDatabase {false};
    bool IDSEnabled {false};
    bool depthExtension {true};
    bool openingBook {false};
    bool drawOnHumanExperience {true};
    bool considerMobility {true};
    bool focusOnBlockingPaths {false};
    bool developerMode {false};

    // TODO: Set this to the correct path
#ifdef _DEBUG
    std::string perfectDatabasePath {"E:\\Malom\\Malom_Standard_Ultra-strong_1."
                                     "1.0\\Std_DD_89adjusted"};
#else
    std::string perfectDatabasePath {"."};
#endif
};

extern GameOptions gameOptions;

#endif /* OPTION_H_INCLUDED */
