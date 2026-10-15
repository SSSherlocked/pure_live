import Cocoa
import FlutterMacOS
import window_manager

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    // Runs before the Flutter engine starts. A second copy of the app (same
    // bundle id, e.g. one in ~/Applications and one in ~/Downloads) shares the
    // sandbox container, and its Hive boxes would fail to lock and leave a
    // black window. Hand focus to the running instance and quit instead.
    if MainFlutterWindow.activateExistingInstance() {
      exit(0)
    }

    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }

  // The window from MainMenu.xib (800x600, with a title bar) would show,
  // black, until Flutter has started and sized it: it stays hidden instead,
  // and DesktopManager shows it once it is ready (window_manager's
  // "hidden at launch").
  override public func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
    super.order(place, relativeTo: otherWin)
    hiddenWindowAtLaunch()
  }

  /// Brings an already running instance to the front.
  ///
  /// Returns true when another live instance exists; this process must then
  /// quit even if the activation request is declined, because it cannot open
  /// the shared data store.
  private static func activateExistingInstance() -> Bool {
    guard let bundleId = Bundle.main.bundleIdentifier else { return false }
    let currentPid = ProcessInfo.processInfo.processIdentifier
    let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
      .filter { $0.processIdentifier != currentPid && !$0.isTerminated }
    guard let existing = others.first else { return false }

    existing.unhide()
    existing.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
    return true
  }
}
