//
//  PacketTunnelProvider.swift
//  RaynTunnel
//

import NetworkExtension

class PacketTunnelProvider: ExtensionProvider {

    // Reported to the app by handleAppMessage below. Nothing increments
    // them: the only writer was a commented-out TrafficReader, which polled
    // the core's clash_api over cleartext http/ws on loopback and was
    // deleted with that file. The counters therefore always read 0.
    private var upload: Int64 = 0
    private var download: Int64 = 0

    override func startTunnel(options: [String : NSObject]?) async throws {
//    override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {

        try await super.startTunnel(options: options)
    }
    
    override func handleAppMessage(_ messageData: Data) async -> Data? {
        
        let message = String(data: messageData, encoding: .utf8)
        switch message {
        case "stats":
            return "\(upload),\(download)".data(using: .utf8)!
        default:
            return nil
        }
    }
}
