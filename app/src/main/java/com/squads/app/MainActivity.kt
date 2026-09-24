package com.squads.app

import android.os.Bundle
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import com.squads.app.ui.SquadsApp
import com.squads.app.ui.theme.SquadsTheme
import dagger.hilt.android.AndroidEntryPoint

@AndroidEntryPoint
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        installSplashScreen()
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        // Keep chat and mail content out of screenshots, screen recordings and the
        // recents thumbnail. Disabled in debug builds so Maestro can capture screens.
        if (BuildConfig.SECURE_WINDOW) {
            window.setFlags(
                WindowManager.LayoutParams.FLAG_SECURE,
                WindowManager.LayoutParams.FLAG_SECURE,
            )
        }

        setContent {
            SquadsTheme {
                SquadsApp()
            }
        }
    }
}
