package com.maleolabs.kecilin.compress

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Rect
import android.media.ExifInterface
import android.os.Build
import java.io.ByteArrayOutputStream
import java.io.File
import kotlin.math.max
import kotlin.math.roundToInt
import kotlin.math.sqrt

/**
 * Image compressor that decodes the source exactly once and then binary-searches
 * the JPEG quality. This keeps batch jobs fast and avoids the compounding
 * generation loss you get from re-decoding a re-encoded file.
 */
class ImageCompressor {

    data class Options(
        val targetBytes: Long?,
        val quality: Int,
        val minQuality: Int,
        val maxQuality: Int,
        val maxEdge: Int,
        val webp: Boolean,
        val maximumMode: Boolean
    )

    data class Result(
        val bytes: Int,
        val width: Int,
        val height: Int,
        val quality: Int,
        val targetMet: Boolean
    )

    fun compress(
        input: File,
        output: File,
        options: Options,
        cancelled: () -> Boolean,
        progress: (Double, String) -> Unit
    ): Result {
        if (!input.exists()) error("File gambar tidak ditemukan.")
        output.parentFile?.mkdirs()

        progress(0.05, "Membaca gambar")
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(input.absolutePath, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) {
            error("Format gambar tidak didukung.")
        }

        val initialSample = sampleFor(bounds.outWidth, bounds.outHeight)
        var bitmap = decode(input, initialSample)
        try {
            if (cancelled()) throw CompressCancelled()

            progress(0.2, "Menyiapkan")
            val rotated = applyOrientation(input, bitmap)
            if (rotated !== bitmap) {
                bitmap.recycle()
                bitmap = rotated
            }

            val outcome = if (options.targetBytes != null) {
                compressToTarget(bitmap, output, options, cancelled, progress)
            } else {
                compressFixed(bitmap, output, options, cancelled)
            }
            return outcome
        } finally {
            if (!bitmap.isRecycled) bitmap.recycle()
        }
    }

    // ---------------------------------------------------------------- target

    private fun compressToTarget(
        source: Bitmap,
        output: File,
        options: Options,
        cancelled: () -> Boolean,
        progress: (Double, String) -> Unit
    ): Result {
        val target = options.targetBytes!!
        var scale = initialScale(source, target, options.maxEdge)

        var bestBytes = Int.MAX_VALUE
        var bestQuality = options.minQuality
        var bestWidth = source.width
        var bestHeight = source.height
        var bestPayload: ByteArray? = null

        for (round in 0 until 3) {
            if (cancelled()) throw CompressCancelled()
            val width = (source.width * scale).roundToInt().coerceIn(1, 20000)
            val height = (source.height * scale).roundToInt().coerceIn(1, 20000)

            progress(0.3 + round * 0.15, "Mengompres")
            val frame = flatten(source, width, height)
            try {
                val ceiling = encode(frame, options.maxQuality, options.webp)
                if (ceiling.size <= target) {
                    write(output, ceiling)
                    return Result(ceiling.size, width, height, options.maxQuality, true)
                }
                if (ceiling.size < bestBytes) {
                    bestBytes = ceiling.size
                    bestQuality = options.maxQuality
                    bestWidth = width
                    bestHeight = height
                    bestPayload = ceiling
                }

                var low = options.minQuality
                var high = options.maxQuality
                var hitQuality: Int? = null
                var hitPayload: ByteArray? = null

                // Binary search the best quality that still fits the budget.
                while (high - low > 4) {
                    if (cancelled()) throw CompressCancelled()
                    val mid = (low + high) / 2
                    val payload = encode(frame, mid, options.webp)
                    if (payload.size <= target) {
                        low = mid
                        hitQuality = mid
                        hitPayload = payload
                    } else {
                        high = mid
                    }
                    if (payload.size < bestBytes) {
                        bestBytes = payload.size
                        bestQuality = mid
                        bestWidth = width
                        bestHeight = height
                        bestPayload = payload
                    }
                }

                if (hitPayload != null) {
                    write(output, hitPayload)
                    return Result(
                        hitPayload.size, width, height, hitQuality ?: low, true
                    )
                }

                val floorPayload = encode(frame, options.minQuality, options.webp)
                if (floorPayload.size < bestBytes) {
                    bestBytes = floorPayload.size
                    bestQuality = options.minQuality
                    bestWidth = width
                    bestHeight = height
                    bestPayload = floorPayload
                }
            } finally {
                frame.recycle()
            }

            if (bestPayload != null && bestPayload.size <= target) {
                write(output, bestPayload)
                return Result(bestPayload.size, bestWidth, bestHeight, bestQuality, true)
            }

            // Nothing fits at this resolution: estimate how much to shrink.
            val factor = sqrt(target.toDouble() / bestBytes.toDouble()).coerceIn(0.35, 0.92)
            scale = (scale * factor).coerceIn(0.1, 1.0)
            if (round == 2) break
        }

        val fallback = bestPayload ?: error("Gagal mengompres gambar.")
        write(output, fallback)
        return Result(fallback.size, bestWidth, bestHeight, bestQuality, false)
    }

