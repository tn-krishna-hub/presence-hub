package com.krishna.presencebeacon

import android.bluetooth.le.AdvertiseCallback

/** Maps Android advertising failure codes to human-readable descriptions. */
object AdvertiseFailure {
    fun describe(code: Int): String = when (code) {
        AdvertiseCallback.ADVERTISE_FAILED_DATA_TOO_LARGE -> "data too large ($code)"
        AdvertiseCallback.ADVERTISE_FAILED_TOO_MANY_ADVERTISERS -> "too many advertisers ($code)"
        AdvertiseCallback.ADVERTISE_FAILED_ALREADY_STARTED -> "already started ($code)"
        AdvertiseCallback.ADVERTISE_FAILED_INTERNAL_ERROR -> "internal error ($code)"
        AdvertiseCallback.ADVERTISE_FAILED_FEATURE_UNSUPPORTED -> "feature unsupported ($code)"
        else -> "unknown error ($code)"
    }
}