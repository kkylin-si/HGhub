package app.hghub.mobile.media

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.LruCache
import app.hghub.mobile.data.HgApi
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import javax.crypto.Cipher
import javax.crypto.spec.IvParameterSpec
import javax.crypto.spec.SecretKeySpec

/** 封面是 AES-128-CBC 密文，和桌面端同一套 key / iv。 */
object Covers {
    private val key = "f5d965df75336270".toByteArray()
    private val iv = "97b60394abc2fbe1".toByteArray()
    private val mem = LruCache<String, Bitmap>(48)

    fun peek(url: String): Bitmap? = if (url.isBlank()) null else mem.get(url)

    fun clear() = mem.evictAll()

    suspend fun load(api: HgApi, url: String): Bitmap? {
        if (url.isBlank()) return null
        mem.get(url)?.let { return it }
        return withContext(Dispatchers.IO) {
            mem.get(url)?.let { return@withContext it }
            val raw = runCatching { api.bytes(url) }.getOrNull() ?: return@withContext null
            val plain = if (isImage(raw)) raw else decrypt(raw) ?: return@withContext null
            val bmp = decode(plain) ?: return@withContext null
            mem.put(url, bmp)
            bmp
        }
    }

    private fun decrypt(data: ByteArray): ByteArray? {
        if (data.isEmpty() || data.size % 16 != 0) return null
        return runCatching {
            val cipher = Cipher.getInstance("AES/CBC/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "AES"), IvParameterSpec(iv))
            unpad(cipher.doFinal(data))
        }.getOrNull()
    }

    private fun unpad(buf: ByteArray): ByteArray {
        if (buf.isEmpty()) return buf
        val pad = buf.last().toInt() and 0xFF
        if (pad in 1..16 && buf.size >= pad && buf.takeLast(pad).all { (it.toInt() and 0xFF) == pad }) {
            return buf.copyOf(buf.size - pad)
        }
        return buf
    }

    private fun isImage(buf: ByteArray): Boolean {
        if (buf.size < 12) return false
        if (buf[0] == 0xFF.toByte() && buf[1] == 0xD8.toByte()) return true
        if (buf[0] == 0x89.toByte() && buf[1] == 0x50.toByte()) return true
        if (buf.copyOfRange(0, 4).decodeToString() == "GIF8") return true
        return buf.copyOfRange(0, 4).decodeToString() == "RIFF" && buf.copyOfRange(8, 12).decodeToString() == "WEBP"
    }

    private fun decode(bytes: ByteArray): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        var sample = 1
        val max = maxOf(bounds.outWidth, bounds.outHeight)
        while (max / sample > 1080) sample *= 2
        val opts = BitmapFactory.Options().apply { inSampleSize = sample }
        return BitmapFactory.decodeByteArray(bytes, 0, bytes.size, opts)
    }
}
