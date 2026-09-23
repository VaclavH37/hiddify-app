//
//  AlertEventHandler.swift
//  Runner
//

import Foundation
import Combine
// Explicit, not left to the bridging header: iOS reaches Flutter through
// Runner-Bridging-Header.h, but the macOS target compiles this file too and has
// no bridging header.
#if os(macOS)
import FlutterMacOS
#else
import Flutter
#endif

public class AlertsEventHandler: NSObject, FlutterPlugin, FlutterStreamHandler {
    static let name = "\(Bundle.main.serviceIdentifier)/service.alerts"
    
    private var channel: FlutterEventChannel?
    
    private var cancellable: AnyCancellable?
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = AlertsEventHandler()
        instance.channel = FlutterEventChannel(name: Self.name, binaryMessenger: registrar.raynMessenger, codec: FlutterJSONMethodCodec())
        instance.channel?.setStreamHandler(instance)
    }
    
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        cancellable = VPNManager.shared.$alert.sink { [events] alert in
            var data = [
                "status": "Stopped",
                "alert": alert.alert?.rawValue,
                "message": alert.message,
            ]
            for key in data.keys {
                if data[key] == nil {
                    data.removeValue(forKey: key)
                }
            }
            events(data)
        }
        return nil
    }
    
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        cancellable?.cancel()
        return nil
    }
}
