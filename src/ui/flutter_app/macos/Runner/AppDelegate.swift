// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// AppDelegate.swift

import Cocoa
import FlutterMacOS
import device_info_plus
import path_provider_foundation
import share_plus
import url_launcher_macos

// The legacy `MillEngine` Swift class lived in
// `command/mill_engine.{h,cpp}` and bridged the Mill C++ UCI engine
// over `com.calcitem.sanmill/engine`.  Both the engine sources and
// the MethodChannel handler were retired in Phase 3 / Phase 4; the
// Rust/TGF engine reaches Dart through `flutter_rust_bridge`, so no
// AppDelegate-level bridge is needed any more.

@main
class AppDelegate: FlutterAppDelegate {
    override func applicationDidFinishLaunching(_ aNotification: Notification) {
        //GeneratedPluginRegistrant.register(with: self)
    }

    override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
}
