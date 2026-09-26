package dev.dawnmesh.intercom

/** One channel contract for both connection events and explicit state queries. */
internal fun wifiConnectionState(
    formed: Boolean,
    owner: Boolean,
    address: String,
): Map<String, Any> = mapOf(
    "isConnected" to formed,
    "groupFormed" to formed,
    "isGroupOwner" to owner,
    "groupOwnerAddress" to address,
)
