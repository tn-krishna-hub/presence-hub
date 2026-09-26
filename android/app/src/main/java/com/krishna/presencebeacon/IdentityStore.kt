package com.krishna.presencebeacon

import android.content.Context
import java.util.UUID

/**
 * Generates one identity per install. This UUID is the whole game:
 * the phone advertises it, the Mac scans for exactly it, so only this
 * phone can ever count as "you".
 */
class IdentityStore(context: Context) {

    private val prefs = context.getSharedPreferences("identity", Context.MODE_PRIVATE)

    fun uuid(): UUID {
        prefs.getString(KEY, null)?.let { stored ->
            runCatching { UUID.fromString(stored) }.getOrNull()?.let { return it }
        }
        val fresh = UUID.randomUUID()
        prefs.edit().putString(KEY, fresh.toString()).apply()
        return fresh
    }

    private companion object {
        const val KEY = "beacon_uuid"
    }
}