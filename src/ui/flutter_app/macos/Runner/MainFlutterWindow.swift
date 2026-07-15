// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// MainFlutterWindow.swift

import Cocoa
import FlutterMacOS
import device_info_plus
import share_plus
import url_launcher_macos

class MainFlutterWindow: NSWindow {

    private func setTitle(title: String) {
        DispatchQueue.main.async {
            self.title = title
        }
    }

    // The Mill engine MethodChannel that used to run here was removed in
    // Phase 3 / Phase 4 along with the native C++ engine; the Rust/TGF
    // engine talks to Dart through `flutter_rust_bridge` so no Swift-side
    // handler is needed.  The remaining `com.calcitem.sanmill/ui`
    // channel only forwards window-title updates from the Flutter side.

    private func setupUIMethodChannel(controller: FlutterViewController) {
            let uiChannel = FlutterMethodChannel(name: "com.calcitem.sanmill/ui",
                                                binaryMessenger: controller.engine.binaryMessenger)

            uiChannel.setMethodCallHandler { [weak self] (call, result) in
                switch call.method {
                case "setWindowTitle":
                    if let arguments = call.arguments as? [String: Any],
                       let title = arguments["title"] as? String {
                        self?.setTitle(title: title)
                    }
                    result(nil)
                default:
                    result(FlutterMethodNotImplemented)
                }
            }
        }

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    self.setContentSize(NSSize(width: 540, height: 960))

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()

    setupUIMethodChannel(controller: flutterViewController)
  }
}
