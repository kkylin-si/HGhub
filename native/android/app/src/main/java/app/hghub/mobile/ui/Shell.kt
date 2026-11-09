package app.hghub.mobile.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
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
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
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

@Composable
fun Shell() {
    val app = LocalApp.current
    val c = LocalHg.current
    var tab by remember { mutableStateOf(Tab.Home) }
    var stack by remember { mutableStateOf<List<Route>>(emptyList()) }
    var login by remember { mutableStateOf(false) }
    val top = stack.lastOrNull()

    BackHandler(enabled = login || stack.isNotEmpty() || tab != Tab.Home) {
        when {
            login -> login = false
            stack.isNotEmpty() -> stack = stack.dropLast(1)
            else -> tab = Tab.Home
        }
    }

    Column(Modifier.fillMaxSize().background(if (top is Route.Feed || top is Route.Series || (top == null && tab == Tab.Home)) androidx.compose.ui.graphics.Color.Black else c.paper)) {
        Box(Modifier.weight(1f).fillMaxWidth()) {
            when (top) {
                is Route.Feed -> VideoFeed(
                    top.ids, top.index, top.ep, top.time,
                    onBack = { stack = stack.dropLast(1) },
                    onNearEnd = null,
                    onEnterSeries = { id, ep -> stack = stack + Route.Series(id, ep, 0.0) },
                )
                is Route.Series -> key(top.id, top.ep) {
                    VideoFeed(
                        listOf(top.id), 0, top.ep, top.time,
                        onBack = { stack = stack.dropLast(1) },
                        onNearEnd = null,
                        episodePaging = true,
                    )
                }
                is Route.Channel -> ChannelScreen(top.cate, top.name, { stack = stack.dropLast(1) }) { ids, index ->
                    stack = stack + Route.Feed(ids, index, 1, 0.0)
                }
                Route.Ranks -> RankScreen({ stack = stack.dropLast(1) }) { id ->
                    stack = stack + Route.Feed(listOf(id), 0, 1, 0.0)
                }
                Route.Posts -> PostsScreen({ stack = stack.dropLast(1) }) { id ->
                    stack = stack + Route.PostDetail(id)
                }
                is Route.PostDetail -> PostScreen(top.id) { stack = stack.dropLast(1) }
                is Route.Library -> LibraryScreen(
                    kind = top.kind,
                    onBack = { stack = stack.dropLast(1) },
                    onOpen = { id, ep, time -> stack = stack + Route.Series(id, ep, time) },
                    onSeries = { id, ep -> stack = stack + Route.Series(id, ep, 0.0) },
                )
                Route.Settings -> SettingsScreen { stack = stack.dropLast(1) }
                null -> when (tab) {
                    Tab.Home -> HomeFeed({}, onEnterSeries = { id, ep -> stack = stack + Route.Series(id, ep, 0.0) })
                    Tab.Search -> SearchScreen(
                        onOpen = { ids, index -> stack = stack + Route.Feed(ids, index, 1, 0.0) },
                        onRanks = { stack = stack + Route.Ranks },
                    )
                    Tab.Category -> CategoryScreen(
                        onChannel = { cate, name -> stack = stack + Route.Channel(cate, name) },
                        onRanks = { stack = stack + Route.Ranks },
                        onPosts = { stack = stack + Route.Posts },
                        onOpen = { ids, index -> stack = stack + Route.Feed(ids, index, 1, 0.0) },
                    )
                    Tab.Profile -> ProfileScreen(
                        onSettings = { stack = stack + Route.Settings },
                        onLogin = { login = true },
                        onLibrary = { kind -> stack = stack + Route.Library(kind) },
                    )
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
        if (top == null && !app.store.immersive) {
            TabBar(tab) { tab = it }
        }
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
