package com.maleolabs.kecilin.compress

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader
import com.tom_roush.pdfbox.cos.COSArray
import com.tom_roush.pdfbox.cos.COSBase
import com.tom_roush.pdfbox.cos.COSInteger
import com.tom_roush.pdfbox.cos.COSName
import com.tom_roush.pdfbox.io.MemoryUsageSetting
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.pdmodel.PDResources
import com.tom_roush.pdfbox.pdmodel.graphics.image.PDImageXObject
import java.io.ByteArrayOutputStream
import java.io.File
import kotlin.math.max

/**
 * "Ringan" mode: the document structure (and therefore the text layer) is kept.
 * Only embedded JPEG images are re-encoded at a lower quality/resolution, and
 * metadata is stripped.
 */
class PdfLightCompressor(private val context: Context) {

    fun compress(
        input: File,
        output: File,
        targetBytes: Long?,
        quality: Int,
        minQuality: Int,
        cancelled: () -> Boolean,
        progress: (Int, Int, String) -> Unit
    ): CompressOutcome {
        PDFBoxResourceLoader.init(context)

        var currentQuality = quality.coerceIn(minQuality, 95)
        var attempt = 0

        while (true) {
            if (cancelled()) throw CompressCancelled()
            val outcome = runOnce(input, output, currentQuality, cancelled, progress)
            val size = output.length()
            val target = targetBytes
            if (target == null || size <= target || attempt >= 2 || currentQuality <= minQuality) {
                return CompressOutcome(
                    pages = outcome.pages,
                    note = describe(currentQuality, outcome.note, target, size)
                )
            }
            attempt++
            currentQuality = (currentQuality * 0.7).toInt().coerceAtLeast(minQuality)
        }
    }

    private fun runOnce(
        input: File,
        output: File,
        quality: Int,
        cancelled: () -> Boolean,
        progress: (Int, Int, String) -> Unit
    ): CompressOutcome {
        // PDFBox spills the document to disk. Wipe it afterwards: the scratch
        // copy is a full duplicate of a personal document and must not linger.
        val scratch = File(context.cacheDir, "pdfbox")
        runCatching { scratch.deleteRecursively() }
        scratch.mkdirs()

        try {
            return runDocument(input, output, quality, scratch, cancelled, progress)
        } finally {
            runCatching { scratch.deleteRecursively() }
        }
    }

    private fun runDocument(
        input: File,
        output: File,
        quality: Int,
        scratch: File,
        cancelled: () -> Boolean,
        progress: (Int, Int, String) -> Unit
    ): CompressOutcome {
        val document = try {
            PDDocument.load(input, MemoryUsageSetting.setupTempFileOnly().setTempDir(scratch))
        } catch (t: Throwable) {
            throw IllegalArgumentException(
                "PDF tidak bisa dibuka. Coba mode Agresif atau pastikan file tidak rusak.",
                t
            )
        }

        document.use { doc ->
            // An owner password only restricts editing/printing. We already
            // opened the file, so clearing it is safe and lets us help.
            if (doc.isEncrypted) runCatching { doc.setAllSecurityToBeRemoved(true) }
            val pages = doc.numberOfPages
            if (pages > MAX_PAGES) {
                error("PDF punya $pages halaman (maksimum $MAX_PAGES). Pecah dulu dokumennya.")
            }
            var optimized = 0
            // A single XObject can be painted on many pages; compressing it once
            // avoids stacking generation loss on the same stream.
            val processed = java.util.Collections.newSetFromMap(
                java.util.IdentityHashMap<COSBase, Boolean>()
            )

            for (index in 0 until pages) {
                if (cancelled()) throw CompressCancelled()
                val page = doc.getPage(index)
                val resources = page.resources
                if (resources != null) {
                    val names = runCatching { resources.xObjectNames.toList() }.getOrDefault(emptyList())
                    for (name in names) {
                        if (cancelled()) throw CompressCancelled()
                        val image = runCatching { resources.getXObject(name) }.getOrNull()
                        if (image is PDImageXObject) {
                            if (recompress(name, image, quality, processed)) {
                                optimized++
                            }
                        }
                    }
                }
                progress(index + 1, pages, "light")
            }

            runCatching { doc.documentInformation.cosObject.clear() }
            runCatching { doc.documentCatalog.cosObject.removeItem(COSName.METADATA) }
            doc.save(output)

            val note = if (optimized > 0) {
                "$optimized gambar diperkecil, teks tetap utuh"
            } else {
                "Tidak ada gambar yang bisa diperkecil, teks tetap utuh"
            }
            return CompressOutcome(pages, note)
        }
    }

