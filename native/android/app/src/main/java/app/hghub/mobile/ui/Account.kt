package app.hghub.mobile.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.hghub.mobile.LocalApp
import app.hghub.mobile.data.AppStore
import app.hghub.mobile.data.Detail
import app.hghub.mobile.data.fmtClock
import app.hghub.mobile.data.fmtCount
import app.hghub.mobile.media.Covers
import kotlinx.coroutines.launch

@Composable
fun ProfileScreen(onSettings: () -> Unit, onLogin: () -> Unit, onOpen: (Int, Int, Double) -> Unit) {
    val app = LocalApp.current
    val c = LocalHg.current
    val store = app.store
    var tab by remember { mutableStateOf("fav") }
    var cards by remember { mutableStateOf<List<Detail>>(emptyList()) }
    val ids = if (tab == "fav") store.favs else store.history.map { it.id }

    LaunchedEffect(ids.joinToString(",")) {
        cards = emptyList()
        val loaded = ids.take(16).mapNotNull { id -> runCatching { app.api.video(id) }.getOrNull() }
        cards = loaded
    }

    val name = store.account?.nickname ?: "未登录"
    LazyColumn(Modifier.fillMaxSize().background(c.paper)) {
        item {
            Row(
                Modifier.fillMaxWidth().padding(start = 20.dp, end = 20.dp, top = 18.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(Modifier.weight(1f)) {
                    Text("我的", color = c.ink, fontFamily = Serif, fontSize = 34.sp)
                    Spacer(Modifier.height(4.dp))
                    Text("收藏和观看都留在这台设备上", color = c.muted, fontSize = 13.sp)
                }
                Box(
                    Modifier.size(40.dp).clip(CircleShape).background(c.card).clickable { onSettings() },
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(Icons.Outlined.Settings, "设置", tint = c.ink)
                }
            }
        }
        item {
            val user = store.account
            Column(
                Modifier.padding(start = 20.dp, end = 20.dp, top = 18.dp).fillMaxWidth().clip(RoundedCornerShape(22.dp)).background(c.card).padding(18.dp),
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(
                        Modifier.size(56.dp).clip(CircleShape).background(c.soft),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(name.take(1), color = c.accent, fontFamily = Serif, fontSize = 22.sp)
                    }
                    Spacer(Modifier.size(14.dp))
                    Column(Modifier.weight(1f)) {
                        Text(name, color = c.ink, fontFamily = Serif, fontSize = 22.sp)
                        Spacer(Modifier.height(4.dp))
                        Text(
                            if (user == null) "登录后可以同步点赞、收藏和评论" else "@${user.username}",
                            color = c.muted,
                            fontSize = 13.sp,
                        )
                    }
                }
                Spacer(Modifier.height(16.dp))
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
                    Stat("收藏", if (user == null) store.favs.size.toString() else fmtCount(user.collect))
                    Stat("喜欢", if (user == null) store.likes.size.toString() else fmtCount(user.like))
                    Stat("观看", store.history.size.toString())
                }
                if (user == null) {
                    Spacer(Modifier.height(16.dp))
                    Text(
                        "登录",
                        color = c.onAccent,
                        fontWeight = FontWeight.SemiBold,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(c.accent).clickable { onLogin() }.padding(vertical = 12.dp),
                    )
                }
            }
        }
        item {
            Spacer(Modifier.height(16.dp))
            Row(Modifier.padding(horizontal = 20.dp).clip(RoundedCornerShape(16.dp)).background(c.card).padding(4.dp)) {
                Seg("收藏", tab == "fav", Modifier.weight(1f)) { tab = "fav" }
                Seg("历史", tab == "history", Modifier.weight(1f)) { tab = "history" }
            }
        }
        if (cards.isEmpty()) {
            item {
                Column(Modifier.fillMaxWidth().padding(vertical = 36.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(
                        if (ids.isEmpty()) if (tab == "fav") "还没有收藏" else "还没有观看记录" else "正在读取…",
                        color = c.ink,
                        fontFamily = Serif,
                        fontSize = 18.sp,
                    )
                    Spacer(Modifier.height(6.dp))
                    Text(
                        if (ids.isEmpty()) if (tab == "fav") "看到喜欢的短剧，点一下收藏" else "看过的剧会记在这里" else "稍等一下",
                        color = c.muted,
                        fontSize = 13.sp,
                    )
                }
            }
        }
        items(cards, key = { it.id }) { d ->
            val progress = store.history.firstOrNull { it.id == d.id }
            val extra = if (tab == "history" && progress != null) "看到第 ${progress.ep} 集 ${fmtClock(progress.t)}" else "${d.episodeCount} 集"
            Column(Modifier.padding(horizontal = 20.dp, vertical = 6.dp).clip(RoundedCornerShape(18.dp)).background(c.card)) {
                VideoRow(d.title, d.cover, extra) {
                    val ep = progress?.ep ?: 1
                    val t = if (tab == "history") progress?.t ?: 0.0 else 0.0
                    onOpen(d.id, ep, t)
                }
            }
        }
        item { Spacer(Modifier.height(28.dp)) }
    }
}

