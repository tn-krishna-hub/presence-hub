package com.krishna.presencebeacon

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.util.Log

/**
 * Foreground service that keeps the beacon advertising even when the app is
 * backgrounded and the screen is off.
 */
class BeaconService : Service() {

    private var advertiser: BeaconAdvertiser? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == Constants.ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }
        advertisingStatus = AdvertisingStatus.STARTING
        startForeground(Constants.NOTIFICATION_ID, buildNotification())
        startBeacon()
        return START_STICKY
    }

    private fun startBeacon() {
        val manager = runCatching {
            getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        }.getOrNull()
        val adapter = manager?.adapter
        val leAdvertiser = adapter?.bluetoothLeAdvertiser
        if (adapter == null || leAdvertiser == null || !adapter.isEnabled) {
            Log.w(TAG, "Bluetooth unavailable — stopping")
            advertisingStatus = AdvertisingStatus.UNAVAILABLE
            updateNotification(getString(R.string.notification_failed_bt))
            stopSelf()
            return
        }

        val identity = IdentityStore(this).uuid()
        val txPower = BeaconSettingsStore(this).txPower
        val advertiser = BeaconAdvertiser(leAdvertiser, object : BeaconAdvertiser.Listener {
            override fun onStartSuccess() {
                Log.i(TAG, "advertising started (txPower=$txPower)")
                advertisingStatus = AdvertisingStatus.BROADCASTING
                updateNotification(getString(R.string.notification_text))
            }

            override fun onStartFailure(errorCode: Int) {
                Log.w(TAG, "advertising failed: $errorCode")
                advertisingStatus = AdvertisingStatus.FAILED
                lastFailureCode = AdvertiseFailure.describe(errorCode)
                updateNotification(getString(R.string.notification_failed, lastFailureCode))
            }

            override fun onStopped() {
                Log.w(TAG, "advertising stopped")
                advertisingStatus = AdvertisingStatus.IDLE
                updateNotification(getString(R.string.notification_stopped))
            }
        })
        advertiser.start(identity, lowLatency = true, txPower = txPower)
        this.advertiser = advertiser
    }

    override fun onDestroy() {
        advertiser?.stop()
        advertiser = null
        super.onDestroy()
    }

    private fun updateNotification(text: String) {
        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(Constants.NOTIFICATION_ID, buildNotification(text))
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                Constants.CHANNEL_ID,
                "Beacon status",
                NotificationManager.IMPORTANCE_LOW
            ).apply { description = "Keeps the presence beacon running" }
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }

    private fun buildNotification(text: String = getString(R.string.notification_text)): Notification {
        val builder: Notification.Builder =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(this, Constants.CHANNEL_ID)
            } else {
                @Suppress("DEPRECATION") Notification.Builder(this)
            }
        return builder
            .setContentTitle(getString(R.string.notification_title))
            .setContentText(text)
            .setSmallIcon(android.R.drawable.stat_sys_data_bluetooth)
            .setOngoing(true)
            .build()
    }

    enum class AdvertisingStatus { IDLE, STARTING, BROADCASTING, FAILED, UNAVAILABLE }

    companion object {
        const val TAG = "PresenceBeacon"

        @Volatile
        var advertisingStatus: AdvertisingStatus = AdvertisingStatus.IDLE
            private set

        @Volatile
        var lastFailureCode: String = ""
            private set
    }
}