    /**
     * Re-encode a single JPEG XObject. Returns true when the replacement is
     * actually smaller. Anything we do not fully understand (masks, exotic
     * colour spaces, non-JPEG filters) is left untouched on purpose.
     */
    private fun recompress(
        name: COSName,
        image: PDImageXObject,
        quality: Int,
        processed: MutableSet<COSBase>
    ): Boolean {
        val cos = image.cosObject
        if (!processed.add(cos)) return false
        if (cos.containsKey(COSName.SMASK) || cos.containsKey(COSName.MASK)) return false

        // /Filter is allowed to be a one-element array, which scanners emit.
        // getFilters() returns COSBase in PDFBox 2.0, so normalise it here.
        val filterBase = runCatching { cos.filters }.getOrNull() ?: return false
        val filters: List<COSName> = when (filterBase) {
            is COSName -> listOf(filterBase)
            is COSArray -> (0 until filterBase.size())
                .mapNotNull { filterBase.getObject(it) as? COSName }
            else -> return false
        }
        if (filters.size != 1 || filters[0] != COSName.DCT_DECODE) return false

        // Check the declared length before materialising the stream, so a huge
        // embedded image cannot blow up the heap just to be rejected after.
        val declared = runCatching { cos.length }.getOrDefault(-1L)
        if (declared > MAX_IMAGE_BYTES) return false

        val raw = runCatching {
            cos.createRawInputStream().use { it.readBytes() }
        }.getOrNull() ?: return false
        if (raw.size < 24 * 1024 || raw.size > MAX_IMAGE_BYTES) return false
        // BitmapFactory mangles CMYK/YCCK JPEGs; leave those untouched.
        val components = jpegComponentCount(raw)
        if (components != 1 && components != 3) return false

        val bounds = decodeBounds(raw)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return false

        val maxEdge = 2200
        val longest = max(bounds.outWidth, bounds.outHeight)
        var sampleSize = 1
        while (longest / (sampleSize * 2) >= maxEdge) sampleSize *= 2

        val bitmap = runCatching {
            BitmapFactory.decodeByteArray(
                raw, 0, raw.size,
                BitmapFactory.Options().apply { inSampleSize = sampleSize }
            )
        }.getOrNull() ?: return false

        try {
            val scaled = scaleDown(bitmap, maxEdge)
            var encoded: ByteArray
            try {
                val stream = ByteArrayOutputStream(1 shl 18)
                scaled.compress(Bitmap.CompressFormat.JPEG, quality.coerceIn(1, 100), stream)
                encoded = stream.toByteArray()
            } finally {
                if (scaled !== bitmap) scaled.recycle()
            }

            if (encoded.size >= (raw.size * 0.92).toInt()) return false

            // Rewrite the stream *in place*. Swapping the resource entry instead
            // would leave the original stream in the document, and PDFBox writes
            // it back out — the "compressed" file ended up larger than the input.
            // In-place also means every reference to this XObject shrinks at once.
            // Raw output: the bytes are already JPEG. Going through
            // createOutputStream() would ask PDFBox to re-encode with DCTFilter,
            // which this port does not implement.
            cos.createRawOutputStream().use { it.write(encoded) }
            cos.setItem(COSName.FILTER, COSName.DCT_DECODE)
            cos.setItem(COSName.LENGTH, COSInteger.get(encoded.size.toLong()))
            cos.setItem(COSName.WIDTH, COSInteger.get(scaled.width.toLong()))
            cos.setItem(COSName.HEIGHT, COSInteger.get(scaled.height.toLong()))
            cos.setItem(COSName.COLORSPACE, COSName.DEVICERGB)
            cos.setItem(COSName.BITS_PER_COMPONENT, COSInteger.get(8L))
            // A /Decode array or mask belonged to the old pixels.
            cos.removeItem(COSName.DECODE)
            cos.removeItem(COSName.DECODE_PARMS)
            cos.removeItem(COSName.SMASK)
            cos.removeItem(COSName.MASK)
            return true
        } finally {
            bitmap.recycle()
        }
    }

    /** Reads the component count from the JPEG SOF marker; 0 when unknown. */
    private fun jpegComponentCount(bytes: ByteArray): Int {
        if (bytes.size < 4) return 0
        if (bytes[0] != 0xFF.toByte() || bytes[1] != 0xD8.toByte()) return 0
        var index = 2
        while (index + 9 < bytes.size) {
            if (bytes[index] != 0xFF.toByte()) {
                index++
                continue
            }
            val marker = bytes[index + 1].toInt() and 0xFF
            if (marker == 0xD8 || marker == 0x01 || marker in 0xD0..0xD7) {
                index += 2
                continue
            }
            if (marker == 0xDA) return 0
            val length = ((bytes[index + 2].toInt() and 0xFF) shl 8) or
                (bytes[index + 3].toInt() and 0xFF)
            if (marker in 0xC0..0xCF && marker != 0xC4 && marker != 0xC8 && marker != 0xCC) {
                return bytes[index + 9].toInt() and 0xFF
            }
            if (length < 2) return 0
            index += 2 + length
        }
        return 0
    }

    private companion object {
        const val MAX_IMAGE_BYTES = 40L * 1024 * 1024
        const val MAX_PAGES = 2000
    }

    private fun describe(quality: Int, note: String?, target: Long?, size: Long): String {
        val base = note ?: "Struktur dipertahankan"
        return if (target != null && size > target) {
            "$base (JPEG $quality) — target belum tercapai, coba mode Agresif."
        } else {
            "$base (JPEG $quality)"
        }
    }
}