@Composable
private fun Stat(label: String, value: String) {
    val c = LocalHg.current
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(value, color = c.ink, fontFamily = Serif, fontSize = 20.sp)
        Text(label, color = c.faint, fontSize = 12.sp)
    }
}

@Composable
private fun Seg(label: String, on: Boolean, modifier: Modifier = Modifier, click: () -> Unit) {
    val c = LocalHg.current
    Text(
        label,
        color = if (on) c.onAccent else c.muted,
        textAlign = TextAlign.Center,
        modifier = modifier.clip(RoundedCornerShape(12.dp)).background(if (on) c.accent else c.card).clickable { click() }.padding(horizontal = 18.dp, vertical = 10.dp),
    )
}

@Composable
fun SettingsScreen(onBack: () -> Unit) {
    val app = LocalApp.current
    val store = app.store
    val c = LocalHg.current
    val scope = rememberCoroutineScope()
    var mirrors by remember { mutableStateOf<List<String>>(emptyList()) }
    var busy by remember { mutableStateOf(false) }

    LazyColumn(Modifier.fillMaxSize().background(c.paper)) {
        item { PageTitle("设置", "线路 · 外观 · 播放", onBack) }
        item { SectionLabel("外观") }
        item {
            GroupCard {
                SettingRow("深色外观", "暖色纸面，晚上更舒服") {
                    Switch(store.dark, { store.applyDark(it) }, colors = SwitchDefaults.colors(checkedTrackColor = c.accent))
                }
            }
        }
        item { SectionLabel("播放") }
        item {
            GroupCard {
                SettingRow("启动时静音", "下次打开仍然静音") {
                    Switch(store.muteOnStartup, { store.applyMuteOnStartup(it) }, colors = SwitchDefaults.colors(checkedTrackColor = c.accent))
                }
                Hairline()
                SettingRow("优先高清", "有高清就用 HEVC，播不了会回到标准") {
                    Switch(store.preferHevc, { store.applyPreferHevc(it) }, colors = SwitchDefaults.colors(checkedTrackColor = c.accent))
                }
            }
        }
        item { SectionLabel("线路") }
        item {
            GroupCard {
                AppStore.FIXED.forEach { (name, url) ->
                    val on = store.base == url
                    SettingRow(name, url.removePrefix("https://")) {
                        Text(if (on) "当前" else "切换", color = if (on) c.accent else c.muted, modifier = Modifier.clickable {
                            if (!on) {
                                store.setLine(url)
                                store.show("已切换到$name，账号需要重新登录")
                            }
                        })
                    }
                    Hairline()
                }
                mirrors.forEach { url ->
                    val on = store.base == url
                    SettingRow(url.removePrefix("https://"), "镜像，仅游客") {
                        Text(if (on) "当前" else "使用", color = c.accent, modifier = Modifier.clickable {
                            store.setLine(url)
                            store.show("已切换镜像线路")
                        })
                    }
                }
                SettingRow("刷新镜像", if (busy) "正在读取地址发布页" else "从发布页拉取") {
                    Text("刷新", color = c.accent, modifier = Modifier.clickable(enabled = !busy) {
                        busy = true
                        scope.launch {
                            runCatching { app.api.mirrors() }
                                .onSuccess { mirrors = it; store.show("已更新 ${it.size} 条镜像") }
                                .onFailure { store.show(it.message ?: "镜像获取失败") }
                            busy = false
                        }
                    })
                }
            }
        }
        item { SectionLabel("本地") }
        item {
            GroupCard {
                SettingRow("清理封面缓存", "不影响收藏和历史") {
                    Text("清理", color = c.accent, modifier = Modifier.clickable {
                        Covers.clear()
                        store.show("封面缓存已清理")
                    })
                }
                Hairline()
                SettingRow("清空收藏和历史", "只清这台设备") {
                    Text("清空", color = c.danger, modifier = Modifier.clickable {
                        store.clearLocal()
                        store.show("已清空")
                    })
                }
            }
        }
        item {
            Text(
                "HGhub  ${store.base.removePrefix("https://")}\n包名 app.hghub.mobile\n个人学习使用，不提供下载。",
                color = c.faint,
                fontSize = 12.sp,
                modifier = Modifier.padding(20.dp),
                lineHeight = 18.sp,
            )
        }
    }
}

