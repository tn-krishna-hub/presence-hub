package com.krishna.presencebeacon

import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.BluetoothLeAdvertiser
import android.os.ParcelUuid
import java.util.UUID

/**
 * Thin wrapper around [BluetoothLeAdvertiser] that emits a non-connectable
 * service-UUID beacon. Non-connectable means macOS's CoreBluetooth scanner
 * (with AllowDuplicates) keeps seeing fresh RSSI samples instead of treating
 * our phone as a connectable peripheral it must pair with.
 */
class BeaconAdvertiser(
    private val advertiser: BluetoothLeAdvertiser,
    private val listener: Listener
) {

    enum class TxPower(val advertiseConstant: Int, val label: String) {
        LOW(AdvertiseSettings.ADVERTISE_TX_POWER_LOW, "Low"),
        MEDIUM(AdvertiseSettings.ADVERTISE_TX_POWER_MEDIUM, "Medium"),
        HIGH(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH, "High");

        companion object {
            fun from(name: String?): TxPower =
                entries.firstOrNull { it.name == name } ?: LOW
        }
    }

    interface Listener {
        fun onStartSuccess()
        fun onStartFailure(errorCode: Int)
        fun onStopped()
    }

    val isRunning: Boolean
        get() = running

    private var running = false

    private val callback = object : AdvertiseCallback() {
        override fun onStartSuccess(settingsInEffect: AdvertiseSettings) {
            running = true
            listener.onStartSuccess()
        }

        override fun onStartFailure(errorCode: Int) {
            running = false
            listener.onStartFailure(errorCode)
        }
    }

    fun start(identity: UUID, lowLatency: Boolean = true, txPower: TxPower = TxPower.LOW) {
        stop()
        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(
                if (lowLatency) AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY
                else AdvertiseSettings.ADVERTISE_MODE_LOW_POWER
            )
            .setTxPowerLevel(txPower.advertiseConstant)
            .setConnectable(false)
            .build()
        val data = AdvertiseData.Builder()
            .setIncludeDeviceName(false)
            .addServiceUuid(ParcelUuid(identity))
            .build()

        try {
            advertiser.startAdvertising(settings, data, callback)
        } catch (_: Exception) {
            running = false
            listener.onStartFailure(AdvertiseCallback.ADVERTISE_FAILED_INTERNAL_ERROR)
        }
    }

    fun stop() {
        if (running) advertiser.stopAdvertising(callback)
        running = false
    }
}