package dev.dawnmesh.intercom

/** Shared DNS-SD TXT fields. Discovery metadata never authorizes a room join. */
internal object BonjourRoomMetadata {
    const val WIFI = "DAWN_MESH_DISCOVERY_V1"
    const val FUSION = "DAWN_MESH_FUSION_V1"

    fun serviceType(magic: String): String? = when (magic) {
        WIFI -> "_dawnmesh._tcp."
        FUSION -> "_dawnfusion._tcp."
        else -> null
    }

    fun text(value: String): String {
        // One DNS-SD TXT entry must fit in 255 bytes, including its key.
        val result = StringBuilder()
        var bytes = 0
        for (point in value.codePoints().toArray().take(64)) {
            val character = String(Character.toChars(point))
            val size = character.toByteArray(Charsets.UTF_8).size
            if (bytes + size > 180) break
            result.append(character)
            bytes += size
        }
        return result.toString()
    }

    fun room(fields: Map<String, String>, magic: String, address: String, resolvedPort: Int): Map<String, Any>? {
        if (serviceType(magic) == null || fields["magic"]?.let { it != magic } == true ||
            fields["roomId"].isNullOrBlank() || address.isBlank() || resolvedPort !in 1..65535) return null
        return mapOf(
            "type" to "room", "magic" to magic,
            "roomId" to text(fields.getValue("roomId")),
            "roomName" to text(fields["roomName"].orEmpty()),
            "hostNickname" to text(fields["hostNickname"].orEmpty()),
            "members" to (fields["members"]?.toIntOrNull() ?: 1).coerceIn(0, 99),
            "address" to address,
            // Apple's peer listener proxies to the Dart server. Its SRV port
            // can differ from the original TCP port carried in TXT.
            "port" to resolvedPort,
        )
    }
}
