package com.hibir.fetchio

import android.Manifest
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.IOException
import java.util.concurrent.Executors

class MediaStoreBridge(private val context: Context) : MethodChannel.MethodCallHandler {
    companion object {
        const val CHANNEL = "com.hibir.fetchio/media_store"
        private const val FILE_PROVIDER_SUFFIX = ".fileprovider"
        private const val DOWNLOAD_FOLDER = "Fetchio"
    }

    private val ioExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "saveToDownloads" -> {
                val sourcePath = call.argument<String>("sourcePath")
                val displayName = call.argument<String>("displayName")
                val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"
                if (sourcePath == null || displayName == null) {
                    result.error("INVALID_ARGS", "sourcePath and displayName are required", null)
                    return
                }

                ioExecutor.execute {
                    try {
                        val saved = saveToDownloads(sourcePath, displayName, mimeType)
                        mainHandler.post { result.success(saved) }
                    } catch (e: Exception) {
                        mainHandler.post { result.error("SAVE_FAILED", e.message, null) }
                    }
                }
            }

            "needsStoragePermission" -> {
                val needed = Build.VERSION.SDK_INT < Build.VERSION_CODES.Q &&
                    context.checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) !=
                    PackageManager.PERMISSION_GRANTED
                result.success(needed)
            }

            "mediaExists" -> {
                val value = call.argument<String>("uri")
                if (value == null) {
                    result.error("INVALID_ARGS", "uri is required", null)
                    return
                }
                result.success(mediaExists(value))
            }

            "openMedia" -> {
                val value = call.argument<String>("uri")
                val mimeType = call.argument<String>("mimeType") ?: "*/*"
                if (value == null) {
                    result.error("INVALID_ARGS", "uri is required", null)
                    return
                }
                try {
                    openMedia(value, mimeType)
                    result.success(true)
                } catch (e: Exception) {
                    result.error("OPEN_FAILED", e.message, null)
                }
            }

            else -> result.notImplemented()
        }
    }

    private fun saveToDownloads(sourcePath: String, displayName: String, mimeType: String): String {
        val sourceFile = File(sourcePath)
        if (!sourceFile.isFile || !sourceFile.canRead()) {
            throw IllegalArgumentException("Source file is unavailable")
        }
        val safeName = sanitizeDisplayName(displayName)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            saveViaMediaStore(sourceFile, safeName, mimeType)
        } else {
            saveLegacy(sourceFile, safeName)
        }
    }

    /** API 29+: keep every file in the public Download/Fetchio directory. */
    private fun saveViaMediaStore(sourceFile: File, displayName: String, mimeType: String): String {
        val resolver = context.contentResolver
        val collection = MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, displayName)
            put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
            put(MediaStore.MediaColumns.RELATIVE_PATH, "${Environment.DIRECTORY_DOWNLOADS}/$DOWNLOAD_FOLDER/")
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = resolver.insert(collection, values)
            ?: throw IOException("MediaStore could not create the download")

        try {
            val output = resolver.openOutputStream(uri)
                ?: throw IOException("MediaStore could not open the download for writing")
            output.use { stream -> FileInputStream(sourceFile).use { it.copyTo(stream) } }

            val published = ContentValues().apply {
                put(MediaStore.MediaColumns.IS_PENDING, 0)
            }
            if (resolver.update(uri, published, null, null) <= 0) {
                throw IOException("MediaStore could not publish the download")
            }
            return uri.toString()
        } catch (e: Exception) {
            try {
                resolver.delete(uri, null, null)
            } catch (_: Exception) {
            }
            throw e
        }
    }

    /** API < 29: copy to public Downloads with a unique name and index it. */
    @Suppress("DEPRECATION")
    private fun saveLegacy(sourceFile: File, displayName: String): String {
        val downloadsDir = Environment.getExternalStoragePublicDirectory(
            Environment.DIRECTORY_DOWNLOADS,
        )
        val destDir = File(downloadsDir, DOWNLOAD_FOLDER)
        if (!destDir.exists() && !destDir.mkdirs()) {
            throw IOException("Could not create the Downloads/Fetchio directory")
        }

        val destFile = createUniqueFile(destDir, displayName)
        try {
            sourceFile.copyTo(destFile, overwrite = true)
            android.media.MediaScannerConnection.scanFile(
                context,
                arrayOf(destFile.absolutePath),
                null,
                null,
            )
            return destFile.absolutePath
        } catch (e: Exception) {
            destFile.delete()
            throw e
        }
    }

    private fun createUniqueFile(directory: File, name: String): File {
        val dot = name.lastIndexOf('.')
        val stem = if (dot > 0) name.substring(0, dot) else name
        val extension = if (dot > 0) name.substring(dot) else ""
        for (index in 0..Int.MAX_VALUE) {
            val candidateName = if (index == 0) name else "$stem ($index)$extension"
            val candidate = File(directory, candidateName)
            if (candidate.createNewFile()) return candidate
        }
        throw IOException("Could not choose a unique download filename")
    }

    private fun sanitizeDisplayName(displayName: String): String {
        val basename = displayName.replace('\\', '/').substringAfterLast('/').trim()
        val safe = basename.replace(Regex("[\\u0000-\\u001F]"), "_")
        if (safe.isEmpty() || safe == "." || safe == "..") {
            throw IllegalArgumentException("displayName must contain a valid filename")
        }
        return safe
    }

    private fun mediaExists(value: String): Boolean {
        return try {
            val uri = Uri.parse(value)
            if (uri.scheme == "content") {
                context.contentResolver.openFileDescriptor(uri, "r")?.use { true } ?: false
            } else {
                val path = if (uri.scheme == "file") uri.path.orEmpty() else value
                File(path).isFile
            }
        } catch (_: Exception) {
            false
        }
    }

    private fun openMedia(value: String, mimeType: String) {
        val parsed = Uri.parse(value)
        val contentUri = when {
            parsed.scheme == "content" -> {
                if (parsed.authority != "media" || !isInFetchioDownloads(parsed)) {
                    throw IllegalArgumentException("Only saved files in Downloads/Fetchio can be opened")
                }
                parsed
            }
            parsed.scheme == null || parsed.scheme == "file" -> {
                val path = if (parsed.scheme == "file") parsed.path.orEmpty() else value
                val file = File(path).canonicalFile
                val downloads = Environment.getExternalStoragePublicDirectory(
                    Environment.DIRECTORY_DOWNLOADS,
                ).canonicalFile
                val allowedDirectory = File(downloads, DOWNLOAD_FOLDER).canonicalFile
                if (!file.isFile || file.parentFile != allowedDirectory) {
                    throw IllegalArgumentException("Only saved files in Downloads/Fetchio can be opened")
                }
                FileProvider.getUriForFile(
                    context,
                    context.packageName + FILE_PROVIDER_SUFFIX,
                    file,
                )
            }
            else -> throw IllegalArgumentException("Unsupported media URI")
        }

        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(contentUri, mimeType)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        if (intent.resolveActivity(context.packageManager) == null) {
            throw IOException("No app can open this file type")
        }
        context.startActivity(intent)
    }

    private fun isInFetchioDownloads(uri: Uri): Boolean {
        val cursor = context.contentResolver.query(
            uri,
            arrayOf(MediaStore.MediaColumns.RELATIVE_PATH),
            null,
            null,
            null,
        ) ?: return false
        cursor.use {
            if (!it.moveToFirst()) return false
            val path = it.getString(0) ?: return false
            return path == "${Environment.DIRECTORY_DOWNLOADS}/$DOWNLOAD_FOLDER/"
        }
    }
}
