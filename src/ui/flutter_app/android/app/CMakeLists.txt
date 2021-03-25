cmake_minimum_required(VERSION 3.4.1)

add_definitions(-g -O2 -std=c++17 -D FLUTTER_UI)

add_library( # Sets the name of the library.
        sanmill

        # Sets the library as a shared library.
        SHARED

        # Provides a relative path to your source file(s).
        src/main/cpp/mill_engine.cpp
        ../../command/command_channel.cpp
        ../../command/command_queue.cpp
        ../../command/engine_main.cpp
        ../../../../bitboard.cpp
        ../../../../endgame.cpp
        ../../../../evaluate.cpp
        ../../../../main.cpp
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
        ../../../../ucioption.cpp)

#target_compile_options(sanmill PUBLIC -fsanitize=hwaddress -fno-omit-frame-pointer)
#set_target_properties(sanmill PROPERTIES LINK_FLAGS -fsanitize=hwaddress)

#target_compile_options(sanmill PUBLIC -fsanitize=address -fno-omit-frame-pointer)
#set_target_properties(sanmill PROPERTIES LINK_FLAGS -fsanitize=address)

include_directories(
        ../../command
        ../../../../../include
        ../../../../
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
