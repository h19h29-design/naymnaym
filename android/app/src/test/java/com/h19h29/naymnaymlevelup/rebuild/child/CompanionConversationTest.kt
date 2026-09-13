package com.h19h29.naymnaymlevelup.rebuild.child

import org.junit.Assert.*
import org.junit.Test

class CompanionConversationTest {
    @Test fun everyTopicProducesAUserAndCharacterTurn() {
        CompanionTopic.entries.forEach { topic ->
            val result = CompanionConversation().respond(topic, 7)
            assertEquals(2, result.messages.size)
            assertTrue(result.messages[0].isUser)
            assertFalse(result.messages[1].isUser)
            assertEquals(topic.title, result.messages[0].text)
            assertTrue(result.messages[1].text.isNotBlank())
        }
        assertTrue(CompanionTopic.Growth.reply(0, 7).contains("레벨 7"))
        assertTrue(CompanionTopic.Growth.reply(0, 7).contains("경험치가 바뀌지는 않아"))
    }
    @Test fun allergyAlwaysDefersToAnAdult() {
        (0..5).forEach {
            val reply = CompanionTopic.Allergy.reply(it, 1)
            assertTrue(reply.contains("먹어 보지 말고"))
            assertTrue(reply.contains("보호자나 선생님"))
            assertTrue(reply.contains("안전한지 판단할 수 없어"))
        }
    }
    @Test fun conversationIsBoundedAndNewSessionsAreEmpty() {
        var conversation = CompanionConversation()
        repeat(30) { conversation = conversation.respond(CompanionTopic.Hello, 1) }
        assertEquals(12, conversation.messages.size)
        assertEquals(30, conversation.turn)
        assertTrue(CompanionConversation().messages.isEmpty())
        assertNotEquals(CompanionTopic.Hello.reply(0, 1), CompanionTopic.Hello.reply(1, 1))
    }
}
