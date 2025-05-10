cmake_minimum_required(VERSION 3.22.1)
cmake_policy(SET CMP0069 NEW)

project(sanmill LANGUAGES CXX)

# ---------- PGO flags injected by Gradle/Env ---------------------------------
set(PACKAGE_NAME "com.calcitem.sanmill")               # single source of truth

# These are expected to be passed as -D arguments from Gradle
# Or set via environment by android-pgo.sh and picked up by Gradle
if(NOT DEFINED USE_PGO)
    set(USE_PGO OFF CACHE BOOL "Enable PGO" FORCE)
else()
    set(USE_PGO ${USE_PGO} CACHE BOOL "Enable PGO" FORCE)
endif()
if(NOT DEFINED PGO_GENERATE)
    set(PGO_GENERATE OFF CACHE BOOL "Generate profile data" FORCE)
else()
    set(PGO_GENERATE ${PGO_GENERATE} CACHE BOOL "Generate profile data" FORCE)
endif()
if(NOT DEFINED PGO_USE)
    set(PGO_USE OFF CACHE BOOL "Use collected profile" FORCE)
else()
    set(PGO_USE ${PGO_USE} CACHE BOOL "Use collected profile" FORCE)
endif()

# PGO_PROFILE_PATH is expected to be passed as -D argument from Gradle
if(DEFINED PGO_PROFILE_PATH)
    message(STATUS "PGO_PROFILE_PATH is defined via -D as: ${PGO_PROFILE_PATH}")
    set(PGO_PROFILE_PATH "${PGO_PROFILE_PATH}" CACHE STRING "Path to PGO profile data" FORCE)
else()
    message(STATUS "PGO_PROFILE_PATH is NOT defined via -D. Will be empty or from cache.")
    # Initialize it empty if not defined, ensuring it's a STRING, and allow cache to fill or be empty.
    set(PGO_PROFILE_PATH "" CACHE STRING "Path to PGO profile data" FORCE)
endif()
message(STATUS "Final PGO_PROFILE_PATH for this run: '${PGO_PROFILE_PATH}'")
message(STATUS "USE_PGO: ${USE_PGO}, PGO_GENERATE: ${PGO_GENERATE}, PGO_USE: ${PGO_USE}")

# --------------------------------------------------------------------
# Instrumentation flags ----------------------------------------------
# --------------------------------------------------------------------
if(USE_PGO)
    if(PGO_GENERATE)
        message(STATUS "PGO_GENERATE is ON. Applying PGO generation flags.")
        # record raw profiles on the device
        add_compile_options(-fprofile-instr-generate=/data/data/${PACKAGE_NAME}/files/sanmill-%m.profraw)
        # IMPORTANT: -u __llvm_profile_runtime is a LINKER flag, not a compiler flag.
        # It ensures the profile runtime is linked into the final shared library.
        # We will add this to target_link_libraries or set_target_properties for LINK_FLAGS.
        # For now, let's ensure it's not in compile_options.
        message(STATUS "PGO-GEN: emitting .profraw into /data/data/${PACKAGE_NAME}/files/sanmill-%m.profraw")
    elseif(PGO_USE)
        message(STATUS "PGO_USE is ON. Applying PGO usage flags. Profile path: '${PGO_PROFILE_PATH}'")
        if("${PGO_PROFILE_PATH}" STREQUAL "")
            message(FATAL_ERROR "PGO_USE is ON but PGO_PROFILE_PATH is empty. Check Gradle/CMake configuration.")
        elseif("${PGO_PROFILE_PATH}" STREQUAL "OFF")
            message(FATAL_ERROR "PGO_USE is ON but PGO_PROFILE_PATH is 'OFF'. Configuration or cache issue.")
        endif()
        add_compile_options(-fprofile-instr-use=${PGO_PROFILE_PATH}.profdata)
        # -fprofile-use is also a linker flag, typically added alongside the compile option.
        # We will add this to target_link_libraries or set_target_properties for LINK_FLAGS.
        message(STATUS "PGO-USE: Will attempt to optimize with ${PGO_PROFILE_PATH}.profdata")
    else()
        message(STATUS "USE_PGO is ON, but neither PGO_GENERATE nor PGO_USE is ON. No PGO flags applied.")
    endif()
else()
    message(STATUS "USE_PGO is OFF. No PGO flags applied.")
endif()

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

set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Werror -Wall -Wcast-qual -pedantic -Wextra -Wshadow -fexceptions -DUSE_POPCNT")
#set(CMAKE_CXX_FLAGS_RELEASE "-O3")
set(CMAKE_CXX_FLAGS_DEBUG "-g")

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

# If we are in PGO generation mode, define PGO_GENERATE for this target so that
# C/C++ source can guard instrumentation-specific code.
if(USE_PGO AND PGO_GENERATE)
    target_compile_definitions(sanmill PRIVATE PGO_GENERATE)
endif()

# Enable LTO only for release builds (and not for ASAN builds)
if (NOT CMAKE_BUILD_TYPE STREQUAL "Debug" AND NOT DEFINED USE_ASAN)
    include(CheckIPOSupported)
    check_ipo_supported(RESULT ipo_supported_result)
    if (ipo_supported_result)
        set_property(TARGET sanmill PROPERTY INTERPROCEDURAL_OPTIMIZATION TRUE)
        message(STATUS "IPO is enabled for Release build")
    else()
        message(STATUS "IPO is NOT enabled for Release build (not supported by toolchain or manually disabled)")
    endif ()
endif ()

# Configure Address Sanitizer for dev mode
if (DEFINED USE_ASAN AND USE_ASAN)
    target_compile_options(sanmill PUBLIC -fsanitize=address -fno-omit-frame-pointer)
    set_target_properties(sanmill PROPERTIES LINK_FLAGS -fsanitize=address)
endif ()

# Add PGO linker flags if enabled
if(USE_PGO)
    if(PGO_GENERATE)
        # Ensures the linker includes PGO generation runtime and necessary symbols.
        target_link_options(sanmill PRIVATE -fprofile-instr-generate)
        target_link_options(sanmill PRIVATE -Wl,-u,__llvm_profile_runtime)
    elseif(PGO_USE)
        # Links with the collected profile data for optimization.
        target_link_options(sanmill PRIVATE -fprofile-use=${PGO_PROFILE_PATH}.profdata)
        # Also ensure the profile runtime is linked in PGO_USE mode if our code calls its symbols directly.
        # -fprofile-instr-generate (without path) can act as a hint to link the runtime.
        target_link_options(sanmill PRIVATE -fprofile-instr-generate)
        # Explicitly tell the linker to include __llvm_profile_runtime, which contains __llvm_profile_write_file.
        # This is needed because flush_profraw_at_exit() in main.cpp calls __llvm_profile_write_file.
        target_link_options(sanmill PRIVATE -Wl,-u,__llvm_profile_runtime)
    endif()
endif()

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