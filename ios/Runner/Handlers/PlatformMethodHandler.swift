//
//  PlatformMethodHandler.swift
//  Runner
//

// Shared with the macOS target, which compiles this file in place (macos/
// references ios/). The FlutterMacOS module has the same API under another name.
#if os(macOS)
import FlutterMacOS
#else
import Flutter
#endif
import Combine
import RaynCore

public class PlatformMethodHandler: NSObject, FlutterPlugin {
        
    public static let name = "\(Bundle.main.serviceIdentifier)/platform"
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: Self.name, binaryMessenger: registrar.raynMessenger)
        let instance = PlatformMethodHandler()
        registrar.addMethodCallDelegate(instance, channel: channel)
        instance.channel = channel
    }
    
    private var channel: FlutterMethodChannel?
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "get_paths":
            result(getPaths(args: call.arguments) as NSDictionary)
        case "get_config_key":
            // Returns the per-install key that seals configs/<id>.enc, creating
            // it on first call. Only the app reaches this; the packet-tunnel
            // extension uses ConfigKey.peek(), which never creates.
            if let key = ConfigKey.getOrCreate() {
                result(FlutterStandardTypedData(bytes: key))
            } else {
                result(FlutterError(code: "CONFIG_KEY", message: "keychain unavailable", details: nil))
            }
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    public func getPaths(args: Any?) -> [String:String] {
        return [
            "base": FilePath.sharedDirectory.path,
            "working": FilePath.workingDirectory.path,
            "temp": FilePath.cacheDirectory.path
        ]
    }
}
