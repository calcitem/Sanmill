cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

add_definitions(-D FLUTTER_UI)

INCLUDE_DIRECTORIES(
  ../../../../
  ../../../../../include
  ../../command
  ../../../../perfect
)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "main.cpp"
  "run_loop.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "../../command/command_channel.cpp"
  "../../command/command_queue.cpp"
  "../../command/engine_main.cpp"
  "../../command/mill_engine.cpp"
  "../../../../bitboard.cpp"
  "../../../../endgame.cpp"
  "../../../../evaluate.cpp"
  "../../../../main.cpp"
  "../../../../mcts.cpp"
  "../../../../mills.cpp"
  "../../../../misc.cpp"
  "../../../../movegen.cpp"
  "../../../../movepick.cpp"
  "../../../../option.cpp"
  "../../../../position.cpp"
  "../../../../rule.cpp"
  "../../../../search.cpp"
  "../../../../thread.cpp"
  "../../../../tt.cpp"
  "../../../../uci.cpp"
  "../../../../ucioption.cpp"
  "../../../../perfect/perfect_adaptor.cpp"
  "../../../../perfect/perfect_api.cpp"
  "../../../../perfect/perfect_adaptor.cpp"
  "../../../../perfect/perfect_common.cpp"
  "../../../../perfect/perfect_debug.cpp"
  "../../../../perfect/perfect_eval_elem.cpp"
  "../../../../perfect/perfect_game.cpp"
  "../../../../perfect/perfect_game_state.cpp"
  "../../../../perfect/perfect_hash.cpp"
  "../../../../perfect/perfect_log.cpp"
  "../../../../perfect/perfect_move.cpp"
  "../../../../perfect/perfect_player.cpp"
  "../../../../perfect/perfect_rules.cpp"
  "../../../../perfect/perfect_sec_val.cpp"
  "../../../../perfect/perfect_sector.cpp"
  "../../../../perfect/perfect_sector_graph.cpp"
  "../../../../perfect/perfect_symmetries.cpp"
  "../../../../perfect/perfect_symmetries_slow.cpp"
  "../../../../perfect/perfect_wrappers.cpp"

  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the build version.
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")

# Disable Windows macros that collide with C++ standard library functions.
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

# Add dependency libraries and include directories. Add any application-specific
# dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)

# Check if the Microsoft Visual C++ compiler is being used
#if(MSVC)
  # If it is, then add compile options for the target ${BINARY_NAME}, using /wd4244 to disable
  # warning 4244
  # /wd4244 is a MSVC specific compiler option used to disable warning 4244
  # This warning generally occurs during potential numeric conversions, where a variable is
  # converted from a larger numeric type (like double or float) to a smaller numeric type
  # (like int)
# target_compile_options(${BINARY_NAME} PRIVATE /wd4244)
#endif()
