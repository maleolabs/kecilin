package com.maleolabs.kecilin.gallery

import android.Manifest
import android.app.Activity
import android.content.ContentResolver
import android.content.ContentUris
import android.content.Context
import android.content.pm.PackageManager
import android.database.Cursor
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.util.Size
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.lang.ref.WeakReference
import java.util.concurrent.Executors
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Optional, on-demand access to the device's recent images.
 *
 * The app is fully usable without this permission: `status` reports what is
 * available and every other method degrades to an empty result instead of
 * throwing. All MediaStore work runs on one background thread, both to keep
 * the UI responsive and to avoid concurrent cursor/thumbnail work.
 *
 * Nothing read here is uploaded; originals are only copied into the app cache
 * so the existing compression engines can open them as plain files.
 */
class GalleryBridge(
    private val context: Context,
    messenger: BinaryMessenger,
    activity: Activity
) : MethodChannel.MethodCallHandler {

    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    // The bridge lives as long as the Flutter engine, which can outlive an
    // Activity recreation; holding it strongly would leak the old Activity.
    private val activityRef = WeakReference(activity)

    /**
     * The in-flight `request` result. Guarded by [this] because `request` and
     * `onRequestPermissionsResult` both run on the main thread, but the
     * synchronized block documents and enforces the "exactly once" contract.
     */
    private var pendingPermission: MethodChannel.Result? = null

    /**
     * Ordered id list used by the legacy (API 24-29) pager. QUERY_ARG_OFFSET
     * is not used there, so paging without a stable snapshot would duplicate
     * or skip rows as the library changes between pages.
     */
    @Volatile
    private var cachedIds: LongArray? = null

    private val resolver: ContentResolver get() = context.contentResolver

    /**
     * Probed once: a missing MediaStore provider is a device anomaly, not a
     * per-call condition, and the binder probe is not free.
     */
    private val mediaStoreAvailable: Boolean by lazy { probeMediaStore() }

    private val collection: Uri get() = MediaStore.Images.Media.EXTERNAL_CONTENT_URI

    /** Starts answering calls on `com.maleolabs.kecilin/gallery`. */
    fun attach() {
        methodChannel.setMethodCallHandler(this)
    }

    /** Stops answering calls and releases the worker thread. */
    fun detach() {
        methodChannel.setMethodCallHandler(null)
        // Never leave a Dart future hanging if the engine goes away mid-dialog.
        val pending = synchronized(this) { pendingPermission.also { pendingPermission = null } }
        pending?.let { runCatching { it.success(statusMap()) } }
        worker.shutdownNow()
    }

    /**
     * Must be called from the Activity's `onRequestPermissionsResult`, after
     * `super`. Safe to call for unrelated request codes.
     */
    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray) {
        if (requestCode != REQUEST_CODE) return
        val result = synchronized(this) {
            pendingPermission.also { pendingPermission = null }
        } ?: return

        // A grant (full or partial) changes which rows are visible, so the
        // legacy id snapshot must be rebuilt.
        if (grantResults.any { it == PackageManager.PERMISSION_GRANTED }) {
            cachedIds = null
        }
        result.success(statusMap())
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "status" -> result.success(statusMap())
            "request" -> requestAccess(result)
            "page" -> runAsync(result) { page(call) }
            "materialize" -> runAsync(result) { materialize(call) }
            "clearCache" -> runAsync(result) { clearCache() }
            else -> result.notImplemented()
        }
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
                        t.message ?: "Terjadi kesalahan saat membaca galeri.",
                        null
                    )
                }
            }
        }
    }

    // ---------------------------------------------------------------- status

    private fun statusMap(): Map<String, Any?> = mapOf("access" to currentAccess())

    private fun currentAccess(): String {
        if (!mediaStoreAvailable) return ACCESS_UNAVAILABLE
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            when {
                hasPermission(Manifest.permission.READ_MEDIA_IMAGES) -> ACCESS_GRANTED
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE &&
                    hasPermission(Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED) ->
                    ACCESS_PARTIAL
                else -> ACCESS_DENIED
            }
        } else {
            // minSdk is 24, so the legacy storage permission is always
            // declared (maxSdk 32) and therefore requestable here.
            if (hasPermission(Manifest.permission.READ_EXTERNAL_STORAGE)) {
                ACCESS_GRANTED
            } else {
                ACCESS_DENIED
            }
        }
    }

    private fun hasPermission(permission: String): Boolean =
        context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

    private fun probeMediaStore(): Boolean = runCatching {
        val client = resolver.acquireContentProviderClient(MediaStore.AUTHORITY) ?: return@runCatching false
        client.close()
        true
    }.getOrDefault(true)

    // --------------------------------------------------------------- request

    private fun requestAccess(result: MethodChannel.Result) {
        if (Looper.myLooper() != Looper.getMainLooper()) {
            main.post { requestAccess(result) }
            return
        }
        synchronized(this) {
            // A second call while the dialog is open must not stack another
            // dialog; report what we know so the caller can keep rendering.
            if (pendingPermission != null) {
                result.success(statusMap())
                return
            }

            val access = currentAccess()
            if (access != ACCESS_DENIED) {
                result.success(mapOf("access" to access))
                return
            }

            val activity = activityRef.get()
            if (activity == null || activity.isFinishing || activity.isDestroyed) {
                // No host to show a dialog; the caller must treat this as denied.
                result.success(mapOf("access" to ACCESS_DENIED))
                return
            }

            pendingPermission = result
            try {
                activity.requestPermissions(requiredPermissions(), REQUEST_CODE)
            } catch (t: Throwable) {
                pendingPermission = null
                result.success(statusMap())
            }
        }
    }

    private fun requiredPermissions(): Array<String> = when {
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE -> arrayOf(
            Manifest.permission.READ_MEDIA_IMAGES,
            Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED
        )
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU ->
            arrayOf(Manifest.permission.READ_MEDIA_IMAGES)
        else -> arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE)
    }

    // ------------------------------------------------------------------ page

    private fun page(call: MethodCall): Map<String, Any?> {
        val offset = (call.argument<Number>("offset")?.toInt() ?: 0).coerceAtLeast(0)
        val limit = (call.argument<Number>("limit")?.toInt() ?: DEFAULT_LIMIT)
            .coerceIn(1, MAX_LIMIT)

        if (!canRead()) return emptyPage()
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                pageWithQueryArgs(offset, limit)
            } else {
                pageWithIdSnapshot(offset, limit)
            }
        } catch (t: SecurityException) {
            cachedIds = null
            emptyPage()
        } catch (t: IllegalArgumentException) {
            cachedIds = null
            emptyPage()
        }
    }

    private fun canRead(): Boolean {
        val access = currentAccess()
        return access == ACCESS_GRANTED || access == ACCESS_PARTIAL
    }

    /**
     * API 30+ lets the provider apply limit/offset itself, so no client-side
     * snapshot is needed.
     */
    private fun pageWithQueryArgs(offset: Int, limit: Int): Map<String, Any?> {
        val args = Bundle().apply {
            putString(ContentResolver.QUERY_ARG_SQL_SELECTION, selection)
            putStringArray(ContentResolver.QUERY_ARG_SQL_SELECTION_ARGS, selectionArgs)
            putStringArray(
                ContentResolver.QUERY_ARG_SORT_COLUMNS,
                arrayOf(MediaStore.MediaColumns.DATE_ADDED, MediaStore.MediaColumns._ID)
            )
            putInt(
                ContentResolver.QUERY_ARG_SORT_DIRECTION,
                ContentResolver.QUERY_SORT_DIRECTION_DESCENDING
            )
            putInt(ContentResolver.QUERY_ARG_LIMIT, limit)
            putInt(ContentResolver.QUERY_ARG_OFFSET, offset)
        }
        val rows = resolver.query(collection, PROJECTION, args, null)?.use { readRows(it) }
            ?: return emptyPage()
        return pagePayload(rows, limit)
    }

    /**
     * API 24-29 has no portable offset support on MediaStore, so we snapshot
     * the ordered ids once per session and slice that snapshot. This keeps
     * paging stable while the user scrolls.
     */
    private fun pageWithIdSnapshot(offset: Int, limit: Int): Map<String, Any?> {
        val ids = loadOrderedIds()
        if (offset >= ids.size) return emptyPage()

        val end = min(offset + limit, ids.size)
        val slice = ids.copyOfRange(offset, end)
        val rows = readRowsByIds(slice)
        return pagePayload(rows, limit)
    }

    private fun loadOrderedIds(): LongArray {
        cachedIds?.let { return it }

        val result = ArrayList<Long>()
        resolver.query(
            collection,
            arrayOf(MediaStore.MediaColumns._ID),
            selection,
            selectionArgs,
            "$SORT_ORDER_LEGACY"
        )?.use { cursor ->
            while (cursor.moveToNext()) result.add(cursor.getLong(0))
        }

        val ids = result.toLongArray()
        cachedIds = ids
        return ids
    }

    private fun readRowsByIds(ids: LongArray): List<Row> {
        if (ids.isEmpty()) return emptyList()

        // A second query fetches metadata for just the page; the snapshot order
        // is restored below because `IN (...)` has no defined ordering.
        val placeholders = ids.joinToString(",") { "?" }
        val byId = HashMap<Long, Row>(ids.size)
        resolver.query(
            collection,
            PROJECTION,
            "${MediaStore.MediaColumns._ID} IN ($placeholders)",
            ids.map { it.toString() }.toTypedArray(),
            null
        )?.use { cursor ->
            readRows(cursor).forEach { byId[it.id] = it }
        }
        return ids.map { byId[it] }.filterNotNull()
    }

    private fun pagePayload(rows: List<Row>, limit: Int): Map<String, Any?> {
        val items = rows.map { it.toMap() }
        return mapOf(
            "items" to items,
            // The contract treats a full page as "there may be more", even when
            // the next page turns out empty.
            "hasMore" to (items.size == limit)
        )
    }

    private fun emptyPage(): Map<String, Any?> =
        mapOf("items" to emptyList<Map<String, Any?>>(), "hasMore" to false)

    private fun readRows(cursor: Cursor): List<Row> {
        val idIdx = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns._ID)
        val nameIdx = cursor.getColumnIndex(MediaStore.MediaColumns.DISPLAY_NAME)
        val sizeIdx = cursor.getColumnIndex(MediaStore.MediaColumns.SIZE)
        val widthIdx = cursor.getColumnIndex(MediaStore.MediaColumns.WIDTH)
        val heightIdx = cursor.getColumnIndex(MediaStore.MediaColumns.HEIGHT)
        val addedIdx = cursor.getColumnIndex(MediaStore.MediaColumns.DATE_ADDED)
        val modifiedIdx = cursor.getColumnIndex(MediaStore.MediaColumns.DATE_MODIFIED)

        val rows = ArrayList<Row>(cursor.count.coerceAtLeast(0))
        while (cursor.moveToNext()) {
            val size = cursor.longOrZero(sizeIdx)
            // Rows without bytes are placeholders (or being written); they can
            // never be materialized, so they must not reach Dart.
            if (size <= 0L) continue

            val id = cursor.getLong(idIdx)
            rows.add(
                Row(
                    id = id,
                    name = cursor.stringOrNull(nameIdx) ?: "image_$id.jpg",
                    bytes = size,
                    width = cursor.intOrZero(widthIdx),
                    height = cursor.intOrZero(heightIdx),
                    dateAdded = cursor.longOrZero(addedIdx),
                    dateModified = cursor.longOrZero(modifiedIdx)
                )
            )
        }
        return rows
    }

    private fun Row.toMap(): Map<String, Any?> = mapOf(
        "id" to id,
        "name" to name,
        "bytes" to bytes,
        "width" to width,
        "height" to height,
        "dateAdded" to dateAdded,
        "thumbPath" to thumbnailFor(this)
    )

    private val selection: String
        get() {
            val clauses = mutableListOf(
                "${MediaStore.MediaColumns.MIME_TYPE} LIKE ?",
                "${MediaStore.MediaColumns.SIZE} > 0"
            )
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                clauses.add("(${MediaStore.MediaColumns.IS_PENDING} IS NULL OR ${MediaStore.MediaColumns.IS_PENDING} = 0)")
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                clauses.add("(${MediaStore.MediaColumns.IS_TRASHED} IS NULL OR ${MediaStore.MediaColumns.IS_TRASHED} = 0)")
            }
            return clauses.joinToString(" AND ")
        }

    private val selectionArgs: Array<String> get() = arrayOf("image/%")

    // ----------------------------------------------------------- thumbnails

    /**
     * Returns an absolute JPEG path, or an empty string when the thumbnail
     * cannot be produced. An empty string is preferred over dropping the item:
     * the caller keeps a stable page size and can render a placeholder.
     */
    private fun thumbnailFor(row: Row): String {
        val dir = File(context.cacheDir, THUMB_DIR)
        if (!dir.isDirectory && !dir.mkdirs()) return ""

        val target = File(dir, "${row.id}_${row.dateModified}.jpg")
        if (target.isFile && target.length() > 0L) return target.absolutePath

        return try {
            writeThumbnail(row, target)
            // writeThumbnail can bail out (unreadable source); never hand Dart
            // a path that does not exist.
            if (target.isFile && target.length() > 0L) target.absolutePath else ""
        } catch (t: Exception) {
            target.delete()
            ""
        }
    }

    private fun writeThumbnail(row: Row, target: File) {
        val uri = ContentUris.withAppendedId(collection, row.id)
        var decoded: Bitmap? = null
        var output: Bitmap? = null
        try {
            decoded = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                loadSystemThumbnail(uri) ?: decodeSampled(uri)
            } else {
                // The legacy thumbnails table is not guaranteed to hold every
                // image, and decoding with inSampleSize is simpler and safer.
                decodeSampled(uri)
            } ?: return

            output = scaleDown(decoded)
            val temp = File(target.parentFile, "${target.name}.tmp")
            temp.outputStream().use { stream ->
                output.compress(Bitmap.CompressFormat.JPEG, THUMB_QUALITY, stream)
            }
            if (!temp.renameTo(target)) {
                temp.delete()
                return
            }
        } finally {
            if (output != null && output !== decoded) output.recycle()
            decoded?.recycle()
        }
    }

    private fun loadSystemThumbnail(uri: Uri): Bitmap? = try {
        resolver.loadThumbnail(uri, Size(THUMB_EDGE, THUMB_EDGE), null)
    } catch (t: Exception) {
        null
    }

    /**
     * Bounds-only decode first, then a power-of-two sample, so a 100 MP photo
     * never allocates a full-resolution bitmap.
     */
    private fun decodeSampled(uri: Uri): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        resolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) }
            ?: return null
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null

        var sample = 1
        while (max(bounds.outWidth, bounds.outHeight) / (sample * 2) >= THUMB_EDGE) {
            sample *= 2
        }
        val options = BitmapFactory.Options().apply {
            inSampleSize = sample
            // Thumbnails are opaque photos; 565 halves the memory cost.
            inPreferredConfig = Bitmap.Config.RGB_565
        }
        return resolver.openInputStream(uri)?.use {
            BitmapFactory.decodeStream(it, null, options)
        }
    }

    private fun scaleDown(source: Bitmap): Bitmap {
        val longest = max(source.width, source.height)
        if (longest <= THUMB_EDGE) return source

        val ratio = THUMB_EDGE.toFloat() / longest
        val width = max(1, (source.width * ratio).roundToInt())
        val height = max(1, (source.height * ratio).roundToInt())
        return Bitmap.createScaledBitmap(source, width, height, true)
    }

    // ---------------------------------------------------------- materialize

    private fun materialize(call: MethodCall): Map<String, Any?> {
        val id = call.argument<Number>("id")?.toLong() ?: error("id wajib diisi")
        val row = findRow(id) ?: error("Foto tidak ditemukan.")

        val dir = File(context.cacheDir, IN_DIR)
        if (!dir.isDirectory && !dir.mkdirs()) error("Tidak bisa menyiapkan cache.")

        val safeName = sanitize(row.name)
        val target = File(dir, "${row.id}_$safeName")
        if (canReuse(target, row.bytes, row.dateModified)) {
            return materializePayload(target, safeName, row)
        }

        copyOriginal(id, target, row.dateModified)
        return materializePayload(target, safeName, row)
    }

    private fun findRow(id: Long): Row? = resolver.query(
        collection,
        PROJECTION,
        "${MediaStore.MediaColumns._ID} = ?",
        arrayOf(id.toString()),
        null
    )?.use { readRows(it).firstOrNull() }

    /**
     * MediaStore reports `DATE_MODIFIED` in seconds; the copy's lastModified is
     * set to match so a second materialize can skip the copy. When the column
     * is absent (0), size equality is the only signal available.
     */
    private fun canReuse(file: File, bytes: Long, dateModified: Long): Boolean {
        if (!file.isFile) return false
        if (file.length() != bytes) return false
        if (dateModified <= 0L) return true
        return file.lastModified() == dateModified * 1000L
    }

    private fun copyOriginal(id: Long, target: File, dateModified: Long) {
        val uri = ContentUris.withAppendedId(collection, id)
        val temp = File(target.parentFile, "${target.name}.part")
        try {
            resolver.openInputStream(uri)?.use { input ->
                temp.outputStream().use { output -> input.copyTo(output, 1 shl 16) }
            } ?: error("Foto tidak bisa dibaca.")

            if (!temp.renameTo(target)) {
                // A stale file at the same path can block the rename on some
                // filesystems; drop it and retry once.
                target.delete()
                if (!temp.renameTo(target)) error("Gagal menyimpan salinan foto.")
            }
            if (dateModified > 0L) target.setLastModified(dateModified * 1000L)
        } catch (t: Throwable) {
            temp.delete()
            throw t
        }
    }

    private fun materializePayload(
        file: File,
        name: String,
        row: Row
    ): Map<String, Any?> = mapOf(
        "path" to file.absolutePath,
        "name" to name,
        "bytes" to file.length(),
        "width" to row.width,
        "height" to row.height
    )

    // ------------------------------------------------------------- cache

    private fun clearCache(): Map<String, Any?> {
        var freed = 0L
        listOf(THUMB_DIR, IN_DIR).forEach { name ->
            val dir = File(context.cacheDir, name)
            if (!dir.exists()) return@forEach
            runCatching {
                freed += dir.walkBottomUp().filter { it.isFile }.sumOf { it.length() }
                dir.deleteRecursively()
            }
        }
        return mapOf("freedBytes" to freed)
    }

    // ------------------------------------------------------------ helpers

    private fun sanitize(name: String): String {
        // Kept byte-for-byte in sync with DownloadsSaver.sanitize, which is
        // private to the compress package and must not be touched.
        val cleaned = name
            .replace(Regex("[\\u0000-\\u001F\\u007F]"), "")
            .replace(Regex("[/\\\\:*?\"<>|]"), "_")
            .replace(Regex("[\\u200B-\\u200F\\u202A-\\u202E\\u2066-\\u2069]"), "")
            .trim()
            .trimEnd('.', ' ')
        if (cleaned.isEmpty()) return "kecilin"
        return if (cleaned.length > 100) cleaned.substring(0, 100) else cleaned
    }

    private fun Cursor.longOrZero(index: Int): Long =
        if (index < 0 || isNull(index)) 0L else getLong(index)

    private fun Cursor.intOrZero(index: Int): Int =
        if (index < 0 || isNull(index)) 0 else getInt(index)

    private fun Cursor.stringOrNull(index: Int): String? =
        if (index < 0 || isNull(index)) null else getString(index)

    private data class Row(
        val id: Long,
        val name: String,
        val bytes: Long,
        val width: Int,
        val height: Int,
        val dateAdded: Long,
        val dateModified: Long
    )

    companion object {
        const val METHOD_CHANNEL = "com.maleolabs.kecilin/gallery"

        private const val REQUEST_CODE = 0x6A11
        private const val THUMB_EDGE = 320
        private const val THUMB_QUALITY = 85
        private const val DEFAULT_LIMIT = 60
        private const val MAX_LIMIT = 200
        private const val THUMB_DIR = "gallery-thumbs"
        private const val IN_DIR = "gallery-in"

        private const val ACCESS_GRANTED = "granted"
        private const val ACCESS_PARTIAL = "partial"
        private const val ACCESS_DENIED = "denied"
        private const val ACCESS_UNAVAILABLE = "unavailable"

        private const val SORT_ORDER_LEGACY =
            "${MediaStore.MediaColumns.DATE_ADDED} DESC, ${MediaStore.MediaColumns._ID} DESC"

        private val PROJECTION = arrayOf(
            MediaStore.MediaColumns._ID,
            MediaStore.MediaColumns.DISPLAY_NAME,
            MediaStore.MediaColumns.SIZE,
            MediaStore.MediaColumns.WIDTH,
            MediaStore.MediaColumns.HEIGHT,
            MediaStore.MediaColumns.DATE_ADDED,
            MediaStore.MediaColumns.DATE_MODIFIED
        )
    }
}
