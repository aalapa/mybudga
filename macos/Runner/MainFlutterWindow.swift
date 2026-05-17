import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // Minimum size — keeps the nav rail + at least one budget column usable
    self.minSize = NSSize(width: 1100, height: 680)

    // Restore saved frame; fall back to a generous default on first launch
    let didRestore = self.setFrameUsingName("MainWindow")
    if !didRestore || self.frame.width < 1100 {
      // First launch: fill the visible screen area (excludes menu bar + dock)
      if let screen = NSScreen.main {
        self.setFrame(screen.visibleFrame, display: true, animate: false)
      } else {
        self.setContentSize(NSSize(width: 1440, height: 900))
        self.center()
      }
    }
    self.setFrameAutosaveName("MainWindow")

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
