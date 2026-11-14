package com.raynlabs.app

import android.annotation.SuppressLint
import android.content.Intent
import android.Manifest
import android.content.pm.ActivityInfo
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.net.VpnService
import android.os.Build
import android.os.Bundle
import android.util.Log
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.MutableLiveData
import androidx.lifecycle.lifecycleScope
import com.raynlabs.app.bg.ServiceConnection
import com.raynlabs.app.bg.ServiceNotification
import com.raynlabs.app.billing.RaynBillingHandler
import com.raynlabs.app.constant.Alert
import com.raynlabs.app.constant.ServiceMode
import com.raynlabs.app.constant.Status
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.LinkedList


class MainActivity : FlutterFragmentActivity(), ServiceConnection.Callback {
    companion object {
        private const val TAG = "ANDROID/MyActivity"
        lateinit var instance: MainActivity

        const val VPN_PERMISSION_REQUEST_CODE = 1001
        const val NOTIFICATION_PERMISSION_REQUEST_CODE = 1010
    }

    private val connection = ServiceConnection(this, this)

    val logList = LinkedList<String>()
    var logCallback: ((Boolean) -> Unit)? = null
    val serviceStatus = MutableLiveData(Status.Stopped)
    val serviceAlerts = MutableLiveData<ServiceEvent?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        applyOrientationPolicy()
        super.onCreate(savedInstanceState)
        // After super: FlutterFragmentActivity.onCreate tints the status bar
        // below API 35 and would undo this. Draws behind both system bars on
        // every version, as Android 15+ already forces; the Dart side keeps
        // content clear of them and sets only icon brightness.
        enableEdgeToEdge()
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        // Folding or unfolding a foldable moves the display across 600dp.
        applyOrientationPolicy()
    }

    /**
     * Phones stay portrait; displays at least 600dp on their shorter side
     * (tablets, unfolded foldables, ChromeOS) rotate freely. Android 16 ignores
     * an orientation lock on those displays anyway, and Play flags a lock in
     * the manifest. Measured on the display rather than the window, so a
     * narrow split-screen or desktop window on a tablet is not locked.
     */
    private fun applyOrientationPolicy() {
        val wanted = if (displaySmallestWidthDp() >= 600) {
            ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
        } else {
            ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
        }
        if (requestedOrientation != wanted) requestedOrientation = wanted
    }

    private fun displaySmallestWidthDp(): Int {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val bounds = windowManager.maximumWindowMetrics.bounds
            return (minOf(bounds.width(), bounds.height()) / resources.displayMetrics.density).toInt()
        }
        return resources.configuration.smallestScreenWidthDp
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        instance = this
        reconnect()
        flutterEngine.plugins.add(MethodHandler(lifecycleScope))
        flutterEngine.plugins.add(PlatformSettingsHandler())
        flutterEngine.plugins.add(EventHandler())
        flutterEngine.plugins.add(LogHandler())
        flutterEngine.plugins.add(RaynBillingHandler())
//        flutterEngine.plugins.add(GroupsChannel(lifecycleScope))
//        flutterEngine.plugins.add(ActiveGroupsChannel(lifecycleScope))
//        flutterEngine.plugins.add(StatsChannel(lifecycleScope))
    }

    fun reconnect() {
        connection.reconnect()
    }

    // The start that is still waiting on a permission dialog. Every path that ends
    // a start completes it exactly once: true once the service has been asked to
    // start, false once it cannot (the reason goes out separately as a service
    // alert). Main thread only.
    //
    // A start that is never completed would leave every later connect waiting on
    // it, so besides the dialog outcomes it is also completed when preparing
    // throws, when starting the service throws, and in onDestroy.
    private var pendingStart: CompletableDeferred<Boolean>? = null

    /**
     * Returns only after the permission dialogs are answered: true if the service
     * was asked to start. The app's wait for the service begins when this
     * returns, so on a fresh install it no longer runs out behind the dialogs.
     */
    @SuppressLint("NewApi")
    suspend fun startService(): Boolean = withContext(Dispatchers.Main) {
        // A second start while the dialogs are open waits for them instead of
        // opening more.
        pendingStart?.let { return@withContext it.await() }
        val start = CompletableDeferred<Boolean>().also { pendingStart = it }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && !ServiceNotification.checkPermission()) {
            notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
        } else {
            startService0()
        }
        start.await()
    }

    private fun finishStart(started: Boolean) {
        pendingStart?.complete(started)
        pendingStart = null
    }

    private fun startService0() {
        lifecycleScope.launch(Dispatchers.IO) {
            try {
                if (Settings.rebuildServiceMode()) {
                    connection.reconnect()
                }
                if (Settings.serviceMode == ServiceMode.VPN) {
                    // The VPN dialog is open (its callback finishes the start), or
                    // preparing failed (prepare finished it).
                    if (prepare()) {
                        return@launch
                    }
                }
                val intent = Intent(Application.application, Settings.serviceClass())
                withContext(Dispatchers.Main) {
                    ContextCompat.startForegroundService(this@MainActivity, intent)
                    finishStart(true)
                }
            } catch (e: Exception) {
                if (e is kotlinx.coroutines.CancellationException) throw e
                withContext(Dispatchers.Main) {
                    onServiceAlert(Alert.StartService, e.message)
                    finishStart(false)
                }
            }
        }
    }

    private suspend fun prepare() = withContext(Dispatchers.Main) {
        try {
            val intent = VpnService.prepare(this@MainActivity)
            if (intent != null) {
                prepareLauncher.launch(intent)
                true
            } else {
                false
            }
        } catch (e: Exception) {
            onServiceAlert(Alert.RequestVPNPermission, e.message)
            finishStart(false)
            true
        }
    }
    private val notificationPermissionLauncher =
        registerForActivityResult(
            ActivityResultContracts.RequestPermission(),
        ) { isGranted ->
            if (Settings.dynamicNotification && !isGranted) {
                onServiceAlert(Alert.RequestNotificationPermission, null)
                finishStart(false)
            } else {
                startService0()
            }
        }

    private val prepareLauncher =
        registerForActivityResult(
            ActivityResultContracts.StartActivityForResult(),
        ) { result ->
            if (result.resultCode == RESULT_OK) {
                startService0()
            } else {
                onServiceAlert(Alert.RequestVPNPermission, null)
                finishStart(false)
            }
        }

    override fun onServiceStatusChanged(status: Status) {
        serviceStatus.postValue(status)
    }

    override fun onServiceAlert(type: Alert, message: String?) {
        serviceAlerts.postValue(ServiceEvent(Status.Stopped, type, message))
    }




    override fun onDestroy() {
        // A start still waiting on a dialog cannot finish now; answer it rather
        // than leave the caller (and every later start) waiting.
        finishStart(false)
        connection.disconnect()
        super.onDestroy()
    }

    @SuppressLint("NewApi")
    private fun grantNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                NOTIFICATION_PERMISSION_REQUEST_CODE
            )
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        if (requestCode == NOTIFICATION_PERMISSION_REQUEST_CODE) {
            if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                lifecycleScope.launch { startService() }
            } else onServiceAlert(Alert.RequestNotificationPermission, null)
        }
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == VPN_PERMISSION_REQUEST_CODE) {
            if (resultCode == RESULT_OK) lifecycleScope.launch { startService() }
            else onServiceAlert(Alert.RequestVPNPermission, null)
        } else if (requestCode == NOTIFICATION_PERMISSION_REQUEST_CODE) {
            if (resultCode == RESULT_OK) lifecycleScope.launch { startService() }
            else onServiceAlert(Alert.RequestNotificationPermission, null)
        }
    }
}
