cmake_minimum_required(VERSION 3.4.1)

add_definitions(-g -O2 -std=c++17 -D FLUTTER_UI)

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
        ../../../../perfect/perfect_adaptor.cpp
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
