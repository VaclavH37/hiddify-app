//
//  StatusEventHandler.swift
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

public class StatusEventHandler: NSObject, FlutterPlugin, FlutterStreamHandler {
    static let name = "\(Bundle.main.serviceIdentifier)/service.status"
    
    private var channel: FlutterEventChannel?
    
    private var cancellable: AnyCancellable?
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = StatusEventHandler()
        instance.channel = FlutterEventChannel(name: Self.name, binaryMessenger: registrar.raynMessenger, codec: FlutterJSONMethodCodec())
        instance.channel?.setStreamHandler(instance)
    }
    
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        cancellable = VPNManager.shared.$state.sink { [events] status in
            switch status {
            case .reasserting, .connecting:
                events(["status": "Starting"])
            case .connected:
                events(["status": "Started"])
            case .disconnecting:
                events(["status": "Stopping"])
            case .disconnected, .invalid:
                events(["status": "Stopped"])
            @unknown default:
                events(["status": "Stopped"])
            }
        }
        return nil
    }
    
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        cancellable?.cancel()
        return nil
    }
}
