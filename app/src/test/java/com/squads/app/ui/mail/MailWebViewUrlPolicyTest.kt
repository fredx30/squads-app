package com.squads.app.ui.mail

import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class MailWebViewUrlPolicyTest {
    @Test
    fun `isGraphImageUrl accepts https graph host`() {
        val url = "https://graph.microsoft.com/v1.0/me/messages/abc/attachments/def/\$value"
        assertTrue(isGraphImageUrl(url))
    }

    @Test
    fun `isGraphImageUrl accepts uppercase graph host`() {
        assertTrue(isGraphImageUrl("https://GRAPH.Microsoft.com/v1.0/me/photo/\$value"))
    }

    @Test
    fun `isGraphImageUrl rejects graph host in path`() {
        assertFalse(isGraphImageUrl("https://attacker.example/graph.microsoft.com.png"))
    }

    @Test
    fun `isGraphImageUrl rejects graph host as subdomain prefix`() {
        assertFalse(isGraphImageUrl("https://graph.microsoft.com.attacker.example/"))
    }

    @Test
    fun `isGraphImageUrl rejects graph host in query`() {
        assertFalse(isGraphImageUrl("https://evil.com/?x=graph.microsoft.com"))
    }

    @Test
    fun `isGraphImageUrl rejects plain http`() {
        assertFalse(isGraphImageUrl("http://graph.microsoft.com/"))
    }

    @Test
    fun `isGraphImageUrl rejects graph host as userinfo`() {
        assertFalse(isGraphImageUrl("https://graph.microsoft.com@attacker.example/"))
    }

    @Test
    fun `isGraphImageUrl rejects teams host`() {
        assertFalse(isGraphImageUrl("https://teams.microsoft.com/"))
    }

    @Test
    fun `isGraphImageUrl rejects unparseable and non-http urls`() {
        assertFalse(isGraphImageUrl(""))
        assertFalse(isGraphImageUrl("cid:image001.png"))
        assertFalse(isGraphImageUrl("data:image/png;base64,AAAA"))
    }

    @Test
    fun `hasRemoteImages detects double quoted https src`() {
        assertTrue(hasRemoteImages("""<p>Hi</p><img src="https://tracker.example/p.gif">"""))
    }

    @Test
    fun `hasRemoteImages detects single quoted and unquoted http src`() {
        assertTrue(hasRemoteImages("<img width=1 src='http://tracker.example/p.gif'>"))
        assertTrue(hasRemoteImages("<IMG SRC=http://tracker.example/p.gif>"))
    }

    @Test
    fun `hasRemoteImages ignores inline data and cid sources`() {
        assertFalse(hasRemoteImages("""<img src="data:image/png;base64,AAAA">"""))
        assertFalse(hasRemoteImages("""<img src="cid:image001.png@01D">"""))
    }

    @Test
    fun `hasRemoteImages ignores graph urls`() {
        val html = """<img src="https://graph.microsoft.com/v1.0/me/photo/${'$'}value">"""
        assertFalse(hasRemoteImages(html))
    }

    @Test
    fun `hasRemoteImages ignores links and plain text urls`() {
        val html = """<a href="https://example.com">https://example.com/img.png</a>"""
        assertFalse(hasRemoteImages(html))
    }

    @Test
    fun `hasRemoteImages finds remote src after a graph src`() {
        val html =
            """<img src="https://graph.microsoft.com/x"><img src="https://tracker.example/p">"""
        assertTrue(hasRemoteImages(html))
    }

    @Test
    fun `isAllowedExternalLinkScheme allows http https and mailto`() {
        assertTrue(isAllowedExternalLinkScheme("http"))
        assertTrue(isAllowedExternalLinkScheme("HTTPS"))
        assertTrue(isAllowedExternalLinkScheme("mailto"))
    }

    @Test
    fun `isAllowedExternalLinkScheme rejects other schemes`() {
        assertFalse(isAllowedExternalLinkScheme("intent"))
        assertFalse(isAllowedExternalLinkScheme("javascript"))
        assertFalse(isAllowedExternalLinkScheme("file"))
        assertFalse(isAllowedExternalLinkScheme("content"))
        assertFalse(isAllowedExternalLinkScheme(null))
    }
}
