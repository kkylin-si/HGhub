package app.hghub.mobile.ui

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.content.pm.ActivityInfo
import android.view.ViewGroup
import androidx.annotation.OptIn
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.pager.VerticalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.outlined.ChatBubbleOutline
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.outlined.FavoriteBorder
import androidx.compose.material.icons.filled.Fullscreen
import androidx.compose.material.icons.filled.FullscreenExit
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.outlined.List
import androidx.compose.material.icons.outlined.StarOutline
import androidx.compose.material.icons.outlined.VolumeOff
import androidx.compose.material.icons.outlined.VolumeUp
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import androidx.activity.compose.BackHandler
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import app.hghub.mobile.Library
import app.hghub.mobile.LocalApp
import app.hghub.mobile.data.Comment
import app.hghub.mobile.data.Detail
import app.hghub.mobile.data.fmtClock
import app.hghub.mobile.data.fmtCount
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

private val speeds = floatArrayOf(1f, 1.25f, 1.5f, 2f)

@OptIn(UnstableApi::class)
@kotlin.OptIn(ExperimentalMaterial3Api::class)
@Composable
fun VideoFeed(
    ids: List<Int>,
    start: Int,
    startEp: Int,
    startTimeSec: Double,
    onBack: (() -> Unit)?,
    onNearEnd: (() -> Unit)?,
) {
    val app = LocalApp.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val base = app.store.base
    if (ids.isEmpty()) {
        EmptyHint("暂无视频", "下拉列表为空", "返回", onBack)
        return
    }
    val pager = rememberPagerState(
        initialPage = start.coerceIn(0, ids.lastIndex),
        pageCount = { ids.size },
    )
    val player = remember(base) {
        val headers = mapOf("Referer" to base.trimEnd('/') + "/", "Origin" to base.trimEnd('/'))
        val dataSource = DefaultHttpDataSource.Factory()
            .setUserAgent(HgApiUa)
            .setDefaultRequestProperties(headers)
            .setAllowCrossProtocolRedirects(true)
        ExoPlayer.Builder(context)
            .setMediaSourceFactory(DefaultMediaSourceFactory(dataSource))
            .build()
            .apply {
                playWhenReady = true
                volume = if (app.store.muted) 0f else 1f
            }
    }
    DisposableEffect(player) { onDispose { player.release() } }

    var pos by remember { mutableLongStateOf(0L) }
    var dur by remember { mutableLongStateOf(0L) }
    var buffering by remember { mutableStateOf(true) }
    var failed by remember { mutableStateOf("") }
    var paused by remember { mutableStateOf(false) }
    var speedIndex by remember { mutableIntStateOf(0) }
    var sheet by remember { mutableStateOf<SheetKind?>(null) }
    var detail by remember { mutableStateOf<Detail?>(null) }
    var ep by remember(ids.getOrNull(pager.currentPage)) { mutableIntStateOf(if (pager.currentPage == start) startEp.coerceAtLeast(1) else 1) }
    val comments = remember { androidx.compose.runtime.mutableStateListOf<Comment>() }
    var commentText by remember { mutableStateOf("") }
    var resume by remember { mutableStateOf(if (startTimeSec > 1) startTimeSec else 0.0) }
    var ticket by remember { mutableIntStateOf(0) }
    var fullscreen by remember { mutableStateOf(false) }
    var hevcUrl by remember { mutableStateOf("") }

    DisposableEffect(player) {
        val listener = object : Player.Listener {
            override fun onPlaybackStateChanged(state: Int) {
                buffering = state == Player.STATE_BUFFERING || state == Player.STATE_IDLE
                if (state == Player.STATE_READY && resume > 0.3) {
                    player.seekTo((resume * 1000).toLong())
                    resume = 0.0
                }
            }
            override fun onPlayerError(error: PlaybackException) {
                if (app.store.preferHevc && hevcUrl.isNotBlank()) {
                    val stay = player.currentPosition
                    if (stay > 300) resume = stay / 1000.0
                    app.store.applyPreferHevc(false)
                    app.store.show("高清暂时播不了，已切回标准")
                    failed = ""
                } else {
                    failed = "这一集暂时播不了，可换线路或重试"
                    buffering = false
                }
            }
            override fun onIsPlayingChanged(isPlaying: Boolean) {
                paused = !isPlaying && player.playbackState == Player.STATE_READY
            }
        }
        player.addListener(listener)
        onDispose { player.removeListener(listener) }
    }

    val lifecycle = LocalLifecycleOwner.current.lifecycle
    DisposableEffect(lifecycle, player) {
        val obs = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_STOP) player.pause()
        }
        lifecycle.addObserver(obs)
        onDispose { lifecycle.removeObserver(obs) }
    }

    LaunchedEffect(player) {
        while (true) {
            pos = player.currentPosition.coerceAtLeast(0L)
            val d = player.duration
            dur = if (d > 0) d else 0L
            val id = ids.getOrNull(pager.currentPage) ?: 0
            if (id > 0 && dur > 0 && pos > 800) {
                app.store.saveWatch(id, ep, pos / 1000.0, dur / 1000.0)
            }
            delay(800)
        }
    }

    LaunchedEffect(pager.currentPage, ids.size) {
        if (pager.currentPage >= ids.size - 2) onNearEnd?.invoke()
    }

    val currentId = ids[pager.currentPage.coerceIn(0, ids.lastIndex)]
    BackHandler(enabled = fullscreen) { fullscreen = false }

    DisposableEffect(fullscreen) {
        val activity = context.findActivity()
        val window = activity?.window
        activity?.requestedOrientation = if (fullscreen) {
            ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
        } else {
            ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
        }
        val controller = window?.let { WindowCompat.getInsetsController(it, it.decorView) }
        if (fullscreen) {
            controller?.hide(WindowInsetsCompat.Type.systemBars())
            controller?.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        } else {
            controller?.show(WindowInsetsCompat.Type.systemBars())
        }
        app.store.immersive = fullscreen
        onDispose {
            app.store.immersive = false
            activity?.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
            if (window != null) {
                WindowCompat.getInsetsController(window, window.decorView).show(WindowInsetsCompat.Type.systemBars())
            }
        }
    }

    LaunchedEffect(currentId, ep, base, ticket, app.store.preferHevc) {
        failed = ""
        buffering = true
        val loaded = runCatching {
            val d = app.api.video(currentId)
            val play = app.api.play(currentId, ep)
            d to play
        }
        val pair = loaded.getOrElse {
            failed = it.message ?: "加载失败"
            buffering = false
            return@LaunchedEffect
        }
        detail = pair.first
        if (pair.first.liked && !app.store.isLiked(currentId)) app.store.toggleLike(currentId)
        if (pair.first.collected && !app.store.isFav(currentId)) app.store.toggleFav(currentId)
        hevcUrl = pair.second.hevcUrl
        val standard = pair.second.videoUrl.ifBlank { pair.first.videoUrl }
        val url = if (app.store.preferHevc && pair.second.hevcUrl.isNotBlank()) pair.second.hevcUrl else standard
        if (url.isBlank()) {
            failed = "没有可播放的地址"
            buffering = false
            return@LaunchedEffect
        }
        player.setMediaItem(MediaItem.fromUri(url))
        player.prepare()
        player.playWhenReady = true
        player.setPlaybackSpeed(speeds[speedIndex])
        player.volume = if (app.store.muted) 0f else 1f
    }

    Box(Modifier.fillMaxSize().background(Color.Black)) {
        VerticalPager(state = pager, modifier = Modifier.fillMaxSize()) { page ->
            val id = ids[page]
            val card = Library.get(id)
            val active = page == pager.currentPage
            Box(Modifier.fillMaxSize()) {
                if (active) {
                    AndroidView(
                        factory = { ctx ->
                            PlayerView(ctx).apply {
                                useController = false
                                this.player = player
                                resizeMode = AspectRatioFrameLayout.RESIZE_MODE_ZOOM
                                layoutParams = ViewGroup.LayoutParams(
                                    ViewGroup.LayoutParams.MATCH_PARENT,
                                    ViewGroup.LayoutParams.MATCH_PARENT,
                                )
                                setShutterBackgroundColor(android.graphics.Color.BLACK)
                            }
                        },
                        modifier = Modifier.fillMaxSize(),
                        update = {
                            it.player = player
                            it.resizeMode = if (fullscreen) {
                                AspectRatioFrameLayout.RESIZE_MODE_FIT
                            } else {
                                AspectRatioFrameLayout.RESIZE_MODE_ZOOM
                            }
                        },
                    )
                } else {
                    CoverImage(card?.cover.orEmpty(), Modifier.fillMaxSize(), 0.dp)
                }
                Box(
                    Modifier.fillMaxSize().pointerInput(active) {
                        if (!active) return@pointerInput
                        detectTapGestures(onTap = {
                            if (player.isPlaying) player.pause() else player.play()
                        })
                    },
                )
            }
        }

        Box(
            Modifier.fillMaxWidth().height(160.dp).align(Alignment.BottomCenter).background(
                Brush.verticalGradient(listOf(Color.Transparent, Color(0xCC000000))),
            ),
        )

        val title = detail?.title ?: Library.get(currentId)?.title.orEmpty()
        val desc = detail?.description ?: Library.get(currentId)?.description.orEmpty()
        val tags = detail?.tags ?: Library.get(currentId)?.tags.orEmpty()

        val fraction = if (dur > 0) (pos.toFloat() / dur.toFloat()).coerceIn(0f, 1f) else 0f
        Column(
            Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
                .then(if (onBack != null || fullscreen) Modifier.navigationBarsPadding() else Modifier)
                .padding(bottom = if (fullscreen) 28.dp else 8.dp),
        ) {
            Box(
                Modifier
                    .padding(horizontal = 16.dp)
                    .fillMaxWidth()
                    .height(28.dp)
                    .pointerInput(dur) {
                        detectTapGestures { offset ->
                            if (dur > 0) player.seekTo((offset.x / size.width * dur).toLong())
                        }
                    },
            ) {
                Box(Modifier.align(Alignment.CenterStart).fillMaxWidth().height(3.dp).background(Color(0x55FFFFFF)))
                Box(Modifier.align(Alignment.CenterStart).fillMaxWidth(fraction).height(3.dp).background(Color(0xFFE08A6E)))
            }
            if (!fullscreen) {
                Column(Modifier.padding(start = 16.dp, end = 72.dp, top = 6.dp, bottom = 8.dp)) {
                    Text(title, color = Color.White, fontFamily = Serif, fontSize = 22.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
                    if (tags.isNotEmpty()) {
                        Spacer(Modifier.height(8.dp))
                        Text(tags.take(3).joinToString("  ·  "), color = Color(0xFFE7D2C8), fontSize = 12.sp)
                    }
                    if (desc.isNotBlank()) {
                        Spacer(Modifier.height(6.dp))
                        Text(desc.replace('\n', ' '), color = Color(0xD9FFFFFF), fontSize = 13.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
                    }
                    Spacer(Modifier.height(8.dp))
                    Text(
                        "第 $ep 集   ${fmtClock(pos / 1000.0)} / ${fmtClock(dur / 1000.0)}",
                        color = Color(0xCCFFFFFF),
                        fontSize = 12.sp,
                    )
                }
            }
        }

        if (!fullscreen) {
        Column(
            Modifier.align(Alignment.CenterEnd).navigationBarsPadding().padding(end = 10.dp, bottom = 72.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            val liked = app.store.isLiked(currentId)
            val faved = app.store.isFav(currentId)
            RailButton(if (liked) Icons.Filled.Favorite else Icons.Outlined.FavoriteBorder, if (liked) Color(0xFFE08A6E) else Color.White, fmtCount(detail?.like ?: Library.get(currentId)?.likeCount ?: 0)) {
                val on = app.store.toggleLike(currentId)
                if (app.store.loggedIn) scope.launch { runCatching { app.api.like(currentId, ep, on) } }
            }
            RailButton(if (faved) Icons.Filled.Star else Icons.Outlined.StarOutline, if (faved) Color(0xFFE08A6E) else Color.White, "收藏") {
                val on = app.store.toggleFav(currentId)
                if (app.store.loggedIn) scope.launch { runCatching { app.api.collect(currentId, on) } }
                app.store.show(if (on) "已收藏" else "已取消收藏")
            }
            RailButton(Icons.Outlined.List, Color.White, "选集") { sheet = SheetKind.Episodes }
            RailButton(Icons.Outlined.ChatBubbleOutline, Color.White, "评论") {
                sheet = SheetKind.Comments
                scope.launch {
                    comments.clear()
                    runCatching { app.api.comments(currentId, ep, 1) }.onSuccess { comments.addAll(it.first) }
                }
            }
        }
        }

        Row(
            Modifier.align(Alignment.TopStart).statusBarsPadding().padding(horizontal = 8.dp, vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (onBack != null) {
                Icon(Icons.Filled.ArrowBack, "返回", tint = Color.White, modifier = Modifier.size(40.dp).clickable { onBack() }.padding(8.dp))
            } else {
                Text("HGhub", color = Color.White, fontFamily = Serif, fontSize = 22.sp, modifier = Modifier.padding(start = 8.dp))
            }
            Spacer(Modifier.weight(1f))
            if (hevcUrl.isNotBlank()) {
                Text(
                    if (app.store.preferHevc) "高清" else "标准",
                    color = Color.White,
                    fontSize = 13.sp,
                    modifier = Modifier
                        .clip(RoundedCornerShape(999.dp))
                        .background(Color(0x66000000))
                        .clickable {
                            val stay = player.currentPosition
                            if (stay > 300) resume = stay / 1000.0
                            app.store.applyPreferHevc(!app.store.preferHevc)
                        }
                        .padding(horizontal = 12.dp, vertical = 6.dp),
                )
                Spacer(Modifier.width(8.dp))
            }
            Icon(
                if (fullscreen) Icons.Filled.FullscreenExit else Icons.Filled.Fullscreen,
                if (fullscreen) "退出全屏" else "全屏",
                tint = Color.White,
                modifier = Modifier.size(40.dp).clickable { fullscreen = !fullscreen }.padding(8.dp),
            )
            Text(
                "${speeds[speedIndex]}x",
                color = Color.White,
                fontSize = 13.sp,
                modifier = Modifier
                    .clip(RoundedCornerShape(999.dp))
                    .background(Color(0x66000000))
                    .clickable {
                        speedIndex = (speedIndex + 1) % speeds.size
                        player.setPlaybackSpeed(speeds[speedIndex])
                    }
                    .padding(horizontal = 12.dp, vertical = 6.dp),
            )
            Spacer(Modifier.width(8.dp))
            Icon(
                if (app.store.muted) Icons.Outlined.VolumeOff else Icons.Outlined.VolumeUp,
                "静音",
                tint = Color.White,
                modifier = Modifier.size(40.dp).clickable {
                    val next = !app.store.muted
                    app.store.applyMuted(next)
                    player.volume = if (next) 0f else 1f
                }.padding(8.dp),
            )
        }

        if (paused && failed.isBlank()) {
            Icon(Icons.Filled.PlayArrow, null, tint = Color.White, modifier = Modifier.size(72.dp).align(Alignment.Center))
        }
        if (buffering && failed.isBlank()) {
            CircularProgressIndicator(color = Color(0xFFE08A6E), strokeWidth = 2.dp, modifier = Modifier.align(Alignment.Center))
        }
        if (failed.isNotBlank()) {
            Column(Modifier.align(Alignment.Center).padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Text(failed, color = Color.White, fontSize = 14.sp)
                Spacer(Modifier.height(12.dp))
                Text(
                    "重试",
                    color = Color(0xFF2A120C),
                    modifier = Modifier.clip(RoundedCornerShape(12.dp)).background(Color(0xFFE08A6E)).clickable {
                        ticket += 1
                    }.padding(horizontal = 16.dp, vertical = 8.dp),
                )
            }
        }

    }

    if (sheet != null) {
        ModalBottomSheet(
            onDismissRequest = { sheet = null },
            sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
            containerColor = LocalHg.current.paper,
        ) {
            when (sheet) {
                SheetKind.Episodes -> EpisodeSheet(detail, ep) { next ->
                    sheet = null
                    resume = 0.0
                    ep = next
                }
                SheetKind.Comments -> CommentSheet(comments, commentText, { commentText = it }) {
                    val text = commentText.trim()
                    if (text.isEmpty()) return@CommentSheet
                    if (!app.store.loggedIn) {
                        app.store.show("登录后才能评论")
                        return@CommentSheet
                    }
                    scope.launch {
                        runCatching { app.api.sendComment(currentId, ep, text) }
                            .onSuccess {
                                commentText = ""
                                app.store.show("已发送")
                                runCatching { app.api.comments(currentId, ep, 1) }.onSuccess {
                                    comments.clear()
                                    comments.addAll(it.first)
                                }
                            }
                            .onFailure { app.store.show(it.message ?: "发送失败") }
                    }
                }
                null -> Unit
            }
            Spacer(Modifier.navigationBarsPadding())
        }
    }
}

private enum class SheetKind { Episodes, Comments }

private fun Context.findActivity(): Activity? {
    var current: Context = this
    while (current is ContextWrapper) {
        if (current is Activity) return current
        current = current.baseContext
    }
    return null
}

private const val HgApiUa =
    "Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36"

@Composable
private fun RailButton(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    tint: Color,
    label: String,
    onClick: () -> Unit,
) {
    Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.clickable { onClick() }) {
        Icon(icon, label, tint = tint, modifier = Modifier.size(28.dp))
        Text(label, color = Color.White, fontSize = 11.sp)
    }
}

@Composable
private fun EpisodeSheet(detail: Detail?, current: Int, onPick: (Int) -> Unit) {
    val c = LocalHg.current
    val eps = detail?.episodes.orEmpty()
    Column(Modifier.fillMaxWidth().padding(horizontal = 20.dp)) {
        Text(detail?.title ?: "选集", color = c.ink, fontFamily = Serif, fontSize = 22.sp)
        Spacer(Modifier.height(12.dp))
        if (eps.isEmpty()) {
            Text("选集加载中", color = c.muted)
        } else {
            LazyColumn(Modifier.height(360.dp)) {
                items(eps, key = { it.ep }) { e ->
                    val on = e.ep == current
                    Row(
                        Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(if (on) c.soft else Color.Transparent)
                            .clickable { onPick(e.ep) }.padding(horizontal = 12.dp, vertical = 12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(if (on) "正在播放" else "第 ${e.ep} 集", color = if (on) c.accent else c.muted, fontSize = 12.sp, modifier = Modifier.width(72.dp))
                        Text(e.title, color = c.ink, fontSize = 15.sp, modifier = Modifier.weight(1f))
                        if (on) Icon(Icons.Filled.Pause, null, tint = c.accent, modifier = Modifier.size(16.dp))
                    }
                }
            }
        }
        Spacer(Modifier.height(12.dp))
    }
}

@Composable
private fun CommentSheet(
    comments: List<Comment>,
    draft: String,
    onDraft: (String) -> Unit,
    onSend: () -> Unit,
) {
    val c = LocalHg.current
    Column(Modifier.fillMaxWidth().padding(horizontal = 20.dp)) {
        Text("评论", color = c.ink, fontFamily = Serif, fontSize = 22.sp)
        Spacer(Modifier.height(8.dp))
        LazyColumn(Modifier.height(280.dp)) {
            if (comments.isEmpty()) {
                item { Text("还没有评论", color = c.muted, modifier = Modifier.padding(vertical = 24.dp)) }
            }
            items(comments, key = { it.id }) { item ->
                Column(Modifier.fillMaxWidth().padding(vertical = 8.dp)) {
                    Text(item.nickname, color = c.ink, fontWeight = FontWeight.SemiBold, fontSize = 13.sp)
                    Text(item.text, color = c.ink, fontSize = 14.sp)
                    Text(item.time, color = c.faint, fontSize = 11.sp)
                }
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            TextField(
                value = draft,
                onValueChange = onDraft,
                placeholder = { Text("说点什么") },
                modifier = Modifier.weight(1f),
                colors = TextFieldDefaults.colors(
                    focusedContainerColor = c.card,
                    unfocusedContainerColor = c.card,
                    focusedIndicatorColor = Color.Transparent,
                    unfocusedIndicatorColor = Color.Transparent,
                ),
            )
            Spacer(Modifier.width(8.dp))
            Text(
                "发送",
                color = c.onAccent,
                modifier = Modifier.clip(RoundedCornerShape(12.dp)).background(c.accent).clickable { onSend() }.padding(horizontal = 14.dp, vertical = 10.dp),
            )
        }
        Spacer(Modifier.height(8.dp))
    }
}

@Composable
fun HomeFeed(onOpenSearch: () -> Unit) {
    val app = LocalApp.current
    val scope = rememberCoroutineScope()
    var items by remember { mutableStateOf(HomeCache.items) }
    var page by remember { mutableIntStateOf(HomeCache.page) }
    var done by remember { mutableStateOf(HomeCache.done) }
    var loading by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf("") }

    suspend fun load(next: Int) {
        if (loading || done && next != 1) return
        loading = true
        error = ""
        val result = runCatching { app.api.feed(next, 8) }
        loading = false
        result.onSuccess { (list, info) ->
            Library.put(list)
            items = if (next == 1) list else (items + list).distinctBy { it.id }
            page = next
            done = list.isEmpty() || next >= info.pages
            HomeCache.items = items
            HomeCache.page = page
            HomeCache.done = done
        }.onFailure {
            error = it.message ?: "首页加载失败"
            if (items.isEmpty()) app.store.show(error)
        }
    }

    LaunchedEffect(Unit) { if (items.isEmpty()) load(1) }

    when {
        items.isEmpty() && loading -> CenterSpinner()
        items.isEmpty() -> EmptyHint("首页加载失败", error.ifBlank { "请检查网络或切换线路" }, "重试") {
            done = false
            scope.launch { load(1) }
        }
        else -> VideoFeed(
            ids = items.map { it.id },
            start = 0,
            startEp = 1,
            startTimeSec = 0.0,
            onBack = null,
            onNearEnd = {
                if (!loading && !done) scope.launch { load(page + 1) }
            },
        )
    }
    if (false) onOpenSearch()
}

private object HomeCache {
    var items: List<app.hghub.mobile.data.VideoCard> = emptyList()
    var page: Int = 1
    var done: Boolean = false
}
