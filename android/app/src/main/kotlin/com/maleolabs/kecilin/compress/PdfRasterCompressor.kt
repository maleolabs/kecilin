package com.maleolabs.kecilin.compress

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import java.io.ByteArrayOutputStream
import java.io.File
import kotlin.math.max
import kotlin.math.roundToInt

/**
 * "Agresif" mode: every page is rendered to a bitmap and re-embedded as JPEG.
 *
 * Text stops being selectable, but the size becomes predictable and we can
 * guarantee a hard byte ceiling for the whole document.
 *
 * Each attempt is written to its own scratch file and only the smallest result
 * is promoted, so a lower-DPI pass that happens to encode larger can never
 * replace a better earlier attempt.
 */
class PdfRasterCompressor {

    private data class Attempt(val bytes: Long, val dpi: Int, val quality: Int)

    fun compress(
        input: File,
        output: File,
        targetBytes: Long?,
        dpi: Int,
        minQuality: Int,
        maxQuality: Int,
        cancelled: () -> Boolean,
        progress: (Int, Int, String) -> Unit
    ): CompressOutcome {
        if (!input.exists()) error("File PDF tidak ditemukan.")

        var descriptor: ParcelFileDescriptor? = null
        var renderer: PdfRenderer? = null
        val parent = output.absoluteFile.parentFile ?: File(".")
        val attemptFile = File(parent, "${output.name}.try")
        val bestFile = File(parent, "${output.name}.best")

        try {
            descriptor = ParcelFileDescriptor.open(input, ParcelFileDescriptor.MODE_READ_ONLY)
            renderer = PdfRenderer(descriptor)
            val pageCount = renderer.pageCount
            if (pageCount <= 0) error("PDF tidak memiliki halaman.")
            if (pageCount > MAX_PAGES) {
                error("PDF punya $pageCount halaman (maksimum $MAX_PAGES). Pecah dulu dokumennya.")
            }

            var workingDpi = dpi.coerceIn(MIN_DPI, MAX_DPI)
            var best: Attempt? = null

            for (attempt in 0 until MAX_ATTEMPTS) {
                if (cancelled()) throw CompressCancelled()

                val quality = chooseQuality(
                    renderer, workingDpi, pageCount, targetBytes, minQuality, maxQuality
                )
                val size = writeDocument(
                    renderer = renderer,
                    output = attemptFile,
                    dpi = workingDpi,
                    quality = quality,
                    pageCount = pageCount,
                    attempt = attempt,
                    cancelled = cancelled,
                    progress = progress
                )

                val target = targetBytes
                if (best == null || size < best.bytes) {
                    best = Attempt(size, workingDpi, quality)
                    if (bestFile.exists()) bestFile.delete()
                    if (!attemptFile.renameTo(bestFile)) {
                        attemptFile.copyTo(bestFile, overwrite = true)
                        attemptFile.delete()
                    }
                } else {
                    attemptFile.delete()
                }

                if (target == null || size <= target || attempt == MAX_ATTEMPTS - 1) break

                // Resolution costs less perceived quality per saved byte than a
                // crushed JPEG, so always step the DPI down. chooseQuality()
                // re-derives the JPEG quality for the new resolution.
                val next = (workingDpi * 0.84).toInt().coerceIn(MIN_DPI, workingDpi - 1)
                if (next >= workingDpi) break
                workingDpi = next
            }

            val winner = best ?: error("Gagal mengompres PDF.")
            if (output.exists()) output.delete()
            if (!bestFile.renameTo(output)) {
                bestFile.copyTo(output, overwrite = true)
                bestFile.delete()
            }

            val target = targetBytes
            return CompressOutcome(
                pages = pageCount,
                note = note(winner.dpi, winner.quality, target, winner.bytes)
            )
        } finally {
            attemptFile.delete()
            bestFile.delete()
            runCatching { renderer?.close() }
            runCatching { descriptor?.close() }
        }
    }

