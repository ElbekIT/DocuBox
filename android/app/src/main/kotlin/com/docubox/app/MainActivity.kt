package com.docubox.app

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.docubox.app/file_intent"
    private var initialFilePath: String? = null
    private var methodChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialFile" -> {
                    val path = initialFilePath
                    initialFilePath = null
                    result.success(path)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun handleIntent(intent: Intent?) {
        if (intent == null) return
        val action = intent.action
        val uri: Uri? = if (Intent.ACTION_VIEW == action) {
            intent.data
        } else if (Intent.ACTION_SEND == action) {
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
                intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra(Intent.EXTRA_STREAM)
            }
        } else {
            null
        }

        if (uri != null) {
            val localPath = copyUriToInternalStorage(uri)
            if (localPath != null) {
                initialFilePath = localPath
                methodChannel?.invokeMethod("onFileReceived", localPath)
            }
        }
    }

    private fun copyUriToInternalStorage(uri: Uri): String? {
        return try {
            if ("file".equals(uri.scheme, ignoreCase = true)) {
                return uri.path
            }

            var fileName = "document_${System.currentTimeMillis()}"
            try {
                contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                    val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (nameIndex != -1 && cursor.moveToFirst()) {
                        val name = cursor.getString(nameIndex)
                        if (!name.isNullOrBlank()) {
                            fileName = name
                        }
                    }
                }
            } catch (e: Exception) {
                // Ignore cursor query error
            }

            if (fileName.startsWith("document_")) {
                val lastSegment = uri.lastPathSegment
                if (!lastSegment.isNullOrBlank()) {
                    val segmentName = lastSegment.substringAfterLast('/')
                    if (segmentName.isNotBlank()) {
                        fileName = segmentName
                    }
                }
            }

            val targetDir = File(cacheDir, "incoming_files")
            if (!targetDir.exists()) {
                targetDir.mkdirs()
            }

            val targetFile = File(targetDir, fileName)
            contentResolver.openInputStream(uri)?.use { inputStream ->
                FileOutputStream(targetFile).use { outputStream ->
                    inputStream.copyTo(outputStream)
                }
            }
            targetFile.absolutePath
        } catch (e: Exception) {
            e.printStackTrace()
            null
        }
    }
}
