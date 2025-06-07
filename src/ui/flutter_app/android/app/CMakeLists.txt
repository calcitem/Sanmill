# For more information about using CMake with Android Studio, read the
# documentation: https://d.android.com/studio/projects/add-native-code.html

# Sets the minimum version of CMake required to build the native library.
cmake_minimum_required(VERSION 3.22.1)
cmake_policy(SET CMP0069 NEW)

project(sanmill LANGUAGES CXX)

# Get the build mode from environment variables
if (CMAKE_BUILD_TYPE STREQUAL "Debug")
    # Debug mode: use -O0 -g, remove -flto
    add_definitions(-DDEBUG -O0 -g -fno-omit-frame-pointer -funwind-tables -std=c++17 -D FLUTTER_UI)
elseif (DEFINED ENV{DEV_MODE} AND "$ENV{DEV_MODE}" STREQUAL "true")
    # Dev mode: add Address Sanitizer
    add_definitions(-DDEBUG -O0 -g -fno-omit-frame-pointer -funwind-tables -std=c++17 -D FLUTTER_UI)
    set(USE_ASAN TRUE)
else ()
    # Release mode: use original optimization flags
    add_definitions(-DNDEBUG -O3 -std=c++17 -flto -D FLUTTER_UI)
endif ()

#add_definitions(-DDISABLE_PERFECT_AI)

set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Werror -Wall -Wcast-qual -pedantic -Wextra -Wshadow -fno-exceptions -DUSE_POPCNT")
#set(CMAKE_CXX_FLAGS_RELEASE "-O3")
set(CMAKE_CXX_FLAGS_DEBUG "-g")

# Enable LTO only for release builds
if (NOT CMAKE_BUILD_TYPE STREQUAL "Debug" AND NOT DEFINED USE_ASAN)
    include(CheckIPOSupported)
    check_ipo_supported(RESULT result)
    if (result)
        set_property(TARGET sanmill PROPERTY INTERPROCEDURAL_OPTIMIZATION TRUE)
        # We usually do this, but only if we REALLY want LTO in release builds
        message(STATUS "IPO is enabled for Release build")
    endif ()
endif ()

add_library( # Sets the name of the library.
        sanmill

        # Sets the library as a shared library.
        SHARED

        # Provides a relative path to your source file(s).
        ../../command/command_channel.cpp
        ../../command/command_queue.cpp
        ../../command/engine_main.cpp
        ../../command/mill_engine.cpp
        ../../../../bitboard.cpp
        ../../../../endgame.cpp
        ../../../../evaluate.cpp
        ../../../../main.cpp
        ../../../../mcts.cpp
        ../../../../mills.cpp
        ../../../../misc.cpp
        ../../../../movegen.cpp
        ../../../../movepick.cpp
        ../../../../option.cpp
        ../../../../position.cpp
        ../../../../rule.cpp
        ../../../../search.cpp
        ../../../../thread.cpp
        ../../../../tt.cpp
        ../../../../uci.cpp
        ../../../../ucioption.cpp
        ../../../../engine_controller.cpp
        ../../../../engine_commands.cpp
        ../../../../search_engine.cpp
        ../../../../thread_pool.cpp
        ../../../../opening_book.cpp
        ../../../../perfect/perfect_adaptor.cpp
        ../../../../perfect/perfect_api.cpp
        ../../../../perfect/perfect_common.cpp
        ../../../../perfect/perfect_debug.cpp
        ../../../../perfect/perfect_errors.cpp
        ../../../../perfect/perfect_eval_elem.cpp
        ../../../../perfect/perfect_game.cpp
        ../../../../perfect/perfect_game_state.cpp
        ../../../../perfect/perfect_hash.cpp
        ../../../../perfect/perfect_log.cpp
        ../../../../perfect/perfect_move.cpp
        ../../../../perfect/perfect_player.cpp
        ../../../../perfect/perfect_rules.cpp
        ../../../../perfect/perfect_sec_val.cpp
        ../../../../perfect/perfect_sector.cpp
        ../../../../perfect/perfect_sector_graph.cpp
        ../../../../perfect/perfect_symmetries.cpp
        ../../../../perfect/perfect_symmetries_slow.cpp
        ../../../../perfect/perfect_wrappers.cpp)

# Configure Address Sanitizer for dev mode
if (DEFINED USE_ASAN AND USE_ASAN)
    target_compile_options(sanmill PUBLIC -fsanitize=address -fno-omit-frame-pointer)
    set_target_properties(sanmill PROPERTIES LINK_FLAGS -fsanitize=address)
endif ()

include_directories(
        ../../command
        ../../../../../include
        ../../../../
        ../../../../perfect
)

find_library( # Sets the name of the path variable.
        log-lib

        # Specifies the name of the NDK library that
        # you want CMake to locate.
        log)

target_link_libraries( # Specifies the target library.
        sanmill

        # Links the target library to the log library
        # included in the NDK.
        ${log-lib})