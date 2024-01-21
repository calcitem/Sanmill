import Cocoa
import FlutterMacOS
import device_info_plus
import path_provider_foundation
import share_plus
import url_launcher_macos



@NSApplicationMain
class AppDelegate: FlutterAppDelegate {
    var engine: MillEngine?

    override init() {
        super.init()
        self.engine = MillEngine()
    }

    override func applicationDidFinishLaunching(_ aNotification: Notification) {
        //GeneratedPluginRegistrant.register(with: self)
        setupMethodChannel()
    }

    private func setupMethodChannel() {
        guard let controller = NSApp.mainWindow?.contentViewController as? FlutterViewController else {
            return
        }

        let channel = FlutterMethodChannel(name: "com.calcitem.sanmill/engine",
                                          binaryMessenger: controller.engine.binaryMessenger)

        channel.setMethodCallHandler { [weak self] (call, result) in
            guard let strongEngine = self?.engine else {
                result(FlutterMethodNotImplemented)
                return
            }

            switch call.method {
            case "startup":
                result(strongEngine.startup(controller))
            case "send":
                if let arguments = call.arguments as? String {
                    result(strongEngine.send(arguments))
                } else {
                    result(FlutterMethodNotImplemented)
                }
            case "read":
                result(strongEngine.read())
            case "shutdown":
                result(strongEngine.shutdown())
            case "isReady":
                result(strongEngine.isReady())
            case "isThinking":
                result(strongEngine.isThinking())
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

