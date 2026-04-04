# Vendored `just_screenshot` 0.1.0

Upstream Windows `CMakeLists.txt` defines the library target as `screenshot_plugin`
and sets `screenshot_bundled_libraries`. Flutter’s generated
`windows/flutter/generated_plugins.cmake` expects `just_screenshot_plugin` and
`just_screenshot_bundled_libraries`, which caused CMake errors when building the
Sanmill Windows app.

Relative to pub.dev 0.1.0, Sanmill changes:

- `windows/CMakeLists.txt` — CMake target `just_screenshot_plugin` and
  `just_screenshot_bundled_libraries` (Flutter generator expectations).
- `windows/include/just_screenshot/screenshot_plugin_c_api.h` — header path so
  `#include <just_screenshot/screenshot_plugin_c_api.h>` from the app’s generated
  registrant resolves (upstream used `include/screenshot/...`).
- `windows/screenshot_plugin_c_api.cpp` — include updated to match.

License: BSD-3-Clause (see `LICENSE`).