package app.hghub.mobile.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.drag
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.outlined.GridView
import androidx.compose.material.icons.outlined.Home
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChange
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlin.math.abs
import kotlin.math.roundToInt
import app.hghub.mobile.LocalApp
import kotlinx.coroutines.delay

private enum class Tab { Home, Search, Category, Profile }

private sealed interface Route {
    data class Feed(val ids: List<Int>, val index: Int, val ep: Int, val time: Double) : Route
    data class Series(val id: Int, val ep: Int, val time: Double) : Route
    data class Channel(val cate: String, val name: String) : Route
    data object Ranks : Route
    data object Posts : Route
    data class PostDetail(val id: Int) : Route
    data class Library(val kind: String) : Route
    data object Settings : Route
}

private sealed interface PlaySlot {
    data object Home : PlaySlot
    data class Feed(val ids: List<Int>, val index: Int, val ep: Int, val time: Double) : PlaySlot
    data class Series(val id: Int, val ep: Int, val time: Double) : PlaySlot
}

private fun PlaySlot.key(): String = when (this) {
    PlaySlot.Home -> "home"
    is PlaySlot.Feed -> "feed-${ids.size}-${index}-${ep}-${ids.firstOrNull() ?: 0}"
    is PlaySlot.Series -> "series-$id-$ep"
}

@Composable
fun Shell() {
    val app = LocalApp.current
    val c = LocalHg.current
    var tab by remember { mutableStateOf(Tab.Home) }
    var stack by remember { mutableStateOf<List<Route>>(emptyList()) }
    var login by remember { mutableStateOf(false) }
    var mini by remember { mutableStateOf(false) }
    var parked by remember { mutableStateOf<PlaySlot?>(null) }
    var miniOffset by remember { mutableStateOf(IntOffset.Zero) }
    val top = stack.lastOrNull()
    val live = when {
        mini -> parked
        top is Route.Feed -> PlaySlot.Feed(top.ids, top.index, top.ep, top.time)
        top is Route.Series -> PlaySlot.Series(top.id, top.ep, top.time)
        top == null && tab == Tab.Home -> PlaySlot.Home
        else -> null
    }
    val fullPlayer = live != null && !mini

    fun closeMini() {
        mini = false
        parked = null
        miniOffset = IntOffset.Zero
    }
    fun openFeed(ids: List<Int>, index: Int) {
        closeMini()
        stack = stack + Route.Feed(ids, index, 1, 0.0)
    }
    fun openSeries(id: Int, ep: Int, time: Double) {
        closeMini()
        stack = stack + Route.Series(id, ep.coerceAtLeast(1), time)
    }
    fun enterMini() {
        val slot = live ?: return
        if (mini) return
        parked = slot
        miniOffset = IntOffset.Zero
        if (top is Route.Feed || top is Route.Series) stack = stack.dropLast(1)
        mini = true
    }
    fun expandMini() {
        val slot = parked ?: return
        mini = false
        parked = null
        miniOffset = IntOffset.Zero
        when (slot) {
            PlaySlot.Home -> tab = Tab.Home
            is PlaySlot.Feed -> stack = stack + Route.Feed(slot.ids, slot.index, slot.ep, slot.time)
            is PlaySlot.Series -> stack = stack + Route.Series(slot.id, slot.ep, slot.time)
        }
    }
    fun floatSeries(id: Int, ep: Int, time: Double) {
        parked = PlaySlot.Series(id, ep.coerceAtLeast(1), time)
        miniOffset = IntOffset.Zero
        mini = true
    }

    BackHandler(enabled = login || stack.isNotEmpty() || tab != Tab.Home) {
        when {
            login -> login = false
            stack.isNotEmpty() -> stack = stack.dropLast(1)
            else -> tab = Tab.Home
        }
    }

    Column(Modifier.fillMaxSize().background(if (fullPlayer || (top == null && tab == Tab.Home && !mini)) Color.Black else c.paper)) {
        Box(Modifier.weight(1f).fillMaxWidth()) {
            if (!fullPlayer) {
                Box(Modifier.fillMaxSize()) {
                    when (top) {
                        is Route.Feed, is Route.Series -> Unit
                        is Route.Channel -> ChannelScreen(top.cate, top.name, { stack = stack.dropLast(1) }) { ids, index ->
                            openFeed(ids, index)
                        }
                        Route.Ranks -> RankScreen({ stack = stack.dropLast(1) }) { id -> openFeed(listOf(id), 0) }
                        Route.Posts -> PostsScreen({ stack = stack.dropLast(1) }) { id ->
                            closeMini()
                            stack = stack + Route.PostDetail(id)
                        }
                        is Route.PostDetail -> PostScreen(top.id) { stack = stack.dropLast(1) }
                        is Route.Library -> LibraryScreen(
                            kind = top.kind,
                            onBack = { stack = stack.dropLast(1) },
                            onOpen = { id, ep, time -> openSeries(id, ep, time) },
                            onSeries = { id, ep, time -> openSeries(id, ep, time) },
                            onFloat = { id, ep, time -> floatSeries(id, ep, time) },
                        )
                        Route.Settings -> SettingsScreen { stack = stack.dropLast(1) }
                        null -> when (tab) {
                            Tab.Home -> if (mini && parked is PlaySlot.Home) {
                                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                                    Text("正在小窗播放", color = c.ink, fontSize = 16.sp)
                                }
                            } else if (live !is PlaySlot.Home) {
                                HomeFeed({}, onEnterSeries = { id, ep, time -> openSeries(id, ep, time) })
                            }
                            Tab.Search -> SearchScreen(
                                onOpen = { ids, index -> openFeed(ids, index) },
                                onRanks = { stack = stack + Route.Ranks },
                            )
                            Tab.Category -> CategoryScreen(
                                onChannel = { cate, name -> stack = stack + Route.Channel(cate, name) },
                                onRanks = { stack = stack + Route.Ranks },
                                onPosts = { stack = stack + Route.Posts },
                                onOpen = { ids, index -> openFeed(ids, index) },
                            )
                            Tab.Profile -> ProfileScreen(
                                onSettings = { stack = stack + Route.Settings },
                                onLogin = { login = true },
                                onLibrary = { kind -> stack = stack + Route.Library(kind) },
                            )
                        }
                    }
                }
            }
            live?.let { slot ->
            Box(
                if (mini) {
                    Modifier
                        .align(Alignment.BottomEnd)
                        .padding(end = 12.dp, bottom = 12.dp)
                        .offset { miniOffset }
                        .size(132.dp, 210.dp)
                        .clip(RoundedCornerShape(14.dp))
                } else {
                    Modifier.fillMaxSize()
                },
            ) {
                key(slot.key()) {
                    when (slot) {
                        PlaySlot.Home -> HomeFeed(
                            {},
                            onEnterSeries = { id, ep, time -> openSeries(id, ep, time) },
                            mini = mini,
                            onMini = { _, _, _ -> enterMini() },
                        )
                        is PlaySlot.Feed -> VideoFeed(
                            slot.ids, slot.index, slot.ep, slot.time,
                            onBack = { stack = stack.dropLast(1) },
                            onNearEnd = null,
                            onEnterSeries = { id, ep, time -> openSeries(id, ep, time) },
                            mini = mini,
                            onMini = { _, _, _ -> enterMini() },
                        )
                        is PlaySlot.Series -> VideoFeed(
                            listOf(slot.id), 0, slot.ep, slot.time,
                            onBack = { stack = stack.dropLast(1) },
                            onNearEnd = null,
                            episodePaging = true,
                            mini = mini,
                            onMini = { _, _, _ -> enterMini() },
                        )
                    }
                }
                    if (mini) {
                        Box(
                            Modifier.fillMaxSize().pointerInput(slot.key()) {
                                awaitEachGesture {
                                    val down = awaitFirstDown()
                                    var moved = 0f
                                    val dragging = drag(down.id) { change ->
                                        val delta = change.positionChange()
                                        moved += abs(delta.x) + abs(delta.y)
                                        miniOffset = IntOffset(
                                            miniOffset.x + delta.x.roundToInt(),
                                            miniOffset.y + delta.y.roundToInt(),
                                        )
                                        change.consume()
                                    }
                                    if (!dragging || moved < 12f) expandMini()
                                }
                            },
                        )
                        Icon(
                            Icons.Filled.Close,
                            "关闭小窗",
                            tint = Color.White,
                            modifier = Modifier
                                .align(Alignment.TopEnd)
                                .padding(4.dp)
                                .size(28.dp)
                                .clip(androidx.compose.foundation.shape.CircleShape)
                                .background(Color(0xCC000000))
                                .clickable { closeMini() }
                                .padding(4.dp),
                        )
                    }
                }
            }
        val toast = app.store.toast
        if (!toast.isNullOrBlank()) {
            Text(
                toast,
                color = c.onAccent,
                fontSize = 13.sp,
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .padding(bottom = 16.dp)
                    .clip(RoundedCornerShape(999.dp))
                    .background(c.accent)
                    .padding(horizontal = 16.dp, vertical = 10.dp),
            )
            androidx.compose.runtime.LaunchedEffect(toast) {
                delay(2200)
                if (app.store.toast == toast) app.store.toast = null
            }
        }
        }
        if (top == null && !app.store.immersive && !app.store.inPip) TabBar(tab) { tab = it }
    }
    if (login) LoginSheet { login = false }
}

