package de.dorfspy.schulpilot

/** Small transport policy. A push is a wake-up hint, never media consent. */
object FamilyCallPolicy {
    private val idPattern = Regex("^[a-f0-9]{32}$")
    private val bindingPattern = Regex("^[a-f0-9]{64}$")
    const val MAX_RING_MILLIS = 45_000L

    data class Incoming(val callId: String, val expiresAt: Long, val ringMillis: Long)

    fun validId(value: String?) = value != null && idPattern.matches(value)
    fun validBinding(value: String?) = value != null && bindingPattern.matches(value)
    fun validAction(value: String?) = value in setOf("open", "answer", "decline")
    fun mayStop(requested: String?, active: String?, pending: String?) =
        requested == null || (validId(requested) && requested == (pending ?: active))
    fun highPriority(delivered: String?, reduced: String?, original: String?) =
        if (delivered != null) delivered == "high" else reduced != "1" && original == "high"

    fun matches(data: Map<String, String>, binding: String?): Boolean =
        validBinding(binding) && data["type"] == "family_call" && data["call_binding"] == binding

    fun incoming(data: Map<String, String>, binding: String?, current: Long): Incoming? {
        if (!matches(data, binding) || data["event"] != "incoming") return null
        val callId = data["call_id"] ?: return null
        val expires = data["expires_at"]?.toLongOrNull() ?: return null
        if (!validId(callId) || expires <= current || expires > current + 60_000L) return null
        return Incoming(callId, expires, (expires - current).coerceAtMost(MAX_RING_MILLIS))
    }
}
