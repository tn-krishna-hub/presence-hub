package com.krishna.presencebeacon

import android.content.Context

/** User-tunable beacon settings, persisted so the value survives service restarts. */
class BeaconSettingsStore(context: Context) {

    private val prefs = context.getSharedPreferences("settings", Context.MODE_PRIVATE)

    var txPower: BeaconAdvertiser.TxPower
        get() = BeaconAdvertiser.TxPower.from(prefs.getString(KEY_TX_POWER, null))
        set(value) {
            prefs.edit().putString(KEY_TX_POWER, value.name).apply()
        }

    private companion object {
        const val KEY_TX_POWER = "tx_power"
    }
}