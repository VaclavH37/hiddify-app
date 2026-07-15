package com.raynlabs.app.bg

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.util.Log
import androidx.annotation.StringRes
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.lifecycle.MutableLiveData
import com.raynlabs.core.api.v2.config.Protocol
import com.raynlabs.core.api.v2.hcommon.Empty
import com.raynlabs.core.api.v2.hcore.CoreClient
import com.raynlabs.core.api.v2.hcore.SystemInfo
import com.raynlabs.core.api.v2.hello.HelloClient
import com.raynlabs.core.api.v2.hello.HelloRequest
import com.raynlabs.app.Application
import com.raynlabs.app.MainActivity
import com.raynlabs.app.R
import com.raynlabs.app.Settings
import com.raynlabs.app.constant.Action
import com.raynlabs.app.constant.Status
//import com.raynlabs.app.utils.CommandClient
import com.raynlabs.core.libbox.Libbox
import com.raynlabs.app.Application.Companion.notification
import com.raynlabs.app.utils.GrpcClientProvider
import com.squareup.wire.GrpcClient
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.isActive

import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.channels.ReceiveChannel
import kotlinx.coroutines.channels.SendChannel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import java.io.IOException
import kotlinx.coroutines.delay
import kotlinx.coroutines.CancellationException
class ServiceNotification(private val status: MutableLiveData<Status>, private val service: Service) : BroadcastReceiver(){
    companion object {
        private const val notificationId = 1
        private const val notificationChannel = "service"
        var coreClient: CoreClient?=null

        // Regexes mirroring lib/features/proxy/model/node_name.dart. One or more
        // trailing country-flag emoji (pairs of Regional Indicator Symbols) plus
        // surrounding whitespace; the core→detour separator ("→" or "->"); and a
        // 2-letter country code.
        private val trailingFlagPattern = Regex("\\s*(?:[\\x{1F1E6}-\\x{1F1FF}]{2}\\s*)+$")
        private val detourSeparator = Regex("\\s*(?:→|->)\\s*")
        private val countryCodePattern = Regex("^[A-Za-z]{2}$")
        val flags =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0

        fun checkPermission(): Boolean {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
                return true
            }
            return Application.notification.areNotificationsEnabled()
        }
    }
    val streamingCoroutineScope = CoroutineScope(Dispatchers.IO + SupervisorJob())


