package com.goldenmole.stonesand

import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        preferHighestRefreshRate()
    }

    /** Some Android skins keep apps at 60 Hz unless they ask for the panel's fastest mode. */
    private fun preferHighestRefreshRate() {
        val screen = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            display
        } else {
            @Suppress("DEPRECATION")
            windowManager.defaultDisplay
        } ?: return
        val current = screen.mode
        val best = screen.supportedModes
            .filter { it.physicalWidth == current.physicalWidth && it.physicalHeight == current.physicalHeight }
            .maxByOrNull { it.refreshRate } ?: return
        if (best.modeId == current.modeId) return
        window.attributes = window.attributes.apply { preferredDisplayModeId = best.modeId }
    }
}
