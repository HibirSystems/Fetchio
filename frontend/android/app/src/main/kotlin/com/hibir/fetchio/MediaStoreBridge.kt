package com.hibir.fetchio

import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream

/**
 * Handles saving a completed download from the app's private storage into the
 * Android MediaStore so it appears in the device's Downloads app and Gallery.
 *
 * On API 29+ we use [MediaStore.Downloads] (or Video/Audio collections).
 * On API < 29 we copy directly to the public external Downloads directory.
 */
class MediaStoreBridge(private val context: Context) :
    MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "com.hibir.fetchio/media_store"
    }

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

                try {
                    val publicPath = saveToDownloads(sourcePath, displayName, mimeType)
                    result.success(publicPath)
                } catch (e: Exception) {
                    result.error("SAVE_FAILED", e.message, null)
                }
            }

            else -> result.notImplemented()
        }
    }

    private fun saveToDownloads(
        sourcePath: String,
        displayName: String,
        mimeType: String,
    ): String {
        val sourceFile = File(sourcePath)
        if (!sourceFile.exists()) throw IllegalArgumentException("Source file not found: $sourcePath")

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            saveViaMediaStore(sourceFile, displayName, mimeType)
        } else {
            saveLegacy(sourceFile, displayName)
        }
    }

    /** API 29+: insert via MediaStore so the file is indexed immediately. */
    private fun saveViaMediaStore(
        sourceFile: File,
        displayName: String,
        mimeType: String,
    ): String {
        val collection = when {
            mimeType.startsWith("video/") ->
                MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            mimeType.startsWith("audio/") ->
                MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            else ->
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
                    MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
                else
                    MediaStore.Files.getContentUri("external")
        }

        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, displayName)
            put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath(mimeType))
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
        }

        val resolver = context.contentResolver
        val uri = resolver.insert(collection, values)
            ?: throw RuntimeException("MediaStore insert returned null")

        resolver.openOutputStream(uri)?.use { out ->
            FileInputStream(sourceFile).use { it.copyTo(out) }
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            values.clear()
            values.put(MediaStore.MediaColumns.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
        }

        return uri.toString()
    }

    /** API < 29: copy to the public external Downloads directory. */
    private fun saveLegacy(sourceFile: File, displayName: String): String {
        @Suppress("DEPRECATION")
        val downloadsDir = Environment.getExternalStoragePublicDirectory(
            Environment.DIRECTORY_DOWNLOADS
        )
        val destDir = File(downloadsDir, "Fetchio")
        destDir.mkdirs()
        val destFile = File(destDir, displayName)
        sourceFile.copyTo(destFile, overwrite = true)
        return destFile.absolutePath
    }

    private fun relativePath(mimeType: String): String = when {
        mimeType.startsWith("video/") -> "${Environment.DIRECTORY_MOVIES}/Fetchio/"
        mimeType.startsWith("audio/") -> "${Environment.DIRECTORY_MUSIC}/Fetchio/"
        else -> "${Environment.DIRECTORY_DOWNLOADS}/Fetchio/"
    }
}
