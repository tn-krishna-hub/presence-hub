package com.krishna.presencebeacon

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.UUID

class BeaconPackageTest {

    @Test
    fun legacyAdvPacketHasRoomForThe128BitServiceUuid() {
        assertTrue(AdvPacket.fitsLegacyPacket())
    }

    @Test
    fun packetIsNotSilentlyOversized() {
        // If this ever grows past 31 bytes, Android advertising fails at runtime.
        assertFalse(AdvPacket.totalBytes() > AdvPacket.LEGACY_PACKET_BUDGET)
    }

    @Test
    fun generatedIdentitySurvivesAStringRoundTrip() {
        val identity = UUID.randomUUID()
        val restored = UUID.fromString(identity.toString())
        assertEquals(identity, restored)
    }
}