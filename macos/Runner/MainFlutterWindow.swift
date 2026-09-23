import Cocoa
import FlutterMacOS
import window_manager
import LaunchAtLogin

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    // Before the engine exists, as iOS does in AppDelegate.setupFileManager: the
    // Dart side reads these paths over the platform channel as soon as it starts.
    prepareWorkingDirectory()

    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    FlutterMethodChannel(
      name: "launch_at_startup", binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    .setMethodCallHandler { (_ call: FlutterMethodCall, result: @escaping FlutterResult) in
      switch call.method {
      case "launchAtStartupIsEnabled":
        result(LaunchAtLogin.isEnabled)
      case "launchAtStartupSetEnabled":
        // Was `as! Bool`: a call without the argument crashed the app.
        guard
          let arguments = call.arguments as? [String: Any],
          let enabled = arguments["setEnabledValue"] as? Bool
        else {
          result(FlutterError(code: "INVALID_ARGS", message: "setEnabledValue must be a bool", details: nil))
          return
        }
        LaunchAtLogin.isEnabled = enabled
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    RegisterGeneratedPlugins(registry: flutterViewController)
    registerRaynHandlers(with: flutterViewController)

    super.awakeFromNib()
  }

  /// The channels the Dart side's CoreInterfaceMobile, directories and billing
  /// code talk to. These are the iOS handlers, compiled in place from ../ios;
  /// iOS registers the same set in its AppDelegate.
  ///
  /// Billing is registered at launch rather than on first use for the reason
  /// given in the iOS AppDelegate: StoreKit can deliver a renewal the moment the
  /// process starts, and an update with no observer attached is lost.
  private func registerRaynHandlers(with registry: FlutterPluginRegistry) {
    MethodHandler.register(with: registry.registrar(forPlugin: MethodHandler.name))
    PlatformMethodHandler.register(with: registry.registrar(forPlugin: PlatformMethodHandler.name))
    StatusEventHandler.register(with: registry.registrar(forPlugin: StatusEventHandler.name))
    AlertsEventHandler.register(with: registry.registrar(forPlugin: AlertsEventHandler.name))
    RaynBillingHandler.register(with: registry.registrar(forPlugin: RaynBillingHandler.name))
  }

  /// Creates the working directory inside the app-group container and moves the
  /// process into the container root, as ios/Runner/AppDelegate.swift does. The
  /// core changes into the working directory itself when it sets up, and the
  /// Dart side creates the directories too; this only guarantees they exist first.
  private func prepareWorkingDirectory() {
    try? FileManager.default.createDirectory(at: FilePath.workingDirectory, withIntermediateDirectories: true)
    FileManager.default.changeCurrentDirectoryPath(FilePath.sharedDirectory.path)
  }

  // window manager hidden at launch
  override public func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
    super.order(place, relativeTo: otherWin)
    hiddenWindowAtLaunch()
  }
}
