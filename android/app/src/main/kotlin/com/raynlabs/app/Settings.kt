package com.raynlabs.app

import android.content.Context
import android.util.Base64
import com.raynlabs.app.bg.ProxyService
import com.raynlabs.app.bg.VPNService
import com.raynlabs.app.constant.ServiceMode
import com.raynlabs.app.constant.SettingsKey


object Settings {

    private val preferences by lazy {
        val context = Application.application.applicationContext
        context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
    }

    var activeConfigPath: String
        get() = preferences.getString(SettingsKey.ACTIVE_CONFIG_PATH, "")!!
        set(value) = preferences.edit().putString(SettingsKey.ACTIVE_CONFIG_PATH, value).apply()

    var activeProfileName: String
        get() = preferences.getString(SettingsKey.ACTIVE_PROFILE_NAME, "")!!
        set(value) = preferences.edit().putString(SettingsKey.ACTIVE_PROFILE_NAME, value).apply()

    var serviceMode: String
        get() = preferences.getString(SettingsKey.SERVICE_MODE, ServiceMode.VPN)!!
        set(value) = preferences.edit().putString(SettingsKey.SERVICE_MODE, value).apply()

    var configOptions: String
        get() = preferences.getString(SettingsKey.CONFIG_OPTIONS, "")!!
        set(value) = preferences.edit().putString(SettingsKey.CONFIG_OPTIONS, value).apply()

    var debugMode: Boolean
        get() = preferences.getBoolean(SettingsKey.DEBUG_MODE, false)
        set(value) = preferences.edit().putBoolean(SettingsKey.DEBUG_MODE, value).apply()

    var disableMemoryLimit: Boolean
        get() = preferences.getBoolean(SettingsKey.DISABLE_MEMORY_LIMIT, false)
        set(value) =
            preferences.edit().putBoolean(SettingsKey.DISABLE_MEMORY_LIMIT, value).apply()

    var dynamicNotification: Boolean
        get() = preferences.getBoolean(SettingsKey.DYNAMIC_NOTIFICATION, true)
        set(value) =
            preferences.edit().putBoolean(SettingsKey.DYNAMIC_NOTIFICATION, value).apply()

    var systemProxyEnabled: Boolean
        get() = preferences.getBoolean(SettingsKey.SYSTEM_PROXY_ENABLED, true)
        set(value) =
            preferences.edit().putBoolean(SettingsKey.SYSTEM_PROXY_ENABLED, value).apply()

    fun serviceClass(): Class<*> {
        return when (serviceMode) {
            ServiceMode.VPN -> VPNService::class.java
            else -> ProxyService::class.java
        }
    }

    private var currentServiceMode : String? = null

    suspend fun rebuildServiceMode(): Boolean {
        var newMode = ServiceMode.NORMAL
        try {
            if (serviceMode == ServiceMode.VPN) {
                newMode = ServiceMode.VPN
            }
        } catch (_: Exception) {
        }
        if (currentServiceMode == newMode) {
            return false
        }
        currentServiceMode = newMode
        return true
    }

    // `needVPNService()` used to live here: it read activeConfigPath as plain
    // JSON to look for a tun inbound. It had no callers, and the config at that
    // path is now sealed, so it is gone rather than taught to decrypt.

    var workingDir: String
        get() = preferences.getString(SettingsKey.WORKING_DIR, "./")!!
        set(value) = preferences.edit().putString(SettingsKey.WORKING_DIR, value).apply()
    var tempDir: String
        get() = preferences.getString(SettingsKey.TMP_DIR, "./")!!
        set(value) = preferences.edit().putString(SettingsKey.TMP_DIR, value).apply()

    var baseDir: String
        get() = preferences.getString(SettingsKey.BASE_DIR, "./")!!
        set(value) = preferences.edit().putString(SettingsKey.BASE_DIR, value).apply()



    var grpcFlutterPublicKey: ByteArray
        get() {
            val encoded = preferences.getString(SettingsKey.GRPC_FLUTTER_PUBLIC_KEY, null)
            return encoded?.let { Base64.decode(it, Base64.DEFAULT) } ?: ByteArray(0)
        }
        set(value) {
            val encoded = Base64.encodeToString(value, Base64.DEFAULT)
            preferences.edit().putString(SettingsKey.GRPC_FLUTTER_PUBLIC_KEY, encoded).apply()
        }
    // Loopback gRPC port for the BACKGROUND core — BoxService starts mode 4 on it.
    // Keep in step with CoreInterfaceMobile.portBack, which is where the reasoning
    // for moving off upstream's 17078/17079 lives.
    //
    // Two upstream problems fixed here:
    //
    //  * the default was 17078, the FRONT port. Harmless only because Dart sets
    //    this on every connect (MethodHandler.kt:120) before the service reads it;
    //    an on-demand start with the app never opened would have bound the wrong
    //    one.
    //  * a persisted value survives an app update, so a new default alone would be
    //    ignored on every existing install — silently keeping the collision with
    //    Hiddify that the new ports exist to remove. The legacy values are
    //    therefore treated as unset rather than honoured.
    private const val LEGACY_GRPC_PORT_FRONT = 17078
    private const val LEGACY_GRPC_PORT_BACK = 17079
    private const val DEFAULT_GRPC_PORT_BACK = 21979

    var grpcServiceModePort: Int
        get() {
            val stored = preferences.getInt(SettingsKey.GRPC_PORT, DEFAULT_GRPC_PORT_BACK)!!
            return if (stored == LEGACY_GRPC_PORT_FRONT || stored == LEGACY_GRPC_PORT_BACK) {
                DEFAULT_GRPC_PORT_BACK
            } else {
                stored
            }
        }
        set(value) = preferences.edit().putInt(SettingsKey.GRPC_PORT, value).apply()

    var startCoreAfterStartingService: Boolean
        get() = preferences.getBoolean(SettingsKey.START_CORE_ON_STARTING_SERVICE, false)
        set(value) = preferences.edit().putBoolean(SettingsKey.START_CORE_ON_STARTING_SERVICE, value).apply()


}

