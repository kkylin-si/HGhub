package app.hghub.mobile.ui

import android.graphics.Bitmap
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
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.Image
import app.hghub.mobile.LocalApp
import app.hghub.mobile.media.Covers

@Composable
fun CoverImage(url: String, modifier: Modifier, radius: Dp = 14.dp) {
    val app = LocalApp.current
    var bmp by remember(url) { mutableStateOf(Covers.peek(url)) }
    LaunchedEffect(url) {
        if (bmp == null && url.isNotBlank()) bmp = Covers.load(app.api, url)
    }
    val c = LocalHg.current
    Box(
        modifier.clip(RoundedCornerShape(radius)).background(c.soft),
        contentAlignment = Alignment.Center,
    ) {
        val image: Bitmap? = bmp
        if (image != null) {
            Image(image.asImageBitmap(), null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
        }
    }
}

@Composable
fun PageTitle(title: String, sub: String? = null, onBack: (() -> Unit)? = null) {
    val c = LocalHg.current
    Column(Modifier.fillMaxWidth().statusBarsPadding().padding(horizontal = 16.dp, vertical = 8.dp)) {
        if (onBack != null) {
            Box(
                Modifier.size(40.dp).clip(RoundedCornerShape(20.dp)).clickable { onBack() },
                contentAlignment = Alignment.Center,
            ) {
                androidx.compose.material3.Icon(Icons.Filled.ArrowBack, "返回", tint = c.ink)
            }
        }
        Text(title, color = c.ink, fontFamily = Serif, fontSize = 32.sp, fontWeight = FontWeight.Medium)
        if (!sub.isNullOrBlank()) {
            Spacer(Modifier.height(4.dp))
            Text(sub, color = c.muted, fontSize = 13.sp)
        }
    }
}

@Composable
fun EmptyHint(title: String, sub: String, action: String? = null, onAction: (() -> Unit)? = null) {
    val c = LocalHg.current
    Column(
        Modifier.fillMaxSize().padding(32.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(title, color = c.ink, fontFamily = Serif, fontSize = 22.sp)
        Spacer(Modifier.height(8.dp))
        Text(sub, color = c.muted, fontSize = 13.sp)
        if (action != null && onAction != null) {
            Spacer(Modifier.height(16.dp))
            Text(
                action,
                color = c.onAccent,
                fontSize = 14.sp,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier
                    .clip(RoundedCornerShape(14.dp))
                    .background(c.accent)
                    .clickable { onAction() }
                    .padding(horizontal = 18.dp, vertical = 10.dp),
            )
        }
    }
}

@Composable
fun CenterSpinner() {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        CircularProgressIndicator(color = LocalHg.current.accent, strokeWidth = 2.dp)
    }
}

@Composable
fun Chip(text: String, onClick: () -> Unit) {
    val c = LocalHg.current
    Text(
        text,
        color = c.ink,
        fontSize = 13.sp,
        modifier = Modifier
            .clip(RoundedCornerShape(999.dp))
            .background(c.card)
            .clickable { onClick() }
            .padding(horizontal = 14.dp, vertical = 8.dp),
    )
}

@Composable
fun VideoRow(title: String, cover: String, meta: String, onClick: () -> Unit) {
    val c = LocalHg.current
    Row(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .clickable { onClick() }
            .padding(vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        CoverImage(cover, Modifier.width(72.dp).height(96.dp), 12.dp)
        Spacer(Modifier.width(14.dp))
        Column(Modifier.weight(1f)) {
            Text(title, color = c.ink, fontFamily = Serif, fontSize = 16.sp, maxLines = 2)
            Spacer(Modifier.height(6.dp))
            Text(meta, color = c.muted, fontSize = 12.sp, maxLines = 1)
        }
    }
}

@Composable
fun GroupCard(content: @Composable () -> Unit) {
    val c = LocalHg.current
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(CardRadius))
            .background(c.card)
            .padding(vertical = 4.dp),
    ) { content() }
}

@Composable
fun Hairline() {
    Box(Modifier.fillMaxWidth().padding(horizontal = 16.dp).height(1.dp).background(LocalHg.current.line))
}

val Scrim = Color(0xCC14120F)