@Composable
private fun TabBar(tab: Tab, onPick: (Tab) -> Unit) {
    val c = LocalHg.current
    Row(
        Modifier.fillMaxWidth().background(c.paper).navigationBarsPadding().padding(top = 6.dp, bottom = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        BarItem("首页", tab == Tab.Home, Icons.Filled.Home, Icons.Outlined.Home) { onPick(Tab.Home) }
        BarItem("搜索", tab == Tab.Search, Icons.Filled.Search, Icons.Outlined.Search) { onPick(Tab.Search) }
        BarItem("分类", tab == Tab.Category, Icons.Filled.GridView, Icons.Outlined.GridView) { onPick(Tab.Category) }
        BarItem("我的", tab == Tab.Profile, Icons.Filled.Person, Icons.Outlined.Person) { onPick(Tab.Profile) }
    }
}

@Composable
private fun androidx.compose.foundation.layout.RowScope.BarItem(
    label: String,
    on: Boolean,
    filled: ImageVector,
    outlined: ImageVector,
    click: () -> Unit,
) {
    val c = LocalHg.current
    Column(
        Modifier.weight(1f).clickable { click() },
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Icon(if (on) filled else outlined, label, tint = if (on) c.accent else c.faint)
        Text(label, color = if (on) c.accent else c.faint, fontSize = 11.sp, fontWeight = if (on) FontWeight.SemiBold else FontWeight.Normal)
    }
}
