package de.ueen.antpod

import android.content.Context
import android.database.Cursor
import android.database.MatrixCursor
import android.os.CancellationSignal
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract.Document
import android.provider.DocumentsContract.Root
import android.provider.DocumentsProvider
import android.webkit.MimeTypeMap
import java.io.File
import java.io.FileNotFoundException

/**
 * The downloaded episodes as a place in the system's Files app (and in other
 * apps' file pickers asking for audio), read-only: the app keeps track of
 * its downloads, so files can be opened and copied but not changed here.
 */
class EpisodesProvider : DocumentsProvider() {
    companion object {
        /** The root and its one folder share this id; files are "episodes/<name>". */
        const val ROOT = "episodes"

        /** Where the app downloads to: getApplicationDocumentsDirectory()/episodes. */
        fun dir(context: Context) = File(context.getDir("flutter", Context.MODE_PRIVATE), "episodes")

        private val ROOT_COLUMNS = arrayOf(
            Root.COLUMN_ROOT_ID, Root.COLUMN_DOCUMENT_ID, Root.COLUMN_TITLE,
            Root.COLUMN_SUMMARY, Root.COLUMN_ICON, Root.COLUMN_FLAGS, Root.COLUMN_MIME_TYPES,
        )
        private val DOCUMENT_COLUMNS = arrayOf(
            Document.COLUMN_DOCUMENT_ID, Document.COLUMN_DISPLAY_NAME, Document.COLUMN_MIME_TYPE,
            Document.COLUMN_SIZE, Document.COLUMN_LAST_MODIFIED, Document.COLUMN_FLAGS,
        )
    }

    override fun onCreate() = true

    override fun queryRoots(projection: Array<out String>?): Cursor =
        MatrixCursor(projection ?: ROOT_COLUMNS).apply {
            newRow()
                .add(Root.COLUMN_ROOT_ID, ROOT)
                .add(Root.COLUMN_DOCUMENT_ID, ROOT)
                .add(Root.COLUMN_TITLE, "AntPod")
                .add(Root.COLUMN_SUMMARY, context!!.getString(R.string.episodes_root_summary))
                .add(Root.COLUMN_ICON, R.mipmap.ic_launcher)
                .add(Root.COLUMN_FLAGS, Root.FLAG_LOCAL_ONLY)
                // Only pickers asking for audio list it.
                .add(Root.COLUMN_MIME_TYPES, "audio/*")
        }

    override fun queryDocument(documentId: String, projection: Array<out String>?): Cursor =
        MatrixCursor(projection ?: DOCUMENT_COLUMNS).apply {
            addRow(documentId, fileFor(documentId))
        }

    override fun queryChildDocuments(
        parentDocumentId: String,
        projection: Array<out String>?,
        sortOrder: String?,
    ): Cursor {
        if (parentDocumentId != ROOT) throw FileNotFoundException(parentDocumentId)
        return MatrixCursor(projection ?: DOCUMENT_COLUMNS).apply {
            dir(context!!).listFiles()
                ?.filter { it.isFile && !it.name.startsWith(".") }
                ?.sortedByDescending { it.lastModified() }
                ?.forEach { addRow("$ROOT/${it.name}", it) }
        }
    }

    override fun openDocument(
        documentId: String,
        mode: String,
        signal: CancellationSignal?,
    ): ParcelFileDescriptor {
        if ('w' in mode || 'a' in mode) throw FileNotFoundException("read-only: $documentId")
        return ParcelFileDescriptor.open(fileFor(documentId), ParcelFileDescriptor.MODE_READ_ONLY)
    }

    private fun MatrixCursor.addRow(id: String, file: File) {
        val folder = id == ROOT
        newRow()
            .add(Document.COLUMN_DOCUMENT_ID, id)
            .add(Document.COLUMN_DISPLAY_NAME, if (folder) "AntPod" else file.name)
            .add(Document.COLUMN_MIME_TYPE, if (folder) Document.MIME_TYPE_DIR else mimeOf(file))
            .add(Document.COLUMN_SIZE, if (folder) null else file.length())
            .add(Document.COLUMN_LAST_MODIFIED, file.lastModified())
            .add(Document.COLUMN_FLAGS, 0)
    }

    private fun mimeOf(file: File) =
        MimeTypeMap.getSingleton().getMimeTypeFromExtension(file.extension.lowercase())
            ?: "audio/mpeg"

    /** The file behind [id], never one outside the downloads folder. */
    private fun fileFor(id: String): File {
        val dir = dir(context!!)
        if (id == ROOT) return dir
        val name = id.removePrefix("$ROOT/")
        if (name == id || name.isEmpty() || '/' in name || name == "..") {
            throw FileNotFoundException(id)
        }
        val file = File(dir, name)
        if (!file.isFile) throw FileNotFoundException(id)
        return file
    }
}
