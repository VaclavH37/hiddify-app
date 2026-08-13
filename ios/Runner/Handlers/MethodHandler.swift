//
//  MethodHandler.swift
//  Runner
//
//  Created by GFWFighter on 10/23/23.
//

import Flutter
import Combine
import RaynCore

public class MethodHandler: NSObject, FlutterPlugin {
    
    private var cancelBag: Set<AnyCancellable> = []
    
    public static let name = "\(Bundle.main.serviceIdentifier)/method"
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: Self.name, binaryMessenger: registrar.messenger())
        let instance = MethodHandler()
        registrar.addMethodCallDelegate(instance, channel: channel)
        instance.channel = channel
    }
    
    private var channel: FlutterMethodChannel?
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        @Sendable func mainResult(_ res: Any?) async -> Void {
            await MainActor.run {
                result(res)
            }
        }
        
        switch call.method {
        // Returns the PEM certificate the Dart client pins for the secure gRPC
        // modes. This used to `result("")` -- a stub that looked implemented,
        // which is part of why the secure modes were believed to work.
        //
        // Delivered over the method channel deliberately: that is in-process and
        // therefore trustworthy, whereas fetching it over the very connection it
        // is meant to authenticate would authenticate nothing. Only valid after
        // `setup` has run with a secure mode; before that the core has no
        // certificate and this correctly returns nil.
        case "get_grpc_server_public_key":
            if let pem = MobileGetServerPublicKey(), !pem.isEmpty {
                result(FlutterStandardTypedData(bytes: pem))
            } else {
                result(nil)
            }
        // Client certificates are not used -- the client authenticates with the
        // setup secret. Kept so an older Dart build calling it gets a clear
        // answer rather than MissingPluginException.
        case "add_grpc_client_public_key":
            result(FlutterError(code: "UNSUPPORTED",
                                message: "client certificates are not used; the client authenticates with the setup secret",
                                details: nil))
        // The credential Dart attaches to every RPC. Creating on first call is
        // correct here and only here: this runs in the app, whereas the extension
        // only ever peeks, so a background start cannot race the app into
        // generating a second secret and leave the two cores disagreeing.
        case "get_grpc_secret":
            if let secret = GrpcSecret.getOrCreate() {
                result(secret)
            } else {
                result(FlutterError(code: "GRPC_SECRET",
                                    message: "keychain unavailable",
                                    details: nil))
            }
        case "setup":
                Task {
                    guard
                        let args = call.arguments as? [String: Any?],
                        let baseDir = args["baseDir"] as? String,
                        let workingDir = args["workingDir"] as? String,
                        let tempDir = args["tempDir"] as? String,
                        let mode = args["mode"] as? Int,
                        let grpcPort = args["grpcPort"] as? Int
                    else {
                        result(FlutterError(code: "INVALID_ARGS", message: nil, details: nil))
                        return
                    }
                    // Dart does not send `debug` on every path; absent means off.
                    let debug = (args["debug"] as? NSNumber)?.boolValue ?? false
                    VPNConfig.shared.baseDir=baseDir
                    VPNConfig.shared.workingDir=workingDir
                    VPNConfig.shared.tempDir=tempDir
                    var error: NSError?
                    let opts = MobileSetupOptions()
                    opts.basePath = baseDir
                    opts.workingDir = workingDir
                    opts.tempDir = tempDir
                    opts.listen = "127.0.0.1:\(grpcPort)"
                    // The credential the core requires on every RPC. Was hardcoded
                    // empty, and the core read it into nothing -- plumbed the whole
                    // way here and used by no one.
                    //
                    // Owned natively rather than passed from Dart, because the
                    // packet-tunnel extension needs the SAME value and an
                    // on-demand start has no app process to hand it one. Dart
                    // fetches it back over `get_grpc_secret` for its call metadata.
                    opts.secret = GrpcSecret.getOrCreate() ?? ""
                    // Both were hardcoded, ignoring the arguments parsed above.
                    // `mode` mattered twice over: the app process is the
                    // FOREGROUND core (Dart sends 3 = GRPC_NORMAL_INSECURE,
                    // rayn_core_service.dart:99) and pinning it to 4 meant
                    //   * it set up as a background core while Dart later closed
                    //     mode 3 (rayn_core_service.dart:607) — the wrong server;
                    //   * hcore redirects stderr to data/stderr<mode>.log
                    //     (v2/hcore/grpc_server.go:67), so this process and the
                    //     packet-tunnel extension — which is legitimately mode 4 —
                    //     interleaved into one file.
                    // Android has always forwarded both (MethodHandler.kt:94).
                    opts.debug = debug
                    opts.mode = mode
                    opts.fixAndroidStack = false
                    MobileSetup(opts,
                        nil,
                        &error
                    )
                    
                    if let error {
                        result(FlutterError(code: String(error.code), message: error.localizedDescription, details: nil))
                        return
                    }
                    do {
                        try await VPNManager.shared.setup()
                    } catch {
                        result(FlutterError(code: "SETUP", message: error.localizedDescription, details: nil))
                        return
                    }
                    result(true)
                }
        case "start":
            Task {
                guard
                    let args = call.arguments as? [String:Any?],
                    let path = args["path"] as? String,
                    let name = args["name"] as? String,
                    let grpcPort=args["grpcPort"] as? Int
                else {
                    await mainResult(FlutterError(code: "INVALID_ARGS", message: nil, details: nil))
                    return
                }
                VPNConfig.shared.activeConfigPath = path
                VPNConfig.shared.activeProfileName = name
                VPNConfig.shared.grpcServiceModePort=grpcPort
                
                var error: NSError?
                //let configstr=MobileBuildConfig(path,&error) as String
                if let error {
                    await mainResult(FlutterError(code: String(error.code), message: error.description, details: nil))
                    return
                }
                do {
                    try await VPNManager.shared.setup()
                    try await VPNManager.shared.connect(with: path, grpcServiceModePort: grpcPort, disableMemoryLimit: VPNConfig.shared.disableMemoryLimit)
                } catch {
                    await mainResult(FlutterError(code: "SETUP_CONNECTION", message: error.localizedDescription, details: nil))
                    return
                }
                await mainResult(true)
            }
//        case "restart":
//            Task { [unowned self] in
//                guard
//                    let args = call.arguments as? [String:Any?],
//                    let path = args["path"] as? String,
//                    let name = args["name"] as? String,
//                    let grpcPort=args["grpcPort"] as? Int
//                else {
//                    await mainResult(FlutterError(code: "INVALID_ARGS", message: nil, details: nil))
//                    return
//                }
//                VPNConfig.shared.activeConfigPath = path
//                VPNConfig.shared.activeProfileName = name
//                VPNConfig.shared.grpcServiceModePort=grpcPort
//                
//                
//                VPNManager.shared.disconnect()
//                await waitForStop().value
//                var error: NSError?
//                do {
//                    try await VPNManager.shared.setup()
//                    try await VPNManager.shared.connect(with: path, disableMemoryLimit: VPNConfig.shared.disableMemoryLimit)
//                } catch {
//                    await mainResult(FlutterError(code: "SETUP_CONNECTION", message: error.localizedDescription, details: nil))
//                    return
//                }
//                await mainResult(true)
//            }
        case "stop":
            VPNManager.shared.disconnect()
            result(true)
        case "reset":
            VPNManager.shared.reset()
            result(true)
        // Removed with this comment as their headstone, so nobody re-adds them:
        //
        //   select_outbound, url_test  -- called LibboxNewStandaloneCommandClient()
        //     against a command server this extension has not started since the
        //     gRPC switch (see the commented-out commandServer in
        //     ExtensionProvider). Dart reaches both over gRPC instead
        //     (rayn_core_service.dart:358 -> bgClient.selectOutbound), which is
        //     also why the sing-box 1.14 selection-notify fix applies to iOS
        //     without anything extra.
        //   generate_config, parse_config -- bodies were commented out.
        //     generate_config additionally never called result(), so invoking it
        //     would have hung the Dart future forever.
        //   generate_warp_config -- WARP was removed from this fork.
        //   change_hiddify_options -- wrote VPNConfig.configOptions, which
        //     nothing reads; the config now arrives from Dart already built.
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func waitForStop() -> Future<Void, Never> {
        return Future { promise in
            var cancellable: AnyCancellable? = nil
            cancellable = VPNManager.shared.$state
                .filter { $0 == .disconnected }
                .first()
                .delay(for: 0.5, scheduler: RunLoop.current)
                .sink(receiveValue: { _ in
                    promise(.success(()))
                    cancellable?.cancel()
                })
        }
    }
}
