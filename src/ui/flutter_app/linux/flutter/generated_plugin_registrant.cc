//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <catcher/catcher_plugin.h>
#include <devicelocale/devicelocale_plugin.h>
#include <url_launcher_linux/url_launcher_plugin.h>

void fl_register_plugins(FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) catcher_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "CatcherPlugin");
  catcher_plugin_register_with_registrar(catcher_registrar);
  g_autoptr(FlPluginRegistrar) devicelocale_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "DevicelocalePlugin");
  devicelocale_plugin_register_with_registrar(devicelocale_registrar);
  g_autoptr(FlPluginRegistrar) url_launcher_linux_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "UrlLauncherPlugin");
  url_launcher_plugin_register_with_registrar(url_launcher_linux_registrar);
}
