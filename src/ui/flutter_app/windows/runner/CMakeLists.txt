cmake_minimum_required(VERSION 3.15)
project(runner LANGUAGES CXX)

add_definitions(-D FLUTTER_UI)

INCLUDE_DIRECTORIES(
  ../../../../
  ../../../../../include
  ../../command
)

add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "main.cpp"
  "run_loop.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "mill_engine.cpp"
  "../../command/command_channel.cpp"
  "../../command/command_queue.cpp"
  "../../command/engine_main.cpp"
  "../../../../bitboard.cpp"
  "../../../../endgame.cpp"
  "../../../../evaluate.cpp"
  "../../../../main.cpp"
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

  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)
apply_standard_settings(${BINARY_NAME})
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")
add_dependencies(${BINARY_NAME} flutter_assemble)
