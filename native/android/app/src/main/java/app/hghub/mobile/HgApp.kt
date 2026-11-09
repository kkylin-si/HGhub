package app.hghub.mobile

import android.app.Application
import androidx.compose.runtime.staticCompositionLocalOf
import app.hghub.mobile.data.AppStore
import app.hghub.mobile.data.HgApi
import app.hghub.mobile.data.VideoCard

class HgApp : Application() {
    lateinit var store: AppStore
        private set
    lateinit var api: HgApi
        private set

    override fun onCreate() {
        super.onCreate()
        store = AppStore(this)
        api = HgApi(store)
    }
}

val LocalApp = staticCompositionLocalOf<HgApp> { error("HgApp 未就绪") }

/** 列表里见过的卡片，播放页用来先显示标题和封面。 */
object Library {
    private val map = linkedMapOf<Int, VideoCard>()
    fun put(items: List<VideoCard>) {
        items.forEach { map[it.id] = it }
        while (map.size > 400) {
            val first = map.keys.firstOrNull() ?: break
            map.remove(first)
        }
    }
    fun get(id: Int): VideoCard? = map[id]
}
