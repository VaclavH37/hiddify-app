import UIKit
import Flutter
import RaynCore
@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
    
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        setupFileManager()
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
    
    /// Registers our channels and the plugins on the engine that the
    /// storyboard's FlutterViewController creates.
    ///
    /// They used to register in didFinishLaunching, through
    /// `self.registrar(forPlugin:)`. Under the UIScene lifecycle (the
    /// UIApplicationSceneManifest in Info.plist, which iOS 27 requires of an
    /// app built with the iOS 27 SDK) the Flutter view is created only when the
    /// scene connects, after didFinishLaunching has returned, so there is no
    /// engine to register on at that point and those force-unwraps would crash
    /// at launch. Flutter calls this as soon as the engine exists, before any
    /// Dart code runs, which is all the registrations below have ever needed.
    func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
        let registry = engineBridge.pluginRegistry
        MethodHandler.register(with: registry.registrar(forPlugin: MethodHandler.name)!)
        PlatformMethodHandler.register(with: registry.registrar(forPlugin: PlatformMethodHandler.name)!)
        FileMethodHandler.register(with: registry.registrar(forPlugin: FileMethodHandler.name)!)
        StatusEventHandler.register(with: registry.registrar(forPlugin: StatusEventHandler.name)!)
        AlertsEventHandler.register(with: registry.registrar(forPlugin: AlertsEventHandler.name)!)
        // Registered with the rest, before any Flutter UI: StoreKit can deliver
        // a renewal or an Ask-to-Buy approval at any time, and the handler has
        // to be observing Transaction.updates to catch it. Under scenes this is
        // a moment after launch rather than during it; StoreKit hands unfinished
        // transactions to a listener when it starts, so none is missed.
        RaynBillingHandler.register(with: registry.registrar(forPlugin: RaynBillingHandler.name)!)
//        LogsEventHandler.register(with: registry.registrar(forPlugin: LogsEventHandler.name)!)
//        GroupsEventHandler.register(with: registry.registrar(forPlugin: GroupsEventHandler.name)!)
//        ActiveGroupsEventHandler.register(with: registry.registrar(forPlugin: ActiveGroupsEventHandler.name)!)
//        StatsEventHandler.register(with: registry.registrar(forPlugin: StatsEventHandler.name)!)
        GeneratedPluginRegistrant.register(with: registry)
    }
    
    func setupFileManager() {
        try? FileManager.default.createDirectory(at: FilePath.workingDirectory, withIntermediateDirectories: true)
        FileManager.default.changeCurrentDirectoryPath(FilePath.sharedDirectory.path)
    }
}
