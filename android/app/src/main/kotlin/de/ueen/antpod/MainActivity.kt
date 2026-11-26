package de.ueen.antpod

import android.content.ActivityNotFoundException
import android.content.Intent
import android.provider.DocumentsContract
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Adds the "antpod/files" channel:
 *   saveFile(name, mime, path)  lets the user pick where to save a copy of
 *                               [path] (file_selector can't save on Android);
 *                               true when saved, false when cancelled.
 *   openDownloads()             opens the downloaded episodes in the Files
 *                               app ([EpisodesProvider]); false when no app
 *                               could.
 */
class MainActivity : AudioServiceActivity() {
    companion object {
        private const val SAVE_REQUEST = 0x5A7E
    }

    /** The file being saved and the call waiting for the picker. */
    private var pendingSave: Pair<File, MethodChannel.Result>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "antpod/files")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveFile" -> saveFile(
                        call.argument<String>("name")!!,
                        call.argument<String>("mime")!!,
                        call.argument<String>("path")!!,
                        result,
                    )
                    "openDownloads" -> result.success(openDownloads())
                    else -> result.notImplemented()
                }
            }
    }

    private fun saveFile(name: String, mime: String, path: String, result: MethodChannel.Result) {
        pendingSave?.second?.success(false)
        pendingSave = File(path) to result
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT)
            .addCategory(Intent.CATEGORY_OPENABLE)
            .setType(mime)
            .putExtra(Intent.EXTRA_TITLE, name)
        try {
            startActivityForResult(intent, SAVE_REQUEST)
        } catch (e: ActivityNotFoundException) {
            pendingSave = null
            result.error("no_picker", e.message, null)
        }
    }

    @Deprecated("FlutterActivity is no ComponentActivity: no result API")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != SAVE_REQUEST) return
        val (file, result) = pendingSave ?: return
        pendingSave = null
        val uri = data?.data
        if (resultCode != RESULT_OK || uri == null) {
            result.success(false)
            return
        }
        Thread {
            val error = try {
                contentResolver.openOutputStream(uri, "w")!!.use { out ->
                    file.inputStream().use { it.copyTo(out) }
                }
                null
            } catch (e: Exception) {
                e
            }
            runOnUiThread {
                if (error == null) result.success(true)
                else result.error("write_failed", error.message, null)
            }
        }.start()
    }

    /** The Files app at AntPod's place, else at its folder. */
    private fun openDownloads(): Boolean {
        val authority = "$packageName.episodes"
        EpisodesProvider.dir(this).mkdirs()
        val targets = listOf(
            DocumentsContract.buildRootUri(authority, EpisodesProvider.ROOT) to
                DocumentsContract.Root.MIME_TYPE_ITEM,
            DocumentsContract.buildDocumentUri(authority, EpisodesProvider.ROOT) to
                DocumentsContract.Document.MIME_TYPE_DIR,
        )
        for ((uri, type) in targets) {
            try {
                startActivity(
                    Intent(Intent.ACTION_VIEW)
                        .setDataAndType(uri, type)
                        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION),
                )
                return true
            } catch (e: ActivityNotFoundException) {
                // Try the next one.
            }
        }
        return false
    }
}
