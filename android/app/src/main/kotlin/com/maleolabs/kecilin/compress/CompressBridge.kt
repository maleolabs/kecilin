package com.maleolabs.kecilin.compress

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Bridge between Flutter and the local compression engines.
 *
 * All heavy work runs on a single background thread so that concurrent
 * requests are serialized (avoids heap spikes on low-end devices).
 */
class CompressBridge(private val context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
    private val eventChannel = EventChannel(messenger, PROGRESS_CHANNEL)
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val cancelFlags = ConcurrentHashMap<String, AtomicBoolean>()

    /**
     * Cancels that arrived before the job was registered. The UI can request a
     * cancel while the request is still queued behind another file, and losing
     * that signal would trap the user on the progress screen.
     */
    private val pendingCancels = ConcurrentHashMap.newKeySet<String>()
    @Volatile private var events: EventChannel.EventSink? = null

    fun attach() {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
    }

    fun detach() {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        worker.shutdownNow()
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        this.events = events
    }

    override fun onCancel(arguments: Any?) {
        this.events = null
    }

    private fun emit(payload: Map<String, Any?>) {
        main.post { events?.success(payload) }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getPdfInfo" -> runAsync(result) { getPdfInfo(call) }
            "getImageInfo" -> runAsync(result) { getImageInfo(call) }
            "compressImage" -> runAsync(result) { compressImage(call) }
            "compressPdf" -> runAsync(result) { compressPdf(call) }
            "saveToDownloads" -> runAsync(result) { saveToDownloads(call) }
            "clearCache" -> runAsync(result) { clearCache() }
            "cancel" -> {
                val jobId = call.argument<String>("jobId")
                if (jobId != null) {
                    val flag = cancelFlags[jobId]
                    if (flag != null) flag.set(true) else pendingCancels.add(jobId)
                }
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    /** Registers a job; a cancel that arrived early is applied immediately. */
    private fun registerJob(jobId: String): AtomicBoolean {
        // `remove` returns a Boolean, never null — comparing it to null would
        // mark every job as cancelled before it starts.
        val flag = AtomicBoolean(pendingCancels.remove(jobId))
        cancelFlags[jobId] = flag
        return flag
    }

    private fun releaseJob(jobId: String) {
        cancelFlags.remove(jobId)
        pendingCancels.remove(jobId)
    }

    private fun runAsync(result: MethodChannel.Result, block: () -> Map<String, Any?>) {
        worker.execute {
            try {
                val payload = block()
                main.post { result.success(payload) }
            } catch (t: Throwable) {
                main.post {
                    result.error(
                        t.javaClass.simpleName,
                        t.message ?: "Terjadi kesalahan saat memproses file.",
                        null
                    )
                }
            }
        }
    }

    private fun getPdfInfo(call: MethodCall): Map<String, Any?> {
        val path = call.argument<String>("path") ?: error("path wajib diisi")
        return PdfInfo.read(File(path))
    }

    private fun getImageInfo(call: MethodCall): Map<String, Any?> {
        val path = call.argument<String>("path") ?: error("path wajib diisi")
        val options = android.graphics.BitmapFactory.Options().apply { inJustDecodeBounds = true }
        android.graphics.BitmapFactory.decodeFile(path, options)
        if (options.outWidth <= 0 || options.outHeight <= 0) {
            error("Format gambar tidak didukung.")
        }
        return mapOf("width" to options.outWidth, "height" to options.outHeight)
    }

    private fun compressImage(call: MethodCall): Map<String, Any?> {
        val jobId = call.argument<String>("jobId") ?: error("jobId wajib diisi")
        val inputPath = call.argument<String>("inputPath") ?: error("inputPath wajib diisi")
        val outputPath = call.argument<String>("outputPath") ?: error("outputPath wajib diisi")

        val options = ImageCompressor.Options(
            targetBytes = call.argument<Number>("targetBytes")?.toLong(),
            quality = call.argument<Number>("quality")?.toInt() ?: 80,
            minQuality = call.argument<Number>("minQuality")?.toInt() ?: 42,
            maxQuality = call.argument<Number>("maxQuality")?.toInt() ?: 92,
            maxEdge = call.argument<Number>("maxEdge")?.toInt() ?: 0,
            webp = call.argument<Boolean>("webp") ?: false,
            maximumMode = call.argument<Boolean>("maximumMode") ?: false
        )

        val input = File(inputPath)
        requireReadable(input)

        val flag = registerJob(jobId)
        try {
            val result = ImageCompressor().compress(
                input = input,
                output = File(outputPath),
                options = options,
                cancelled = { flag.get() },
                progress = { fraction, stage ->
                    emit(
                        mapOf(
                            "jobId" to jobId,
                            "fraction" to fraction,
                            "stage" to stage
                        )
                    )
                }
            )
            return mapOf(
                "outputPath" to File(outputPath).absolutePath,
                "beforeBytes" to File(inputPath).length(),
                "afterBytes" to result.bytes,
                "width" to result.width,
                "height" to result.height,
                "quality" to result.quality,
                "targetMet" to result.targetMet
            )
        } finally {
            releaseJob(jobId)
        }
    }

    private fun compressPdf(call: MethodCall): Map<String, Any?> {
        val jobId = call.argument<String>("jobId") ?: error("jobId wajib diisi")
        val inputPath = call.argument<String>("inputPath") ?: error("inputPath wajib diisi")
        val outputPath = call.argument<String>("outputPath") ?: error("outputPath wajib diisi")
        val mode = call.argument<String>("mode") ?: "light"
        val targetBytes = call.argument<Number>("targetBytes")?.toLong()
        val quality = call.argument<Number>("quality")?.toInt() ?: 75
        val maxDpi = call.argument<Number>("maxDpi")?.toInt() ?: 150
        val minQuality = call.argument<Number>("minQuality")?.toInt() ?: 35
        val maxQuality = call.argument<Number>("maxQuality")?.toInt() ?: 92

        val input = File(inputPath)
        val output = File(outputPath)
        requireReadable(input)
        output.parentFile?.mkdirs()

        val flag = registerJob(jobId)

        val cancelled = { flag.get() }
        val progress = { page: Int, pages: Int, stage: String ->
            emit(
                mapOf(
                    "jobId" to jobId,
                    "page" to page,
                    "pages" to pages,
                    "stage" to stage
                )
            )
        }

        try {
            val outcome = when (mode) {
                "raster" -> PdfRasterCompressor().compress(
                    input = input,
                    output = output,
                    targetBytes = targetBytes,
                    dpi = maxDpi,
                    minQuality = minQuality,
                    maxQuality = maxQuality,
                    cancelled = cancelled,
                    progress = progress
                )
                else -> PdfLightCompressor(context).compress(
                    input = input,
                    output = output,
                    targetBytes = targetBytes,
                    quality = quality,
                    minQuality = minQuality,
                    cancelled = cancelled,
                    progress = progress
                )
            }
            return mapOf(
                "outputPath" to output.absolutePath,
                "beforeBytes" to input.length(),
                "afterBytes" to output.length(),
                "pages" to outcome.pages,
                "note" to outcome.note
            )
        } finally {
            releaseJob(jobId)
        }
    }

    /**
     * Removes copies of the user's documents that libraries leave behind
     * (PDFBox scratch files, share_plus staging). These survive "Hapus file
     * hasil" otherwise, which breaks the mental model of deletion.
     */
    private fun clearCache(): Map<String, Any?> {
        var freed = 0L
        listOf("pdfbox", "share_plus").forEach { name ->
            val dir = File(context.cacheDir, name)
            if (dir.exists()) {
                runCatching {
                    freed += dir.walkBottomUp().filter { it.isFile }.sumOf { it.length() }
                    dir.deleteRecursively()
                }
            }
        }
        return mapOf("freedBytes" to freed)
    }

    private fun saveToDownloads(call: MethodCall): Map<String, Any?> {
        val path = call.argument<String>("path") ?: error("path wajib diisi")
        val displayName = call.argument<String>("displayName") ?: File(path).name
        val mime = call.argument<String>("mime") ?: "application/octet-stream"
        return DownloadsSaver.save(context, File(path), displayName, mime)
    }

    /**
     * Refuses files that cannot be processed in a reasonable amount of memory.
     * Parsing is the only place untrusted bytes enter the app, so the cap lives
     * here rather than inside each engine.
     */
    private fun requireReadable(file: File) {
        if (!file.exists()) error("File tidak ditemukan.")
        if (!file.canRead()) error("File tidak bisa dibaca.")
        if (file.length() <= 0L) error("File kosong.")
        if (file.length() > MAX_INPUT_BYTES) {
            error("File lebih dari 300 MB. Pecah dulu dokumennya.")
        }
    }

    companion object {
        private const val MAX_INPUT_BYTES = 300L * 1024 * 1024
        const val METHOD_CHANNEL = "com.maleolabs.kecilin/compress"
        const val PROGRESS_CHANNEL = "com.maleolabs.kecilin/progress"
    }
}
