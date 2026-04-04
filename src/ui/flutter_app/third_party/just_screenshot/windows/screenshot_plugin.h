#ifndef FLUTTER_PLUGIN_SCREENSHOT_PLUGIN_H_
#define FLUTTER_PLUGIN_SCREENSHOT_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace screenshot {

// Windows implementation of the screenshot plugin.
// 
// Error Codes (returned via MethodResult::Error):
// - "cancelled": User cancelled the screenshot operation (ESC or right-click during region selection)
// - "not_supported": Screenshot operation is not supported on this platform (non-Windows)
// - "internal_error": Internal Windows API error occurred (BitBlt, WIC encoding, memory allocation failure)
//                     Details contain Win32 error code (GetLastError) or error description
// - "invalid_argument": Invalid parameters provided (missing 'mode', invalid mode value, invalid parameter types)
//
// Return Values:
// - Success with Map: Screenshot captured successfully, contains 'width', 'height', 'bytes' (PNG)
// - Success with null: User cancelled (region mode ESC/right-click) - not an error
// - Error: Operation failed, see error codes above
class ScreenshotPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  ScreenshotPlugin();

  virtual ~ScreenshotPlugin();

  // Disallow copy and assign.
  ScreenshotPlugin(const ScreenshotPlugin&) = delete;
  ScreenshotPlugin& operator=(const ScreenshotPlugin&) = delete;

  // Called when a method is called on this plugin's channel from Dart.
  // 
  // Supported methods:
  // - "capture": Capture screenshot (screen or region mode)
  //   Parameters: { mode: "screen"|"region", includeCursor?: bool, displayId?: int }
  //   Returns: { width: int, height: int, bytes: Uint8List } or null (if cancelled)
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

}  // namespace screenshot

#endif  // FLUTTER_PLUGIN_SCREENSHOT_PLUGIN_H_
