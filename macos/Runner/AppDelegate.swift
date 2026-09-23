import Cocoa
import FlutterMacOS
import NetworkExtension

@main
class AppDelegate: FlutterAppDelegate {
  /// Set once the system announces a logout, restart or shutdown.
  ///
  /// FlutterAppDelegate answers every quit with `.terminateCancel` while it asks
  /// the Dart side whether to exit (System.requestAppExit), then quits on its
  /// own once Dart agrees. That is right for Cmd+Q, but at logout a cancel
  /// reply is what makes macOS abandon the logout and name this app as the one
  /// that stopped it. When the system is going down, there is nothing to ask.
  ///
  /// Never reset. If a logout is itself cancelled, a later Cmd+Q skips the Dart
  /// exit path, and the tunnel is still stopped below in applicationWillTerminate.
  private var systemIsPoweringOff = false

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    // Closing the window hides it (or asks, per the closing preference); the app
    // keeps running in the menu bar. https://github.com/leanflutter/window_manager/issues/214
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationWillFinishLaunching(_ notification: Notification) {
    // FlutterAppDelegate implements this: it names the window and the
    // application menu after the bundle.
    super.applicationWillFinishLaunching(notification)
    NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.willPowerOffNotification, object: nil, queue: .main
    ) { [weak self] _ in
      self?.systemIsPoweringOff = true
    }
  }

  // No notification-permission request any more. Upstream asked for alert and
  // badge permission at every launch, and nothing in this app posts a
  // notification: the in-app inbox is drawn by Flutter. A prompt that grants
  // nothing is also a question an App Store reviewer asks.

  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    if systemIsPoweringOff {
      return .terminateNow
    }
    // Cmd+Q, the Dock's Quit and window_manager's destroy() all arrive here.
    // FlutterAppDelegate hands the request to Dart, where an AppLifecycleListener
    // can run the app's own exit path before agreeing.
    return super.applicationShouldTerminate(sender)
  }

  override func applicationWillTerminate(_ notification: Notification) {
    // The packet-tunnel extension is a separate process and outlives this one.
    // The Windows client drops the tunnel when it exits, and so does this one,
    // whichever route the quit took: the Dart exit path, a logout, or a quit that
    // arrived before Dart was ready to be asked. Force Quit and a crash never
    // reach this method; the tunnel then keeps running, and the next launch
    // adopts it. FlutterAppDelegate does not implement this method, so there is
    // no super to call.
    let state = VPNManager.shared.state
    if state != .disconnected && state != .invalid {
      VPNManager.shared.disconnect()
    }
  }

  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    // Launching the app again while it runs hidden in the menu bar must bring the
    // window back, as a second launch does on Windows. Hiding also removes the
    // Dock icon (setSkipTaskbar on macOS, window_notifier.dart), so the activation
    // policy has to be restored as well as the window. Not implemented by
    // FlutterAppDelegate either.
    if !flag {
      NSApp.setActivationPolicy(.regular)
      let window = mainFlutterWindow ?? NSApp.windows.first { $0 is MainFlutterWindow }
      window?.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
    }
    return true
  }
}
