package com.maleolabs.kecilin.compress

import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import java.io.File

/**
 * Copies a finished file into the user-visible Downloads folder.
 *
 * On API 29+ this goes through MediaStore (no storage permission needed).
 * On older devices we fall back to the app-specific external folder.
 */
object DownloadsSaver {

    fun save(context: Context, source: File, rawName: String, mime: String): Map<String, Any?> {
        require(source.exists()) { "File hasil tidak ditemukan." }
        // Defence in depth: the Dart layer already sanitises, but this is the
        // boundary where a name becomes a real MediaStore row.
        val displayName = sanitize(rawName)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            saveWithMediaStore(context, source, displayName, mime)
        } else {
            saveToAppExternal(context, source, displayName)
        }
    }

    private fun sanitize(name: String): String {
        val cleaned = name
            .replace(Regex("[\\u0000-\\u001F\\u007F]"), "")
            .replace(Regex("[/\\\\:*?\"<>|]"), "_")
            .replace(Regex("[\\u200B-\\u200F\\u202A-\\u202E\\u2066-\\u2069]"), "")
            .trim()
            .trimEnd('.', ' ')
        if (cleaned.isEmpty()) return "kecilin"
        return if (cleaned.length > 100) cleaned.substring(0, 100) else cleaned
    }

    private fun saveWithMediaStore(
        context: Context,
        source: File,
        displayName: String,
        mime: String
    ): Map<String, Any?> {
        val resolver = context.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, displayName)
            put(MediaStore.MediaColumns.MIME_TYPE, mime)
            put(
                MediaStore.MediaColumns.RELATIVE_PATH,
                "${Environment.DIRECTORY_DOWNLOADS}/Kecilin"
            )
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }

        val collection = MediaStore.Downloads.EXTERNAL_CONTENT_URI
        val uri = resolver.insert(collection, values)
            ?: error("Tidak bisa membuat file di folder Download.")

        try {
            resolver.openOutputStream(uri)?.use { output ->
                source.inputStream().use { input -> input.copyTo(output, 1 shl 16) }
            } ?: error("Tidak bisa menulis ke folder Download.")

            val done = ContentValues().apply {
                put(MediaStore.MediaColumns.IS_PENDING, 0)
            }
            val updated = resolver.update(uri, done, null, null)
            if (updated <= 0) {
                // Without this the row stays pending forever and the user never
                // sees the file, with no error to explain why.
                runCatching { resolver.delete(uri, null, null) }
                error("Gagal menyelesaikan penyimpanan ke Download.")
            }

            // MediaStore renames on collision ("ktp-kecil (1).jpg"). Report the
            // name that actually landed on disk, otherwise the UI points at a
            // file that does not exist.
            val actualName = runCatching {
                resolver.query(
                    uri,
                    arrayOf(MediaStore.MediaColumns.DISPLAY_NAME),
                    null,
                    null,
                    null
                )?.use { cursor ->
                    if (cursor.moveToFirst()) cursor.getString(0) else null
                }
            }.getOrNull() ?: displayName

            return mapOf(
                "uri" to uri.toString(),
                "displayName" to actualName,
                "displayPath" to "Download/Kecilin/$actualName"
            )
        } catch (t: Throwable) {
            runCatching { resolver.delete(uri, null, null) }
            throw t
        }
    }

    private fun saveToAppExternal(
        context: Context,
        source: File,
        displayName: String
    ): Map<String, Any?> {
        val base = context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)
            ?: context.filesDir
        val folder = File(base, "Kecilin").apply { mkdirs() }
        val target = uniqueFile(folder, displayName)
        source.copyTo(target, overwrite = true)
        return mapOf(
            "uri" to null,
            "displayPath" to target.absolutePath
        )
    }

    private fun uniqueFile(folder: File, name: String): File {
        var candidate = File(folder, name)
        if (!candidate.exists()) return candidate
        val dot = name.lastIndexOf('.')
        val stem = if (dot > 0) name.substring(0, dot) else name
        val extension = if (dot > 0) name.substring(dot) else ""
        var index = 1
        while (candidate.exists()) {
            candidate = File(folder, "$stem ($index)$extension")
            index++
        }
        return candidate
    }
}
