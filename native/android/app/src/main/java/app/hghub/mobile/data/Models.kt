package app.hghub.mobile.data

import org.json.JSONArray
import org.json.JSONObject

data class Author(val id: Int, val name: String, val avatar: String)

data class VideoCard(
    val id: Int,
    val title: String,
    val cover: String,
    val description: String,
    val tags: List<String>,
    val score: Double,
    val episodeCount: Int,
    val totalEpisodes: Int,
    val hot: Long,
    val likeCount: Int,
    val finished: Boolean,
    val author: Author?,
)

data class Episode(val ep: Int, val title: String, val duration: Int)

data class Detail(
    val id: Int,
    val title: String,
    val description: String,
    val cover: String,
    val tags: List<String>,
    val score: Double,
    val episodeCount: Int,
    val episodes: List<Episode>,
    val like: Int,
    val collect: Int,
    val comment: Int,
    val author: Author?,
    val liked: Boolean,
    val collected: Boolean,
    val videoUrl: String,
)

data class PlayInfo(
    val id: Int,
    val ep: Int,
    val title: String,
    val duration: Int,
    val videoUrl: String,
    val hevcUrl: String,
)

data class PageInfo(val page: Int, val pages: Int, val total: Int)

data class Comment(
    val id: Int,
    val nickname: String,
    val text: String,
    val time: String,
    val likeCount: Int,
)

data class RankItem(
    val rank: Int,
    val videoId: Int,
    val title: String,
    val cover: String,
    val tags: List<String>,
    val score: Double,
    val episodeCount: Int,
    val metricLabel: String,
    val metricValue: Long,
)

data class Post(
    val id: Int,
    val title: String,
    val desc: String,
    val cover: String,
    val tags: List<String>,
    val hot: Long,
    val content: String,
    val videoUrl: String,
)

data class Account(
    val id: Int,
    val username: String,
    val nickname: String,
    val avatar: String,
    val like: Int,
    val collect: Int,
    val following: Int,
)

data class Watch(val id: Int, val ep: Int, val t: Double, val dur: Double, val at: Long)

fun JSONObject.str(key: String): String = when (val v = opt(key)) {
    null, JSONObject.NULL -> ""
    is String -> v
    else -> v.toString()
}

fun JSONObject.int(key: String): Int = when (val v = opt(key)) {
    is Number -> v.toInt()
    is String -> v.toIntOrNull() ?: 0
    else -> 0
}

fun JSONObject.long(key: String): Long = when (val v = opt(key)) {
    is Number -> v.toLong()
    is String -> v.toLongOrNull() ?: 0L
    else -> 0L
}

fun JSONObject.dbl(key: String): Double = when (val v = opt(key)) {
    is Number -> v.toDouble()
    is String -> v.toDoubleOrNull() ?: 0.0
    else -> 0.0
}

fun JSONObject.bool(key: String): Boolean = when (val v = opt(key)) {
    is Boolean -> v
    is Number -> v.toInt() != 0
    is String -> v == "1" || v.equals("true", true)
    else -> false
}

fun JSONObject.strings(key: String): List<String> {
    val arr = optJSONArray(key) ?: return emptyList()
    return buildList {
        for (i in 0 until arr.length()) {
            val s = arr.optString(i)
            if (s.isNotBlank()) add(s)
        }
    }
}

fun JSONObject.obj(key: String): JSONObject? = optJSONObject(key)

private fun JSONObject.author(): Author? {
    val o = obj("author") ?: return null
    val name = o.str("name")
    if (name.isBlank() && o.int("id") == 0) return null
    return Author(o.int("id"), name, o.str("avatar"))
}

fun JSONObject.toCard(): VideoCard = VideoCard(
    id = int("id"),
    title = str("title"),
    cover = str("cover"),
    description = str("description"),
    tags = strings("tags"),
    score = dbl("score"),
    episodeCount = int("episode_count"),
    totalEpisodes = int("total_episodes"),
    hot = long("hot"),
    likeCount = int("like_count"),
    finished = bool("is_finished"),
    author = author(),
)

fun JSONObject.toDetail(): Detail {
    val counts = obj("counts")
    val interaction = obj("interaction")
    val eps = optJSONArray("episodes")
    val episodes = buildList {
        if (eps != null) {
            for (i in 0 until eps.length()) {
                val e = eps.optJSONObject(i) ?: continue
                add(Episode(e.int("ep_num"), e.str("title").ifBlank { "第${e.int("ep_num")}集" }, e.int("duration")))
            }
        }
    }
    return Detail(
        id = int("id"),
        title = str("title"),
        description = str("description"),
        cover = str("cover"),
        tags = strings("tags"),
        score = dbl("score"),
        episodeCount = int("episode_count"),
        episodes = episodes,
        like = counts?.int("like") ?: int("like_count"),
        collect = counts?.int("collect") ?: int("collect_count"),
        comment = counts?.int("comment") ?: obj("metrics")?.int("comment") ?: int("comment_count"),
        author = author(),
        liked = interaction?.bool("liked") == true,
        collected = interaction?.bool("collected") == true,
        videoUrl = str("video_url"),
    )
}

