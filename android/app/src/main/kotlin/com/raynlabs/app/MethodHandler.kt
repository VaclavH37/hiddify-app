package com.raynlabs.app

import android.util.Log
import com.raynlabs.app.bg.BoxService
//import com.raynlabs.app.bg.BoxService.Companion.workingDir
import com.raynlabs.app.constant.Status
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

import com.raynlabs.core.libbox.Libbox
import com.raynlabs.core.mobile.Mobile
import com.raynlabs.core.mobile.SetupOptions
import com.raynlabs.app.bg.Bugs
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.io.File

class MethodHandler(private val scope: CoroutineScope) : FlutterPlugin,
    MethodChannel.MethodCallHandler {
    private var channel: MethodChannel? = null

    companion object {
        const val TAG = "A/MethodHandler"
        const val channelName = "com.raynlabs.app/method"

        enum class Trigger(val method: String) {
            Setup("setup"),
            Start("start"),
            Stop("stop"),
            Restart("restart"),
            AddGrpcClientPublicKey("add_grpc_client_public_key"),
            GetGrpcServerPublicKey("get_grpc_server_public_key"),
            GetGrpcSecret("get_grpc_secret"),
            RotateGrpcBgSecret("rotate_grpc_bg_secret"),
            GetGrpcBgSecret("get_grpc_bg_secret"),

        }
    }

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(
            flutterPluginBinding.binaryMessenger,
            channelName,
        )
        channel!!.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            // Client certificates are not used — the client authenticates with the
            // setup secret. This previously stored the key in Settings and returned
            // success without ever reaching the core, so it read as implemented
            // while doing nothing. Answer explicitly rather than silently.
            Trigger.AddGrpcClientPublicKey.method -> {
                result.error(
                    "UNSUPPORTED",
                    "client certificates are not used; the client authenticates with the setup secret",
                    null,
                )
            }

            Trigger.GetGrpcServerPublicKey.method -> {
                GlobalScope.launch {
                    result.runCatching {
                        result.success(Mobile.getServerPublicKey())
                    }
                }
            }

            // The credential Dart attaches to every RPC. Generating on first read
            // is safe here because both readers — this process and the VPN service
            // — go through the same SharedPreferences, so whichever asks first
            // wins and the other sees the stored value.
            Trigger.GetGrpcSecret.method -> {
                result.success(Settings.grpcSecret)
            }

            // Minted fresh on every connect, and returned so Dart can attach it to
            // the background channel it is about to use. Dart calls this BEFORE
            // `start`, because the service reads the stored value once when it sets
            // the core up — rotating afterwards would leave the two disagreeing and
            // fail every background call.
            //
            // Rotation is what bounds the exposure of a secret that crosses a
            // plaintext socket: a process that squats the port and captures one
            // holds a value that is dead by the next connect.
            Trigger.RotateGrpcBgSecret.method -> {
                result.success(Settings.rotateGrpcBgSecret())
            }

            // READ, never mint. The VPN service outlives the Flutter engine, so a
            // Dart side that was recreated -- the first-install VPN consent dialog
            // recreates the activity, and process death does the same -- has to be
            // able to adopt the secret the running core was started with. Minting
            // here instead would hand the app a value the core has never seen and
            // wedge every background call.
            Trigger.GetGrpcBgSecret.method -> {
                result.success(Settings.grpcBgSecret)
            }

            Trigger.Setup.method -> {
                GlobalScope.launch {
                    result.runCatching {
                        val args = call.arguments as Map<*, *>
                        Settings.baseDir = args["baseDir"] as String
                        Settings.workingDir = args["workingDir"] as String
                        Settings.tempDir = args["tempDir"] as String
                        Settings.debugMode = args["debug"] as Boolean? ?: false
                        val mode = args["mode"] as Int
                        val grpcPort = args["grpcPort"] as Int
                        Log.d("debugmode","${Settings.debugMode}")
                        runCatching {
                            Mobile.setup(
                                SetupOptions().also {
                                    it.basePath = Settings.baseDir
                                    it.workingDir = Settings.workingDir
                                    it.tempDir = Settings.tempDir
                                    it.fixAndroidStack = Bugs.fixAndroidStack
                                    it.mode=mode.toLong()
                                    it.listen= "127.0.0.1:" + grpcPort
                                    // The credential the core requires on every RPC.
                                    // Owned here rather than passed from Dart: the
                                    // VPN service needs the SAME value and can be
                                    // started by the system with no Flutter engine
                                    // alive. Dart reads it back over get_grpc_secret.
                                    it.secret = Settings.grpcSecret
                                    it.debug = Settings.debugMode
                                },null)

//                            Libbox.setup(Settings.baseDir, Settings.workingDir, Settings.tempDir, false)
                            Libbox.redirectStderr(File(Settings.workingDir, "stderr2.log").path)

                            success("")
                        }.onFailure {
                            error(it)
                        }

                    }
                }
            }


            Trigger.Start.method -> {
                scope.launch {
                    result.runCatching {
                        val args = call.arguments as Map<*, *>
                        Settings.activeConfigPath = args["path"] as String? ?: ""
                        Settings.activeProfileName = args["name"] as String? ?: ""
                        Settings.debugMode = args["debug"] as Boolean? ?: false
                        Settings.grpcServiceModePort = args["grpcPort"] as Int

                        val mainActivity = MainActivity.instance
//                        val started = mainActivity.serviceStatus.value == Status.Started
//                        if (started) {
//                            Log.w(TAG, "service is already running")
//                            return@launch success(true)
//                        }
                        Settings.startCoreAfterStartingService = false

                        mainActivity.startService()
                        success(true)
                    }
                }
            }

            Trigger.Stop.method -> {
                scope.launch {
                    result.runCatching {
                        val mainActivity = MainActivity.instance
                        val started = mainActivity.serviceStatus.value == Status.Started
                        if (!started) {
                            Log.w(TAG, "service is not running")
                            //    return@launch success(true)
                        }
                        BoxService.stop()
                        success(true)
                    }
                }
            }

//            Trigger.Restart.method -> {
//                scope.launch(Dispatchers.IO) {
//                    result.runCatching {
//                        val args = call.arguments as Map<*, *>
//                        Settings.activeConfigPath = args["path"] as String? ?: ""
//                        Settings.activeProfileName = args["name"] as String? ?: ""
//                        val mainActivity = MainActivity.instance
//                        val started = mainActivity.serviceStatus.value == Status.Started
//                        if (!started) return@launch success(true)
//                        val restart = Settings.rebuildServiceMode()
//                        if (restart) {
//                            mainActivity.reconnect()
//                            BoxService.stop()
//                            delay(1000L)
//                            mainActivity.startService()
//                            return@launch success(true)
//                        }
//                        runCatching {
//                            Libbox.newStandaloneCommandClient().serviceReload()
//                            success(true)
//                        }.onFailure {
//                            error(it)
//                        }
//                    }
//                }
//            }

            else -> result.notImplemented()
        }
    }
}