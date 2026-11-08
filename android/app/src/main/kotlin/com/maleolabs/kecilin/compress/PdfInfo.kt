package com.maleolabs.kecilin.compress

import android.os.ParcelFileDescriptor
import java.io.File

class CompressCancelled : Exception("Kompresi dibatalkan")

data class CompressOutcome(
    val pages: Int,
    val note: String? = null
)

/**
 * Cheap metadata read. Uses the platform PdfRenderer so we do not pay the
 * cost of parsing the whole document.
 */
object PdfInfo {
    fun read(file: File): Map<String, Any?> {
        if (!file.exists()) error("File tidak ditemukan.")
        var descriptor: ParcelFileDescriptor? = null
        var renderer: android.graphics.pdf.PdfRenderer? = null
        return try {
            descriptor = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
            renderer = android.graphics.pdf.PdfRenderer(descriptor)
            mapOf(
                "pages" to renderer.pageCount,
                "bytes" to file.length(),
                "encrypted" to false
            )
        } catch (security: SecurityException) {
            mapOf(
                "pages" to 0,
                "bytes" to file.length(),
                "encrypted" to true,
                "note" to "PDF terkunci password."
            )
        } finally {
            runCatching { renderer?.close() }
            runCatching { descriptor?.close() }
        }
    }
}
