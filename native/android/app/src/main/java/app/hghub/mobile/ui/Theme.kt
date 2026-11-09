package app.hghub.mobile.ui

import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp

data class HgPalette(
    val paper: Color,
    val ink: Color,
    val muted: Color,
    val faint: Color,
    val card: Color,
    val line: Color,
    val accent: Color,
    val onAccent: Color,
    val soft: Color,
    val danger: Color,
)

val LightHg = HgPalette(
    paper = Color(0xFFFAF9F5),
    ink = Color(0xFF1A1915),
    muted = Color(0xFF6E6A62),
    faint = Color(0xFF9A958C),
    card = Color(0xFFFFFFFF),
    line = Color(0xFFE7E3D8),
    accent = Color(0xFFC96442),
    onAccent = Color(0xFFFFF8F4),
    soft = Color(0xFFF6E7E0),
    danger = Color(0xFFB42318),
)

val DarkHg = HgPalette(
    paper = Color(0xFF1C1B19),
    ink = Color(0xFFF3F0E8),
    muted = Color(0xFFB2ACA2),
    faint = Color(0xFF8A847A),
    card = Color(0xFF262522),
    line = Color(0xFF3A3833),
    accent = Color(0xFFE08A6E),
    onAccent = Color(0xFF2A120C),
    soft = Color(0xFF3A2C26),
    danger = Color(0xFFFFB4A8),
)

val LocalHg = staticCompositionLocalOf { LightHg }
val Serif = FontFamily.Serif

val PagePad = 20.dp
val CardRadius = 18.dp
