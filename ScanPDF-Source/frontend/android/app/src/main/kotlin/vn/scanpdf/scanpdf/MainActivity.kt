package vn.scanpdf.scanpdf

import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.Executors
import kotlin.math.max

class MainActivity : FlutterActivity() {
    private val renderer = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "vn.scanpdf/pdf")
            .setMethodCallHandler { call, result ->
                if (call.method != "render") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val path = call.argument<String>("path")
                val page = call.argument<Int>("page")
                if (path == null || page == null) {
                    result.error("INVALID_PDF", null, null)
                    return@setMethodCallHandler
                }
                renderer.execute {
                    try {
                        val file = File(path).canonicalFile
                        val root = File(cacheDir, "scanpdf-cloud").canonicalPath
                        require(file.path.startsWith(root + File.separator))
                        val bytes = renderPage(file, page)
                        runOnUiThread { result.success(bytes) }
                    } catch (_: Exception) {
                        runOnUiThread { result.error("INVALID_PDF", null, null) }
                    }
                }
            }
    }

    override fun onDestroy() {
        renderer.shutdown()
        super.onDestroy()
    }

    private fun renderPage(file: File, index: Int): ByteArray {
        ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY).use { input ->
            PdfRenderer(input).use { pdf ->
                pdf.openPage(index).use { page ->
                    val scale = 1440f / max(page.width, page.height)
                    val width = max(1, (page.width * scale).toInt())
                    val height = max(1, (page.height * scale).toInt())
                    val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                    try {
                        bitmap.eraseColor(Color.WHITE)
                        page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                        return ByteArrayOutputStream().use { output ->
                            check(bitmap.compress(Bitmap.CompressFormat.JPEG, 88, output))
                            output.toByteArray()
                        }
                    } finally {
                        bitmap.recycle()
                    }
                }
            }
        }
    }
}