    // ------------------------------------------------------------- fixed q

    private fun compressFixed(
        source: Bitmap,
        output: File,
        options: Options,
        cancelled: () -> Boolean
    ): Result {
        if (cancelled()) throw CompressCancelled()
        val (width, height) = fitWithin(source.width, source.height, options.maxEdge)
        val frame = flatten(source, width, height)
        try {
            val quality = if (options.maximumMode) 96 else options.quality
            val payload = encode(frame, quality, options.webp)
            write(output, payload)
            return Result(payload.size, width, height, quality, true)
        } finally {
            frame.recycle()
        }
    }

    // ------------------------------------------------------------- helpers

    private fun initialScale(source: Bitmap, target: Long, maxEdge: Int): Double {
        // ~0.16 bytes per pixel at q85: a deliberately cheap starting guess,
        // the binary search corrects the rest.
        val budgetPixels = target.toDouble() / 0.16
        val pixels = source.width.toDouble() * source.height.toDouble()
        var scale = if (budgetPixels < pixels) sqrt(budgetPixels / pixels) else 1.0
        if (maxEdge > 0) {
            val longest = max(source.width, source.height).toDouble()
            if (longest * scale > maxEdge) scale = maxEdge / longest
        }
        return scale.coerceIn(0.1, 1.0)
    }

    private fun fitWithin(width: Int, height: Int, maxEdge: Int): Pair<Int, Int> {
        if (maxEdge <= 0) return width to height
        val longest = max(width, height)
        if (longest <= maxEdge) return width to height
        val factor = maxEdge.toDouble() / longest
        return (width * factor).roundToInt().coerceAtLeast(1) to
            (height * factor).roundToInt().coerceAtLeast(1)
    }

    /**
     * Redraws the bitmap at the requested size on a white canvas. This both
     * resamples and removes alpha (transparent PNGs would otherwise turn black
     * once flattened into JPEG).
     */
    private fun flatten(source: Bitmap, width: Int, height: Int): Bitmap {
        val out = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(out)
        canvas.drawColor(Color.WHITE)
        if (width != source.width || height != source.height) {
            canvas.drawBitmap(
                source,
                null,
                Rect(0, 0, width, height),
                Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
            )
        } else {
            canvas.drawBitmap(source, 0f, 0f, Paint(Paint.ANTI_ALIAS_FLAG))
        }
        return out
    }

    private fun encode(bitmap: Bitmap, quality: Int, webp: Boolean): ByteArray {
        val stream = ByteArrayOutputStream(1 shl 20)
        val format = if (webp) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                Bitmap.CompressFormat.WEBP_LOSSY
            } else {
                @Suppress("DEPRECATION")
                Bitmap.CompressFormat.WEBP
            }
        } else {
            Bitmap.CompressFormat.JPEG
        }
        bitmap.compress(format, quality.coerceIn(1, 100), stream)
        return stream.toByteArray()
    }

    private fun write(output: File, payload: ByteArray) {
        output.parentFile?.mkdirs()
        output.outputStream().use { it.write(payload) }
    }

    private fun sampleFor(width: Int, height: Int): Int {
        var sample = 1
        while ((width / (sample * 2)).toLong() * (height / (sample * 2)).toLong() > MAX_DECODE_PIXELS) {
            sample *= 2
        }
        return sample
    }

    private fun decode(file: File, initialSample: Int): Bitmap {
        var sample = initialSample
        while (true) {
            try {
                val options = BitmapFactory.Options().apply {
                    inSampleSize = sample
                    inPreferredConfig = Bitmap.Config.ARGB_8888
                }
                return BitmapFactory.decodeFile(file.absolutePath, options)
                    ?: error("Gambar gagal dibaca. File mungkin rusak.")
            } catch (oom: OutOfMemoryError) {
                if (sample >= 8) error("Gambar terlalu besar untuk diproses di perangkat ini.")
                sample *= 2
            }
        }
    }

    private fun applyOrientation(file: File, bitmap: Bitmap): Bitmap {
        val orientation = runCatching {
            ExifInterface(file.absolutePath)
                .getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
        }.getOrDefault(ExifInterface.ORIENTATION_NORMAL)

        val matrix = Matrix()
        when (orientation) {
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.postScale(-1f, 1f)
            ExifInterface.ORIENTATION_ROTATE_180 -> matrix.postRotate(180f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.postScale(1f, -1f)
            ExifInterface.ORIENTATION_TRANSPOSE -> {
                matrix.postRotate(90f)
                matrix.postScale(-1f, 1f)
            }
            ExifInterface.ORIENTATION_ROTATE_90 -> matrix.postRotate(90f)
            ExifInterface.ORIENTATION_TRANSVERSE -> {
                matrix.postRotate(270f)
                matrix.postScale(-1f, 1f)
            }
            ExifInterface.ORIENTATION_ROTATE_270 -> matrix.postRotate(270f)
            else -> return bitmap
        }

        return runCatching {
            Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
        }.getOrDefault(bitmap)
    }

    companion object {
        private const val MAX_DECODE_PIXELS = 12_000_000L
    }
}
