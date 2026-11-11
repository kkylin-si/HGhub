package app.hghub.mobile

import android.app.PictureInPictureParams
import android.os.Build
import android.os.Bundle
import android.util.Rational
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.CompositionLocalProvider
import app.hghub.mobile.ui.DarkHg
import app.hghub.mobile.ui.LightHg
import app.hghub.mobile.ui.LocalHg
import app.hghub.mobile.ui.Shell

class MainActivity : ComponentActivity() {
    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        val store = (application as HgApp).store
        if (!store.pipOnDesktop || !store.canDesktopPip || isInPictureInPictureMode) return
        store.inPip = true
        requestedOrientation = android.content.pm.ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
        val entered = enterPictureInPictureMode(pipParams(store.pipOnDesktop, store.canDesktopPip, store.pipWidth, store.pipHeight))
        if (!entered) store.inPip = false
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val app = application as HgApp
        setContent {
            val dark = app.store.dark
            val palette = if (dark) DarkHg else LightHg
            val scheme = if (dark) {
                darkColorScheme(primary = palette.accent, background = palette.paper, surface = palette.card)
            } else {
                lightColorScheme(primary = palette.accent, background = palette.paper, surface = palette.card)
            }
            CompositionLocalProvider(LocalApp provides app, LocalHg provides palette) {
                MaterialTheme(colorScheme = scheme) { Shell() }
            }
        }
    }
}

internal fun pipParams(enabled: Boolean, active: Boolean, width: Int, height: Int): PictureInPictureParams {
    val ratio = pipRational(width, height)
    val builder = PictureInPictureParams.Builder().setAspectRatio(ratio)
    if (Build.VERSION.SDK_INT >= 31) {
        builder.setAutoEnterEnabled(enabled && active)
    }
    return builder.build()
}

private fun pipRational(width: Int, height: Int): Rational {
    if (width <= 0 || height <= 0) return Rational(9, 16)
    val ratio = width.toFloat() / height.toFloat()
    return when {
        ratio < 0.42f -> Rational(9, 16)
        ratio > 2.39f -> Rational(16, 9)
        else -> Rational(width, height)
    }
}
