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
        //setupMethodChannel()
    }

    private func setupMethodChannel() {
        print("Setting up method channel")

        guard let controller = NSApp.mainWindow?.contentViewController as? FlutterViewController else {
            print("Failed to get FlutterViewController. mainWindow: \(String(describing: NSApp.mainWindow)), contentViewController: \(String(describing: NSApp.mainWindow?.contentViewController))")
            return
        }

        print("Successfully obtained FlutterViewController")

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

    override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
}

