cmake_minimum_required(VERSION 3.20)
project(sanmill_tests CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# ---------------------------------------------------------------------------
# Build options
# ---------------------------------------------------------------------------
option(BUILD_TESTS         "Build the gtest unit-test suite"         ON)
option(DISABLE_PERFECT_AI  "Disable Gabor Malom perfect AI module"   OFF)

# ---------------------------------------------------------------------------
# Source root directories
# ---------------------------------------------------------------------------
set(SRC_DIR    "${CMAKE_SOURCE_DIR}/src")
set(TESTS_DIR  "${CMAKE_SOURCE_DIR}/tests")
set(INC_DIR    "${CMAKE_SOURCE_DIR}/include")
set(PERFECT_DIR "${SRC_DIR}/perfect")

# ---------------------------------------------------------------------------
# Platform-specific definitions
# ---------------------------------------------------------------------------
if(WIN32)
    add_definitions(-D_WIN32_WINNT=0x0601)
    add_definitions(-D_CONSOLE)
    # vcpkg provides the CRT linkage; avoid MT/MD mismatch
    set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreadedDLL")
endif()

# Silence MSVC warnings that are verbose but harmless for our usage
if(MSVC)
    add_compile_options(/utf-8 /W3 /wd4267 /wd4244 /wd4100 /wd4189)
    add_definitions(-D_CRT_SECURE_NO_WARNINGS)
else()
    add_compile_options(-Wall -Wextra -Wno-unused-parameter)
endif()

# ---------------------------------------------------------------------------
# Feature flags (mirror include/config.h logic)
# config.h already contains:
#   #ifndef DISABLE_PERFECT_AI
#   #define GABOR_MALOM_PERFECT_AI
# So we only need to define DISABLE_PERFECT_AI when user opts out; we do NOT
# pre-define GABOR_MALOM_PERFECT_AI from CMake to avoid C4005 redefinition.
# ---------------------------------------------------------------------------
if(DISABLE_PERFECT_AI)
    add_definitions(-DDISABLE_PERFECT_AI)
endif()

# ---------------------------------------------------------------------------
# Engine library (all src/*.cpp except main.cpp)
# ---------------------------------------------------------------------------
set(ENGINE_SOURCES
    ${SRC_DIR}/benchmark.cpp
    ${SRC_DIR}/bitboard.cpp
    ${SRC_DIR}/endgame.cpp
    ${SRC_DIR}/engine_commands.cpp
    ${SRC_DIR}/engine_controller.cpp
    ${SRC_DIR}/evaluate.cpp
    ${SRC_DIR}/mcts.cpp
    ${SRC_DIR}/mills.cpp
    ${SRC_DIR}/misc.cpp
    ${SRC_DIR}/movegen.cpp
    ${SRC_DIR}/movepick.cpp
    ${SRC_DIR}/opening_book.cpp
    ${SRC_DIR}/option.cpp
    ${SRC_DIR}/position.cpp
    ${SRC_DIR}/rule.cpp
    ${SRC_DIR}/search.cpp
    ${SRC_DIR}/search_engine.cpp
    ${SRC_DIR}/self_play.cpp
    ${SRC_DIR}/thread.cpp
    ${SRC_DIR}/thread_pool.cpp
    ${SRC_DIR}/tt.cpp
    ${SRC_DIR}/uci.cpp
    ${SRC_DIR}/ucioption.cpp
)

if(NOT DISABLE_PERFECT_AI)
    file(GLOB PERFECT_SOURCES "${PERFECT_DIR}/*.cpp")
    list(APPEND ENGINE_SOURCES ${PERFECT_SOURCES})
endif()

add_library(sanmill_engine STATIC ${ENGINE_SOURCES})
target_include_directories(sanmill_engine PUBLIC
    ${INC_DIR}
    ${SRC_DIR}
    ${PERFECT_DIR}
)

# ---------------------------------------------------------------------------
# Test executable
# ---------------------------------------------------------------------------
if(BUILD_TESTS)
    find_package(GTest CONFIG REQUIRED)

    # Collect all test source files from tests/ (excluding tests/golden/*.cpp
    # which contain a main() and are compiled as a separate tool)
    file(GLOB TEST_SOURCES "${TESTS_DIR}/*.cpp")

    add_executable(test_sanmill ${TEST_SOURCES})
    target_include_directories(test_sanmill PRIVATE
        ${INC_DIR}
        ${SRC_DIR}
        ${PERFECT_DIR}
    )
    target_link_libraries(test_sanmill PRIVATE
        sanmill_engine
        GTest::gtest
        GTest::gtest_main
    )
    if(WIN32)
        # On Windows link against Winsock and other system libs
        target_link_libraries(test_sanmill PRIVATE ws2_32 winmm)
    elseif(UNIX)
        target_link_libraries(test_sanmill PRIVATE pthread)
    endif()

    # Register tests with CTest
    include(GoogleTest)
    gtest_discover_tests(test_sanmill
        WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
        PROPERTIES TIMEOUT 120
    )

    # ---------------------------------------------------------------------------
    # Phase 0 baseline generator (separate binary, not part of the test suite)
    # ---------------------------------------------------------------------------
    add_executable(generate_baselines
        ${TESTS_DIR}/golden/generate_baselines.cpp
    )
    target_include_directories(generate_baselines PRIVATE
        ${INC_DIR}
        ${SRC_DIR}
        ${PERFECT_DIR}
    )
    target_link_libraries(generate_baselines PRIVATE sanmill_engine)
    if(WIN32)
        target_link_libraries(generate_baselines PRIVATE ws2_32 winmm)
    elseif(UNIX)
        target_link_libraries(generate_baselines PRIVATE pthread)
    endif()

endif() # BUILD_TESTS

# ---------------------------------------------------------------------------
# Main sanmill executable
# ---------------------------------------------------------------------------
add_executable(sanmill ${SRC_DIR}/main.cpp)
target_include_directories(sanmill PRIVATE
    ${INC_DIR}
    ${SRC_DIR}
    ${PERFECT_DIR}
)
target_link_libraries(sanmill PRIVATE sanmill_engine)
if(WIN32)
    target_link_libraries(sanmill PRIVATE ws2_32 winmm)
elseif(UNIX)
    target_link_libraries(sanmill PRIVATE pthread)
endif()

# ---------------------------------------------------------------------------
# CTest integration
# ---------------------------------------------------------------------------
enable_testing()

# ---------------------------------------------------------------------------
# Usage instructions
# ---------------------------------------------------------------------------
message(STATUS "")
message(STATUS "=== Sanmill Test Suite (Phase 0 Safety-Net) ===")
message(STATUS "  vcpkg toolchain : ${CMAKE_TOOLCHAIN_FILE}")
message(STATUS "  Build dir       : ${CMAKE_BINARY_DIR}")
message(STATUS "")
message(STATUS "  Build + run tests:")
message(STATUS "    cmake --build . --config Release")
message(STATUS "    ctest -C Release --output-on-failure")
message(STATUS "")
message(STATUS "  Generate FEN baselines (populate tests/golden/mill_games.json):")
message(STATUS "    .\\generate_baselines.exe ..\\tests\\golden\\mill_games.json")
message(STATUS "")
