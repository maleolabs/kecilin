package com.maleolabs.kecilin.compress

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.util.Base64

/**
 * Structural check for the hand-written PDF writer. Renders nothing; it only
 * verifies the byte layout is a valid PDF that any viewer can open.
 */
class RasterPdfWriterTest {

    private val jpeg: ByteArray = Base64.getDecoder().decode(
        "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAYEBQYFBAYGBQYHBwYIChAKCgkJChQODwwQFxQYGBcUFhYaHSUfGhsjHBYWICwgIyYnKSopGR8tMC0oMCUoKSj/2wBDAQcHBwoIChMKChMoGhYaKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCj/wAARCAAQABADASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAb/xAAYEAACAwAAAAAAAAAAAAAAAAAAFAFRYf/EABUBAQEAAAAAAAAAAAAAAAAAAAQG/8QAFxEBAAMAAAAAAAAAAAAAAAAAABQVYf/aAAwDAQACEQMRAD8Ah25sNzZPN6G9ARlXda//2Q=="
    )

    @Test
    fun writesAWellFormedTwoPageDocument() {
        val output = File("build/test-artifacts/raster-sample.pdf")
        output.parentFile?.mkdirs()

        RasterPdfWriter(output).apply {
            open(2)
            addPage(0, 595, 842, 16, 16, jpeg)
            addPage(1, 842, 595, 16, 16, jpeg)
            close()
        }

        val bytes = output.readBytes()
        val text = String(bytes, Charsets.ISO_8859_1)

        assertTrue("missing header", text.startsWith("%PDF-1.7"))
        assertTrue("missing EOF", text.trimEnd().endsWith("%%EOF"))
        assertTrue("catalog missing", text.contains("/Type /Catalog"))
        assertTrue("page count missing", text.contains("/Count 2"))
        assertEquals("expected 8 objects (catalog, pages, 2x3)", 8, countObjects(text))

        // Every xref offset must point at the matching "N 0 obj" header.
        val offsets = xrefOffsets(text)
        assertEquals(8, offsets.size)
        offsets.forEachIndexed { index, offset ->
            val expected = "${index + 1} 0 obj"
            assertTrue(
                "xref entry ${index + 1} points at ${offset}: '${text.substring(offset, minOf(offset + expected.length, text.length))}'",
                text.startsWith(expected, offset)
            )
        }

        val startxref = Regex("startxref\\s+(\\d+)").find(text)!!.groupValues[1].toInt()
        assertTrue("startxref must point at the xref table", text.startsWith("xref", startxref))
        assertTrue("xref must be inside the file", startxref < bytes.size)
    }

    private fun countObjects(text: String): Int =
        Regex("(?m)^\\d+ 0 obj$").findAll(text).count()

    private fun xrefOffsets(text: String): List<Int> {
        val table = text.substringAfter("xref\n0 ").substringBefore("trailer")
        return table.lines()
            .drop(1)
            .mapNotNull { line ->
                val match = Regex("^(\\d{10}) (\\d{5}) ([nf])").find(line.trim()) ?: return@mapNotNull null
                if (match.groupValues[3] == "n") match.groupValues[1].toInt() else null
            }
    }
}