fun JSONObject.toPlay(): PlayInfo = PlayInfo(
    id = int("id"),
    ep = int("ep_num").let { if (it == 0) 1 else it },
    title = str("title"),
    duration = int("duration"),
    videoUrl = str("video_url"),
    hevcUrl = str("video_url_hevc"),
)

fun JSONObject.toPage(): PageInfo {
    val p = obj("pagination") ?: return PageInfo(1, 1, 0)
    return PageInfo(p.int("page").coerceAtLeast(1), p.int("pages").coerceAtLeast(1), p.int("total"))
}

fun JSONObject.items(): List<JSONObject> {
    val arr = optJSONArray("items") ?: return emptyList()
    return buildList {
        for (i in 0 until arr.length()) arr.optJSONObject(i)?.let { add(it) }
    }
}

fun JSONObject.toComment(): Comment = Comment(
    id = int("id"),
    nickname = str("nickname").ifBlank { "用户" },
    text = str("text").ifBlank { str("content") },
    time = str("time").ifBlank { str("created_at") },
    likeCount = int("like_count"),
)

fun JSONObject.toRank(): RankItem = RankItem(
    rank = int("rank"),
    videoId = int("video_id"),
    title = str("title"),
    cover = str("cover"),
    tags = strings("tags"),
    score = dbl("score"),
    episodeCount = int("episode_count"),
    metricLabel = str("metric_label"),
    metricValue = long("metric_value"),
)

fun JSONObject.toPost(): Post = Post(
    id = int("id"),
    title = str("title"),
    desc = str("desc"),
    cover = str("cover"),
    tags = strings("tags"),
    hot = long("hot"),
    content = str("content"),
    videoUrl = str("video_url"),
)

fun JSONObject.toAccount(): Account {
    val counts = obj("counts")
    return Account(
        id = int("id"),
        username = str("username"),
        nickname = str("nickname").ifBlank { str("username") },
        avatar = str("avatar"),
        like = counts?.int("like") ?: 0,
        collect = counts?.int("collect") ?: 0,
        following = counts?.int("following") ?: 0,
    )
}

fun Account.toJson(): JSONObject = JSONObject()
    .put("id", id)
    .put("username", username)
    .put("nickname", nickname)
    .put("avatar", avatar)
    .put("like", like)
    .put("collect", collect)
    .put("following", following)

fun accountFrom(raw: String?): Account? {
    if (raw.isNullOrBlank()) return null
    return runCatching { JSONObject(raw).toAccount() }.getOrNull()
}

fun watchesFrom(raw: String?): List<Watch> {
    if (raw.isNullOrBlank()) return emptyList()
    val arr = runCatching { JSONArray(raw) }.getOrNull() ?: return emptyList()
    return buildList {
        for (i in 0 until arr.length()) {
            val o = arr.optJSONObject(i) ?: continue
            val id = o.int("id")
            if (id <= 0) continue
            add(Watch(id, o.int("ep").coerceAtLeast(1), o.dbl("t"), o.dbl("dur"), o.long("at")))
        }
    }
}

fun List<Watch>.toJson(): String {
    val arr = JSONArray()
    for (w in this) {
        arr.put(JSONObject().put("id", w.id).put("ep", w.ep).put("t", w.t).put("dur", w.dur).put("at", w.at))
    }
    return arr.toString()
}

fun intsFrom(raw: String?): List<Int> {
    if (raw.isNullOrBlank()) return emptyList()
    val arr = runCatching { JSONArray(raw) }.getOrNull() ?: return emptyList()
    return buildList {
        for (i in 0 until arr.length()) {
            val n = arr.optInt(i)
            if (n > 0) add(n)
        }
    }
}

fun List<Int>.intsJson(): String = JSONArray(this).toString()

fun List<String>.stringsJson(): String = JSONArray(this).toString()

fun stringsFrom(raw: String?): List<String> {
    if (raw.isNullOrBlank()) return emptyList()
    val arr = runCatching { JSONArray(raw) }.getOrNull() ?: return emptyList()
    return buildList {
        for (i in 0 until arr.length()) {
            val s = arr.optString(i)
            if (s.isNotBlank()) add(s)
        }
    }
}

fun fmtCount(n: Long): String {
    val v = n.coerceAtLeast(0)
    return when {
        v >= 100_000_000 -> "${trimNum(v / 100_000_000.0)}亿"
        v >= 10_000 -> "${trimNum(v / 10_000.0)}万"
        else -> v.toString()
    }
}

fun fmtCount(n: Int): String = fmtCount(n.toLong())

private fun trimNum(v: Double): String {
    val s = String.format(java.util.Locale.US, "%.1f", v)
    return if (s.endsWith(".0")) s.dropLast(2) else s
}

fun fmtClock(sec: Double): String {
    val s = sec.coerceAtLeast(0.0).toInt()
    return "${s / 60}:${(s % 60).toString().padStart(2, '0')}"
}
