package app.hghub.mobile

import android.os.Bundle
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