    private fun writeDocument(
        renderer: PdfRenderer,
        output: File,
        dpi: Int,
        quality: Int,
        pageCount: Int,
        attempt: Int,
        cancelled: () -> Boolean,
        progress: (Int, Int, String) -> Unit
    ): Long {
        val writer = RasterPdfWriter(output)
        try {
            writer.open(pageCount)
            for (index in 0 until pageCount) {
                if (cancelled()) throw CompressCancelled()
                renderer.openPage(index).use { page ->
                    val dims = pixelSize(page.width, page.height, dpi)
                    val bitmap = renderBitmap(page, dims.first, dims.second)
                    try {
                        val jpeg = encodeJpeg(bitmap, quality)
                        writer.addPage(index, page.width, page.height, dims.first, dims.second, jpeg)
                    } finally {
                        bitmap.recycle()
                    }
                }
                progress(index + 1, pageCount, stageFor(attempt))
            }
            writer.close()
        } catch (t: Throwable) {
            writer.abort()
            throw t
        }
        return output.length()
    }

    private fun stageFor(attempt: Int): String = when (attempt) {
        0 -> "raster"
        1 -> "raster · percobaan 2"
        else -> "raster · percobaan 3"
    }

    private fun chooseQuality(
        renderer: PdfRenderer,
        dpi: Int,
        pageCount: Int,
        targetBytes: Long?,
        minQuality: Int,
        maxQuality: Int
    ): Int {
        val target = targetBytes ?: return maxQuality
        renderer.openPage(0).use { page ->
            val dims = pixelSize(page.width, page.height, dpi)
            val bitmap = renderBitmap(page, dims.first, dims.second)
            try {
                val highTotal = encodeJpegSize(bitmap, maxQuality).toDouble() * pageCount
                if (highTotal <= target) return maxQuality
                val lowTotal = encodeJpegSize(bitmap, minQuality).toDouble() * pageCount
                if (lowTotal >= target) return minQuality
                val span = highTotal - lowTotal
                if (span <= 0.0) return minQuality
                val ratio = ((target - lowTotal) / span).coerceIn(0.0, 1.0)
                return (minQuality + ratio * (maxQuality - minQuality)).roundToInt()
                    .coerceIn(minQuality, maxQuality)
            } finally {
                bitmap.recycle()
            }
        }
    }

    private fun pixelSize(widthPt: Int, heightPt: Int, dpi: Int): Pair<Int, Int> {
        val scale = dpi / 72.0
        var width = (widthPt * scale).roundToInt().coerceAtLeast(1)
        var height = (heightPt * scale).roundToInt().coerceAtLeast(1)
        val longest = max(width, height)
        if (longest > MAX_EDGE_PX) {
            val factor = MAX_EDGE_PX.toDouble() / longest
            width = (width * factor).roundToInt().coerceAtLeast(1)
            height = (height * factor).roundToInt().coerceAtLeast(1)
        }
        return width to height
    }

    private fun renderBitmap(page: PdfRenderer.Page, width: Int, height: Int): Bitmap {
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        bitmap.eraseColor(Color.WHITE)
        page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
        return bitmap
    }

    private fun encodeJpeg(bitmap: Bitmap, quality: Int): ByteArray {
        val out = ByteArrayOutputStream(1 shl 18)
        bitmap.compress(Bitmap.CompressFormat.JPEG, quality.coerceIn(1, 100), out)
        return out.toByteArray()
    }

    private fun encodeJpegSize(bitmap: Bitmap, quality: Int): Int = encodeJpeg(bitmap, quality).size

    private fun note(dpi: Int, quality: Int, target: Long?, size: Long): String {
        val base = "Raster ${dpi} dpi, JPEG $quality"
        return if (target != null && size > target) {
            "$base — target belum tercapai, coba mode kualitas lebih rendah."
        } else {
            base
        }
    }

    private companion object {
        const val MAX_ATTEMPTS = 3
        const val MIN_DPI = 72
        const val MAX_DPI = 300
        const val MAX_EDGE_PX = 2400
        const val MAX_PAGES = 2000
    }
}

/** Shared bitmap helper: downscale so the longest edge is at most [maxEdge]. */
internal fun scaleDown(source: Bitmap, maxEdge: Int): Bitmap {
    val longest = max(source.width, source.height)
    if (longest <= maxEdge) return source
    val factor = maxEdge.toDouble() / longest
    val width = (source.width * factor).roundToInt().coerceAtLeast(1)
    val height = (source.height * factor).roundToInt().coerceAtLeast(1)
    return Bitmap.createScaledBitmap(source, width, height, true)
}

internal fun decodeBounds(bytes: ByteArray): BitmapFactory.Options {
    val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)
    return options
}
