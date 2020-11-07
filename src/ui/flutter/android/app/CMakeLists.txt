cmake_minimum_required(VERSION 3.4.1)

add_library( # Sets the name of the library.
        engine

        # Sets the library as a shared library.
        SHARED

        # Provides a relative path to your source file(s).
        src/main/cpp/mill_engine.cpp
        ../../command/command_channel.cpp
        ../../command/command_queue.cpp
        ../../command/engine_main.cpp)


find_library( # Sets the name of the path variable.
        log-lib

        # Specifies the name of the NDK library that
        # you want CMake to locate.
        log)


target_link_libraries( # Specifies the target library.
        engine

        # Links the target library to the log library
        # included in the NDK.
        ${log-lib})