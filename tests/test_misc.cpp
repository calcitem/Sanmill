// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// test_misc.cpp

#include <gtest/gtest.h>
#include <cstdio>
#include <fstream>
#include <string>

#include "misc.h"

namespace {

// A small helper function to read the contents of a file (if it exists).
std::string ReadFile(const std::string &path)
{
    std::ifstream ifs(path, std::ios::in);
    if (!ifs.is_open()) {
        return {};
    }
    std::string content((std::istreambuf_iterator<char>(ifs)),
                        std::istreambuf_iterator<char>());
    return content;
}

TEST(MiscTest, EngineInfoTest)
{
    // We only verify that engine_info returns a non-empty string
    // containing "Sanmill" per the code.
    const std::string info = engine_info(/*to_uci=*/false);
    EXPECT_FALSE(info.empty());
    EXPECT_NE(info.find("Sanmill"), std::string::npos) << "engine_info() "
                                                          "should contain "
                                                          "'Sanmill' in the "
                                                          "returned string.";
}

TEST(MiscTest, EngineInfoUciTest)
{
    // If we call with to_uci=true, we expect it to contain "\nid author".
    const std::string info = engine_info(/*to_uci=*/true);
    EXPECT_FALSE(info.empty());
    EXPECT_NE(info.find("\nid author "), std::string::npos)
        << "engine_info(to_uci=true) should contain 'id author ' in the "
           "returned string.";
}

TEST(MiscTest, CompilerInfoTest)
{
    // Just check that it returns a non-empty string containing the word
    // "Compiled"
    const std::string cinfo = compiler_info();
    EXPECT_FALSE(cinfo.empty());
    EXPECT_NE(cinfo.find("Compiled by"), std::string::npos);
}

TEST(MiscTest, DebugHitOnTest)
{
    // Just call dbg_hit_on in various ways to ensure no crashes
    // We'll also call dbg_print() to print the counters
    // There's no easy way to capture the console output or reset them
    // but we can verify it doesn't crash or throw.

    // We'll do a few increments
    dbg_hit_on(true);        // increments total and hits
    dbg_hit_on(false);       // increments total only
    dbg_hit_on(true, true);  // increments total once, hits once
    dbg_hit_on(true, false); // increments total once, hits not incremented
    // Summarize them (prints to stderr)
    dbg_print();

    // The main goal: no crash. If needed, you could test hits[] and means[]
    // by making them externally accessible or by scanning stderr.
    SUCCEED() << "dbg_hit_on and dbg_print completed without crashing.";
}

TEST(MiscTest, DebugMeanOfTest)
{
    // This tests dbg_mean_of() plus dbg_print().
    dbg_mean_of(10);
    dbg_mean_of(20);
    dbg_mean_of(30);
    dbg_print();

    // Again, no direct checks except no crash.
    SUCCEED() << "dbg_mean_of and dbg_print completed without crashing.";
}

TEST(MiscTest, PrefetchTest)
{
    // We can't verify it does the actual caching, but we can ensure no crash.
    int localVar = 42;
    prefetch(&localVar);
    // Also test prefetch_range
    char buffer[256];
    prefetch_range(buffer, sizeof(buffer));

    // If it doesn't crash, presumably it works under normal conditions.
    SUCCEED() << "prefetch and prefetch_range calls did not crash.";
}

TEST(MiscTest, AlignedAllocTest)
{
    // We'll try to allocate some memory with alignment=64 and size=128
    void *ptr = std_aligned_alloc(64, 128);
    ASSERT_NE(ptr, nullptr) << "std_aligned_alloc should return non-null "
                               "pointer.";

    // Confirm the pointer is aligned.
    // Note: reinterpret_cast<std::uintptr_t>(ptr) % 64 == 0 for correct
    // alignment.
    std::uintptr_t addr = reinterpret_cast<std::uintptr_t>(ptr);
    EXPECT_EQ(addr % 64, 0U) << "Pointer should be 64-byte aligned.";

    // Use the allocated memory just to confirm no obvious error
    std::memset(ptr, 0xAB, 128);

    // Now free it
    std_aligned_free(ptr);
    // If we got here without crashing, success
    SUCCEED() << "Memory allocated and freed successfully.";
}

TEST(MiscTest, StartLoggerTest)
{
    // This test verifies that we can start logging,
    // and that we can produce a file with some basic content.

    // Use a temporary file name
    const std::string logFileName = "test_logger_output.txt";

    // Ensure file doesn't exist initially
    std::remove(logFileName.c_str());

    // Start the logger
    start_logger(logFileName);

    // Now do some I/O that might go to the logger
    std::cout << "Hello logger!" << std::endl;
    std::cin.clear(); // minimal usage

    // Stop the logger by calling start_logger("")
    // as implied by the ~Logger destructor logic
    start_logger("");

    // Now let's see if the file was created and has content
    std::string content = ReadFile(logFileName);
    // Confirm we have something
    EXPECT_NE(content.size(), 0U) << "Logger output file should contain some "
                                     "data.";

    // Optional: check if it has the "Hello logger!" line
    // depending on the prefix or tie logic
    EXPECT_NE(content.find("Hello logger!"), std::string::npos)
        << "Log file should contain 'Hello logger!'";

    // Cleanup
    std::remove(logFileName.c_str());
}

} // namespace
