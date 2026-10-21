package de.dorfspy.schulpilot

import org.junit.Assert.*
import org.junit.Test

class FamilyCallPolicyTest {
    private val binding = "a".repeat(64)
    private val callId = "b".repeat(32)
    private val data = mapOf("type" to "family_call", "event" to "incoming",
        "call_id" to callId, "call_binding" to binding, "expires_at" to "140000")

    @Test fun validIncomingIsBoundAndLimited() {
        assertEquals(40_000L, FamilyCallPolicy.incoming(data, binding, 100_000L)!!.ringMillis)
        assertEquals(45_000L, FamilyCallPolicy.incoming(data + ("expires_at" to "160000"), binding, 100_000L)!!.ringMillis)
    }

    @Test fun differentAccountAndNoOptInNeverRing() {
        assertNull(FamilyCallPolicy.incoming(data, null, 100_000L))
        assertNull(FamilyCallPolicy.incoming(data, "c".repeat(64), 100_000L))
        assertNull(FamilyCallPolicy.incoming(data - "call_binding", binding, 100_000L))
    }

    @Test fun expiredMalformedAndArbitraryLinksNeverRing() {
        assertNull(FamilyCallPolicy.incoming(data, binding, 140_000L))
        assertNull(FamilyCallPolicy.incoming(data + ("expires_at" to "999999999"), binding, 100_000L))
        assertNull(FamilyCallPolicy.incoming(data + ("call_id" to "https://example.invalid"), binding, 100_000L))
        assertNull(FamilyCallPolicy.incoming(data + ("event" to "ended"), binding, 100_000L))
    }

    @Test fun mediaIsNotANotificationAction() {
        assertTrue(FamilyCallPolicy.validAction("answer"))
        assertTrue(FamilyCallPolicy.validAction("decline"))
        assertFalse(FamilyCallPolicy.validAction("startCamera"))
    }

    @Test fun oldCleanupCannotStopANewerOrPendingCall() {
        val next = "c".repeat(32)
        assertFalse(FamilyCallPolicy.mayStop(callId, next, null))
        assertFalse(FamilyCallPolicy.mayStop(callId, callId, next))
        assertTrue(FamilyCallPolicy.mayStop(next, callId, next))
        assertTrue(FamilyCallPolicy.mayStop(null, next, null))
    }

    @Test fun downgradedPushCannotStartABackgroundService() {
        assertTrue(FamilyCallPolicy.highPriority("high", null, "high"))
        assertFalse(FamilyCallPolicy.highPriority("normal", null, "high"))
        assertFalse(FamilyCallPolicy.highPriority(null, "1", "high"))
        assertFalse(FamilyCallPolicy.highPriority(null, null, null))
    }
}