//
//    private val commandClient =
//            CommandClient(GlobalScope, CommandClient.ConnectionType.Status, this)
    private var receiverRegistered = false


    private val notificationBuilder by lazy {
        NotificationCompat.Builder(service, notificationChannel)
                .setShowWhen(false)
                .setOngoing(true)
                .setContentTitle("Rayn VPN")
                .setOnlyAlertOnce(true)
                .setSmallIcon(R.drawable.ic_stat_logo)
                .setCategory(NotificationCompat.CATEGORY_SERVICE)
                .setContentIntent(
                        PendingIntent.getActivity(
                                service,
                                0,
                                Intent(
                                        service,
                                        MainActivity::class.java
                                ).setFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT),
                                flags
                        )
                )
                .setPriority(NotificationCompat.PRIORITY_LOW).apply {
                    addAction(
                            NotificationCompat.Action.Builder(
                                    0, service.getText(R.string.stop), PendingIntent.getBroadcast(
                                    service,
                                    0,
                                    Intent(Action.SERVICE_CLOSE).setPackage(
                                        Application.application.packageName
                                    ),
                                    flags
                            )
                            ).build()
                    )
                }
    }

    fun show(profileName: String, @StringRes contentTextId: Int) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Application.notification.createNotificationChannel(
                NotificationChannel(
                    notificationChannel, "Rayn VPN service", NotificationManager.IMPORTANCE_LOW
                )
            )
        }
        service.startForeground(
            notificationId, notificationBuilder
                .setContentTitle(profileName.takeIf { it.isNotBlank() } ?: "Rayn VPN")
                .setContentText(service.getString(contentTextId)).build()
        )
    }


    suspend fun start() {
        if (Settings.dynamicNotification && checkPermission()) {
//            commandClient.connect()
            startListenSystemInfo()
            withContext(Dispatchers.Main) {
                registerReceiver()
            }
        }
    }

    private fun registerReceiver() {
        service.registerReceiver(this, IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_SCREEN_OFF)
        })
        receiverRegistered = true
    }

    fun updateStatus(previous:SystemInfo,status: SystemInfo) {
        val uplink=status.uplink_total - previous.uplink_total
        val downlink=status.downlink_total - previous.downlink_total
        val content = "${Libbox.formatBytes(uplink)}/s ↑\t${Libbox.formatBytes(downlink)}/s ↓ \n${prettifyOutbound(status.current_outbound)}"
        val title = "${status.current_profile}"
        Application.notificationManager.notify(
                notificationId,
                notificationBuilder.setContentTitle(title).setContentText(content).build()
        )
    }

    // Port of the Flutter proxy list's prettifyNodeName
    // (lib/features/proxy/model/node_name.dart) so the notification shows the same
    // "City, CC" label the in-app list does (e.g. "EXIT-SK-SEOUL-01🇰🇷" -> "Seoul, SK").
    // The core reports the whole selector chain (e.g. "lowest → EXIT-SK-SEOUL-01"),
    // so we scan every detour hop and use the first that matches the convention.
    private fun prettifyOutbound(tag: String): String {
        for (hop in tag.split(detourSeparator)) {
            prettifyHop(hop)?.let { return it }
        }
        // No hop matched — fall back to the raw tag with any trailing flag stripped.
        return stripTrailingFlag(tag).ifBlank { tag }
    }

    // Converts a single "HUB-<CC>-<CITY…>-<id>" / "EXIT-<CC>-<CITY…>-<id>[flag]" hop
    // into "City, CC", or null when it doesn't fit the convention.
    private fun prettifyHop(hop: String): String? {
        val parts = stripTrailingFlag(hop).split("-")
        // Need at least: <prefix> - <cc> - <city…> - <id>.
        if (parts.size < 4) return null
        val prefix = parts.first().uppercase()
        if (prefix != "HUB" && prefix != "EXIT") return null
        val countryCode = parts[1]
        if (!countryCodePattern.matches(countryCode)) return null
        // Everything between the country code and the trailing id is the city, which
        // may span multiple hyphen-separated segments (e.g. "NEW-YORK" -> "New York").
        val citySegments = parts.subList(2, parts.size - 1).filter { it.isNotEmpty() }
        if (citySegments.isEmpty()) return null
        val city = citySegments.joinToString(" ") { titleCase(it) }
        return "$city, ${countryCode.uppercase()}"
    }

    private fun stripTrailingFlag(name: String): String =
        trailingFlagPattern.replace(name, "").trim()

    private fun titleCase(word: String): String =
        word.first().uppercase() + word.substring(1).lowercase()

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_SCREEN_ON -> {
                startListenSystemInfo()
            }

            Intent.ACTION_SCREEN_OFF -> {
                stopListenSystemInfo()
            }
        }
    }

    fun close() {
        stopListenSystemInfo()
        ServiceCompat.stopForeground(service, ServiceCompat.STOP_FOREGROUND_REMOVE)
        if (receiverRegistered) {
            service.unregisterReceiver(this)
            receiverRegistered = false
        }
    }

    private var streamingJob: Job? = null

    fun startListenSystemInfo() {
        // Cancel any previous stream if still running
        Log.d("notification","startListenSystemInfo")
        streamingJob?.cancel()

        streamingJob = streamingCoroutineScope.launch(Dispatchers.IO) {
            Log.d("notification", "startListenSystemInfo-launch")

            val coreClient = GrpcClientProvider.grpcClient.create(CoreClient::class)

            try {
                var previous = coreClient.GetSystemInfo().executeBlocking(Empty())

                while (isActive) {
                    delay(1_000) // ✅ coroutine-friendly
                    val current = coreClient.GetSystemInfo().executeBlocking(Empty())
                    updateStatus(previous,current)
                    previous = current
                }
            } catch (e: CancellationException) {
                // coroutine cancelled normally
                Log.d("notification", "SystemInfo polling cancelled")
                notification.cancel(notificationId)
            } catch (e: Exception) {
                Log.e("notification", "SystemInfo polling failed", e)
                notification.cancel(notificationId)
            }
        }
    }
    fun stopListenSystemInfo(){
        try {
            streamingJob?.cancel()
        }catch (e: Exception){
            Log.d("notification", "Exception ${e}")
        }
    }
}