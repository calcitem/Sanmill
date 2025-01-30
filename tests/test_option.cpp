// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// test_option.cpp

#include <gtest/gtest.h>
#include "option.h"

namespace {

class OptionTest : public ::testing::Test
{
protected:
    void SetUp() override
    {
        // Reinitialize to defaults by invoking the default constructor
        // and overwriting the global instance.
        gameOptions = GameOptions();
    }
};

TEST_F(OptionTest, DefaultValues)
{
    // Check default constructor values (from the class definition)
    // e.g. skillLevel = 1, moveTime = 1, etc.
    EXPECT_EQ(gameOptions.getSkillLevel(), 1);
    EXPECT_EQ(gameOptions.getMoveTime(), 1);
    EXPECT_FALSE(gameOptions.getAiIsLazy());
    EXPECT_FALSE(gameOptions.getAutoRestart());
    EXPECT_FALSE(gameOptions.getAutoChangeFirstMove());
    EXPECT_FALSE(gameOptions.getResignIfMostLose());

    EXPECT_TRUE(gameOptions.getShufflingEnabled());
    EXPECT_FALSE(gameOptions.getLearnEndgameEnabled());
    EXPECT_FALSE(gameOptions.getIDSEnabled());
    EXPECT_TRUE(gameOptions.getDepthExtension());
    EXPECT_FALSE(gameOptions.getOpeningBook());
    EXPECT_TRUE(gameOptions.getDrawOnHumanExperience());
    EXPECT_TRUE(gameOptions.getConsiderMobility());
    EXPECT_FALSE(gameOptions.getFocusOnBlockingPaths());
    EXPECT_FALSE(gameOptions.getDeveloperMode());

    EXPECT_EQ(gameOptions.getAlgorithm(), 2); // from the default
    EXPECT_FALSE(gameOptions.getUsePerfectDatabase());
    EXPECT_EQ(gameOptions.getPerfectDatabasePath(), std::string("."));
}

TEST_F(OptionTest, SetSkillLevel)
{
    gameOptions.setSkillLevel(5);
    EXPECT_EQ(gameOptions.getSkillLevel(), 5);

    gameOptions.setSkillLevel(2);
    EXPECT_EQ(gameOptions.getSkillLevel(), 2);
}

TEST_F(OptionTest, SetMoveTime)
{
    gameOptions.setMoveTime(1000);
    EXPECT_EQ(gameOptions.getMoveTime(), 1000);

    // Try another value
    gameOptions.setMoveTime(500);
    EXPECT_EQ(gameOptions.getMoveTime(), 500);
}

TEST_F(OptionTest, SetAiIsLazy)
{
    gameOptions.setAiIsLazy(true);
    EXPECT_TRUE(gameOptions.getAiIsLazy());

    gameOptions.setAiIsLazy(false);
    EXPECT_FALSE(gameOptions.getAiIsLazy());
}

TEST_F(OptionTest, SetAutoRestart)
{
    gameOptions.setAutoRestart(true);
    EXPECT_TRUE(gameOptions.getAutoRestart());

    gameOptions.setAutoRestart(false);
    EXPECT_FALSE(gameOptions.getAutoRestart());
}

TEST_F(OptionTest, SetAutoChangeFirstMove)
{
    gameOptions.setAutoChangeFirstMove(true);
    EXPECT_TRUE(gameOptions.getAutoChangeFirstMove());

    gameOptions.setAutoChangeFirstMove(false);
    EXPECT_FALSE(gameOptions.getAutoChangeFirstMove());
}

TEST_F(OptionTest, SetResignIfMostLose)
{
    gameOptions.setResignIfMostLose(true);
    EXPECT_TRUE(gameOptions.getResignIfMostLose());

    gameOptions.setResignIfMostLose(false);
    EXPECT_FALSE(gameOptions.getResignIfMostLose());
}

TEST_F(OptionTest, SetShufflingEnabled)
{
    gameOptions.setShufflingEnabled(false);
    EXPECT_FALSE(gameOptions.getShufflingEnabled());

    gameOptions.setShufflingEnabled(true);
    EXPECT_TRUE(gameOptions.getShufflingEnabled());
}

TEST_F(OptionTest, SetLearnEndgameEnabled)
{
    // Turn on
    gameOptions.setLearnEndgameEnabled(true);
    EXPECT_TRUE(gameOptions.getLearnEndgameEnabled());

    // Turn off
    gameOptions.setLearnEndgameEnabled(false);
    EXPECT_FALSE(gameOptions.getLearnEndgameEnabled());
}

TEST_F(OptionTest, SetIDSEnabled)
{
    gameOptions.setIDSEnabled(true);
    EXPECT_TRUE(gameOptions.getIDSEnabled());

    gameOptions.setIDSEnabled(false);
    EXPECT_FALSE(gameOptions.getIDSEnabled());
}

TEST_F(OptionTest, SetDepthExtension)
{
    gameOptions.setDepthExtension(false);
    EXPECT_FALSE(gameOptions.getDepthExtension());

    gameOptions.setDepthExtension(true);
    EXPECT_TRUE(gameOptions.getDepthExtension());
}

TEST_F(OptionTest, SetOpeningBook)
{
    gameOptions.setOpeningBook(true);
    EXPECT_TRUE(gameOptions.getOpeningBook());

    gameOptions.setOpeningBook(false);
    EXPECT_FALSE(gameOptions.getOpeningBook());
}

TEST_F(OptionTest, SetAlgorithm)
{
    // We expect any integer to be stored as is:
    gameOptions.setAlgorithm(0);
    EXPECT_EQ(gameOptions.getAlgorithm(), 0);

    gameOptions.setAlgorithm(4);
    EXPECT_EQ(gameOptions.getAlgorithm(), 4);

    // A negative or large value might just be stored as is (unless you clamp
    // them)
    gameOptions.setAlgorithm(999);
    EXPECT_EQ(gameOptions.getAlgorithm(), 999);
}

TEST_F(OptionTest, SetUsePerfectDatabase)
{
    gameOptions.setUsePerfectDatabase(true);
    EXPECT_TRUE(gameOptions.getUsePerfectDatabase());

    gameOptions.setUsePerfectDatabase(false);
    EXPECT_FALSE(gameOptions.getUsePerfectDatabase());
}

TEST_F(OptionTest, SetPerfectDatabasePath)
{
    std::string newPath = "/some/absolute/path";
    gameOptions.setPerfectDatabasePath(newPath);
    EXPECT_EQ(gameOptions.getPerfectDatabasePath(), newPath);

    // Another test
    gameOptions.setPerfectDatabasePath("C:\\DBPath\\Db.dat");
    EXPECT_EQ(gameOptions.getPerfectDatabasePath(), "C:\\DBPath\\Db.dat");
}

TEST_F(OptionTest, SetDrawOnHumanExperience)
{
    gameOptions.setDrawOnHumanExperience(false);
    EXPECT_FALSE(gameOptions.getDrawOnHumanExperience());

    gameOptions.setDrawOnHumanExperience(true);
    EXPECT_TRUE(gameOptions.getDrawOnHumanExperience());
}

TEST_F(OptionTest, SetConsiderMobility)
{
    gameOptions.setConsiderMobility(false);
    EXPECT_FALSE(gameOptions.getConsiderMobility());

    gameOptions.setConsiderMobility(true);
    EXPECT_TRUE(gameOptions.getConsiderMobility());
}

TEST_F(OptionTest, SetFocusOnBlockingPaths)
{
    gameOptions.setFocusOnBlockingPaths(true);
    EXPECT_TRUE(gameOptions.getFocusOnBlockingPaths());

    gameOptions.setFocusOnBlockingPaths(false);
    EXPECT_FALSE(gameOptions.getFocusOnBlockingPaths());
}

TEST_F(OptionTest, SetDeveloperMode)
{
    gameOptions.setDeveloperMode(true);
    EXPECT_TRUE(gameOptions.getDeveloperMode());

    gameOptions.setDeveloperMode(false);
    EXPECT_FALSE(gameOptions.getDeveloperMode());
}

} // namespace
