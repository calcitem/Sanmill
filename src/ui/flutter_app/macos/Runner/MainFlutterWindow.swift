import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
    override func awakeFromNib() {
        let flutterViewController = FlutterViewController.init()

        let initialSize = NSRect(x: 0, y: 0, width: 800, height: 600)
        self.setContentSize(NSSize(width: initialSize.width, height: initialSize.height))
        self.setFrame(initialSize, display: true)

        self.contentViewController = flutterViewController

        RegisterGeneratedPlugins(registry: flutterViewController)

        super.awakeFromNib()

        self.makeKeyAndOrderFront(nil)
    }
}
