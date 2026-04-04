#include "include/just_screenshot/screenshot_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "screenshot_plugin.h"

void ScreenshotPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  screenshot::ScreenshotPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
