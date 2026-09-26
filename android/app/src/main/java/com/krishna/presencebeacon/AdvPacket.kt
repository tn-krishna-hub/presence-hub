package com.krishna.presencebeacon

/**
 * Packet-budget model for the legacy (non-extended) BLE advertising packet.
 * Kept dependency-free so the constraint is covered by a plain JVM unit test.
 *
 * Standard legacy advertisement body budget: 31 bytes.
 * Our payload: 2-byte flags AD + 2-byte AD header + 16-byte service UUID.
 */
object AdvPacket {
    const val FLAGS_AND_HEADER_BYTES = 4
    const val SERVICE_UUID_128_BYTES = 18
    const val LEGACY_PACKET_BUDGET = 31

    fun totalBytes(): Int = FLAGS_AND_HEADER_BYTES + SERVICE_UUID_128_BYTES

    fun fitsLegacyPacket(): Boolean = totalBytes() <= LEGACY_PACKET_BUDGET
}