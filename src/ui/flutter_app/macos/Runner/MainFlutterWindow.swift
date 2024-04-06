import Cocoa
import FlutterMacOS
import device_info_plus
import path_provider_foundation
import share_plus
import url_launcher_macos

class MainFlutterWindow: NSWindow {
    var engine: MillEngine?

    private func setTitle(title: String) {
        DispatchQueue.main.async {
            self.title = title
        }
    }

    private func setupMethodChannel( controller: FlutterViewController) {

        let channel = FlutterMethodChannel(name: "com.calcitem.sanmill41/engine",
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

    private func setupUIMethodChannel(controller: FlutterViewController) {
            let uiChannel = FlutterMethodChannel(name: "com.calcitem.sanmill41/ui",
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

    self.engine = MillEngine()

    setupMethodChannel(controller: flutterViewController)
    setupUIMethodChannel(controller: flutterViewController)
  }
}
