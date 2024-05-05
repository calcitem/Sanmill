cmake_minimum_required(VERSION 3.22.1)
cmake_policy(SET CMP0069 NEW)

project(sanmill LANGUAGES CXX)

add_definitions(-DNDEBUG -O3 -std=c++17 -flto -D FLUTTER_UI)
#add_definitions(-DDISABLE_PERFECT_AI)

set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Werror -Wall -Wcast-qual -pedantic -Wextra -Wshadow -fexceptions -DUSE_POPCNT")
#set(CMAKE_CXX_FLAGS_RELEASE "-O3")
set(CMAKE_CXX_FLAGS_DEBUG "-g")

include(CheckIPOSupported)
check_ipo_supported(RESULT result)
if(result)
	set_property(TARGET sanmill PROPERTY INTERPROCEDURAL_OPTIMIZATION TRUE)
endif()

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
        ../../../../perfect/perfect_adaptor.cpp
        ../../../../perfect/perfect_api.cpp
        ../../../../perfect/perfect_common.cpp
        ../../../../perfect/perfect_debug.cpp
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

#target_compile_options(sanmill PUBLIC -fsanitize=hwaddress -fno-omit-frame-pointer)
#set_target_properties(sanmill PROPERTIES LINK_FLAGS -fsanitize=hwaddress)

#target_compile_options(sanmill PUBLIC -fsanitize=address -fno-omit-frame-pointer)
#set_target_properties(sanmill PROPERTIES LINK_FLAGS -fsanitize=address)

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
