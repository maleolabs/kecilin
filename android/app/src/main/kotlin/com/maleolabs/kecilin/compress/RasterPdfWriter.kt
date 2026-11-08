package com.maleolabs.kecilin.compress

import java.io.BufferedOutputStream
import java.io.File
import java.io.OutputStream
import java.nio.charset.StandardCharsets
import java.util.Locale

/**
 * Minimal, deterministic PDF writer for rasterised pages.
 *
 * Every page becomes a single DCTDecode (JPEG) image stretched to the original
 * page box. Pages are streamed to disk one at a time so memory stays flat.
 *
 * Layout: 1 = Catalog, 2 = Pages, then 3 objects per page (Page, Contents, Image).
 */
internal class RasterPdfWriter(private val file: File) {

    private val offsets = mutableListOf<Long>()
    private var position = 0L
    private lateinit var out: OutputStream

    fun open(pageCount: Int) {
        file.parentFile?.mkdirs()
        out = BufferedOutputStream(file.outputStream(), 1 shl 16)
        val header = "%PDF-1.7\n%\u00E2\u00E3\u00CF\u00D3\n".toByteArray(StandardCharsets.ISO_8859_1)
        out.write(header)
        position += header.size

        writeObject(1) { ascii("<< /Type /Catalog /Pages 2 0 R >>") }
        val kids = buildString {
            repeat(pageCount) { index ->
                if (index > 0) append(' ')
                append("${3 + index * 3} 0 R")
            }
        }
        writeObject(2) { ascii("<< /Type /Pages /Count $pageCount /Kids [$kids] >>") }
    }

    fun addPage(
        index: Int,
        widthPt: Int,
        heightPt: Int,
        pixelWidth: Int,
        pixelHeight: Int,
        jpeg: ByteArray
    ) {
        val pageObj = 3 + index * 3
        val contentObj = pageObj + 1
        val imageObj = pageObj + 2

        writeObject(pageObj) {
            ascii(
                "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 $widthPt $heightPt] " +
                    "/Resources << /XObject << /Im0 $imageObj 0 R >> >> " +
                    "/Contents $contentObj 0 R >>"
            )
        }

        val content = buildString {
            append("q\n")
            append("$widthPt 0 0 $heightPt 0 0 cm\n")
            append("/Im0 Do\n")
            append("Q\n")
        }.toByteArray(StandardCharsets.US_ASCII)

        writeObject(contentObj) {
            ascii("<< /Length ${content.size} >>\nstream\n")
            bytes(content)
            ascii("\nendstream")
        }

        writeObject(imageObj) {
            ascii(
                "<< /Type /XObject /Subtype /Image /Width $pixelWidth /Height $pixelHeight " +
                    "/ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode " +
                    "/Length ${jpeg.size} >>\nstream\n"
            )
            bytes(jpeg)
            ascii("\nendstream")
        }
    }

    fun close() {
        val xrefStart = position
        val count = offsets.size + 1
        val builder = StringBuilder()
        builder.append("xref\n0 $count\n")
        builder.append("0000000000 65535 f \n")
        offsets.forEach { offset ->
            builder.append(String.format(Locale.ROOT, "%010d 00000 n \n", offset))
        }
        builder.append("trailer\n<< /Size $count /Root 1 0 R >>\nstartxref\n$xrefStart\n%%EOF\n")
        out.write(builder.toString().toByteArray(StandardCharsets.US_ASCII))
        out.flush()
        out.close()
    }

    fun abort() {
        runCatching { out.close() }
        runCatching { file.delete() }
    }

    private fun writeObject(id: Int, body: ByteSink.() -> Unit) {
        while (offsets.size < id) offsets.add(0L)
        val buffer = java.io.ByteArrayOutputStream(512)
        BufferSink(buffer).body()
        val payload = buffer.toByteArray()

        val head = "$id 0 obj\n".toByteArray(StandardCharsets.US_ASCII)
        val tail = "\nendobj\n".toByteArray(StandardCharsets.US_ASCII)
        offsets[id - 1] = position
        out.write(head)
        out.write(payload)
        out.write(tail)
        position += head.size + payload.size + tail.size
    }

    private fun ByteSink.ascii(text: String) = write(text.toByteArray(StandardCharsets.ISO_8859_1))
    private fun ByteSink.bytes(data: ByteArray) = write(data)

    private interface ByteSink {
        fun write(data: ByteArray)
    }

    private class BufferSink(private val buffer: java.io.ByteArrayOutputStream) : ByteSink {
        override fun write(data: ByteArray) = buffer.write(data, 0, data.size)
    }
}