@Composable
private fun SectionLabel(text: String) {
    Text(text, color = LocalHg.current.faint, fontSize = 12.sp, modifier = Modifier.padding(start = 24.dp, top = 16.dp, bottom = 6.dp))
}

@Composable
private fun SettingRow(title: String, sub: String, trailing: @Composable () -> Unit) {
    val c = LocalHg.current
    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f).padding(end = 12.dp)) {
            Text(title, color = c.ink, fontSize = 15.sp)
            Text(sub, color = c.muted, fontSize = 12.sp)
        }
        trailing()
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LoginSheet(onClose: () -> Unit) {
    val app = LocalApp.current
    val c = LocalHg.current
    val scope = rememberCoroutineScope()
    var mode by remember { mutableStateOf("login") }
    var username by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var email by remember { mutableStateOf("") }
    var error by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }

    ModalBottomSheet(onDismissRequest = onClose, containerColor = c.paper) {
        Column(Modifier.padding(horizontal = 22.dp).padding(bottom = 28.dp)) {
            Text(if (mode == "login") "登录" else "注册", color = c.ink, fontFamily = Serif, fontSize = 28.sp)
            Spacer(Modifier.height(6.dp))
            Text("使用黄果短剧账号。镜像线路不能登录。", color = c.muted, fontSize = 13.sp)
            Spacer(Modifier.height(14.dp))
            Row(Modifier.clip(RoundedCornerShape(12.dp)).background(c.card).padding(4.dp)) {
                Seg("登录", mode == "login") { mode = "login"; error = "" }
                Seg("注册", mode == "register") { mode = "register"; error = "" }
            }
            Spacer(Modifier.height(14.dp))
            Field(username, "账号") { username = it }
            Spacer(Modifier.height(8.dp))
            Field(password, "密码", password = true) { password = it }
            if (mode == "register") {
                Spacer(Modifier.height(8.dp))
                Field(email, "邮箱，可选") { email = it }
            }
            if (error.isNotBlank()) {
                Spacer(Modifier.height(8.dp))
                Text(error, color = c.danger, fontSize = 13.sp)
            }
            Spacer(Modifier.height(16.dp))
            Text(
                if (busy) "处理中…" else if (mode == "login") "登录" else "注册并登录",
                color = c.onAccent,
                fontWeight = FontWeight.SemiBold,
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(c.accent).clickable(enabled = !busy) {
                    if (username.isBlank() || password.isBlank()) {
                        error = "请输入账号和密码"
                        return@clickable
                    }
                    busy = true
                    error = ""
                    scope.launch {
                        val result = runCatching {
                            if (mode == "login") app.api.login(username.trim(), password)
                            else app.api.register(username.trim(), password, email.trim())
                        }
                        busy = false
                        result.onSuccess {
                            password = ""
                            app.store.show("欢迎，${it.nickname}")
                            onClose()
                        }.onFailure { error = it.message ?: "操作失败" }
                    }
                }.padding(vertical = 14.dp),
            )
            if (app.store.loggedIn) {
                Spacer(Modifier.height(10.dp))
                Text("退出登录", color = c.danger, modifier = Modifier.clickable {
                    scope.launch {
                        app.api.logout()
                        onClose()
                    }
                })
            }
        }
    }
}

@Composable
private fun Field(value: String, hint: String, password: Boolean = false, onChange: (String) -> Unit) {
    val c = LocalHg.current
    BasicTextField(
        value = value,
        onValueChange = onChange,
        singleLine = true,
        visualTransformation = if (password) PasswordVisualTransformation() else androidx.compose.ui.text.input.VisualTransformation.None,
        textStyle = TextStyle(color = c.ink, fontSize = 15.sp),
        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(c.card).padding(horizontal = 14.dp, vertical = 14.dp),
        decorationBox = { inner ->
            if (value.isEmpty()) Text(hint, color = c.faint, fontSize = 15.sp)
            inner()
        },
    )
}
