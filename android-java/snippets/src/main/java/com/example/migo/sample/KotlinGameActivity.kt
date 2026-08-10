package com.example.migo.sample

import android.app.Activity
import android.content.res.Configuration
import android.os.Bundle
import android.util.Log
import android.view.SurfaceHolder
import android.view.SurfaceView
import com.migo.runtime.ErrorCode
import com.migo.runtime.GameSession
import com.migo.runtime.MigoException
import com.migo.runtime.MigoRuntime
import com.migo.runtime.RuntimeConfig
import com.migo.runtime.callback.GameSessionListener

/**
 * Kotlin example showing idiomatic usage with extension functions.
 *
 * To handle device rotation without recreating the surface (and thus avoiding render
 * interruption), declare this Activity in your AndroidManifest.xml with configChanges:
 *
 *     <activity
 *         android:name="com.example.migo.sample.KotlinGameActivity"
 *         android:configChanges="orientation|screenSize|keyboardHidden" />
 *
 * This allows the Activity to handle rotation events itself, calling onConfigurationChanged
 * instead of being destroyed and recreated.
 */
class KotlinGameActivity : Activity(), SurfaceHolder.Callback {

    companion object {
        private const val TAG = "KotlinGame"
        // gameId creates isolated directories for this game
        private const val GAME_ID = "kotlin-sample-game"
        private const val GAME_ENTRY = "game.js"
    }

    private var session: GameSession? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Check runtime support
        val runtime = MigoRuntime.getInstance()
        if (!runtime.isDeviceSupported) {
            Log.e(TAG, "Device not supported")
            finish()
            return
        }

        Log.i(TAG, "Migo Runtime v${runtime.version} (native: ${runtime.nativeVersion})")

        // Set up surface view
        SurfaceView(this).apply {
            holder.addCallback(this@KotlinGameActivity)
            setOnTouchListener { _, event ->
                session?.dispatchTouchEvent(event) ?: false
            }
            setContentView(this)
        }
    }

    override fun surfaceCreated(holder: SurfaceHolder) {
        // Build config
        val config = RuntimeConfig.Builder(this)
            .setTargetFps(60)
            .setDebugEnabled(BuildConfig.DEBUG)
            .setLogLevel(
                if (BuildConfig.DEBUG) RuntimeConfig.LogLevel.DEBUG
                else RuntimeConfig.LogLevel.WARN
            ).build()

        // Create session with gameId for isolated directories
        val result = MigoRuntime.getInstance()
            .createSessionSafe(this, holder.surface, config, GAME_ID)

        if (result.isFailure) {
            Log.e(TAG, "Create session failed: ${ErrorCode.getMessage(result.errorCode)}")
            finish()
            return
        }

        session = result.value?.apply {
            // Log game paths
            Log.d(TAG, "Code dir: ${paths.codeDir}")
            Log.d(TAG, "User data dir: ${paths.userDataDir}")

            // Set up unified listener
            setListener(object : GameSessionListener {
                override fun onGameReady() {
                    Log.i(TAG, "Game ready!")
                }

                override fun onGameExit(exitCode: Int) {
                    Log.i(TAG, "Game exit: $exitCode")
                    runOnUiThread { finish() }
                }

                override fun onError(exception: MigoException) {
                    Log.e(TAG, "Error [${exception.errorCode}]: ${exception.message} (recoverable: ${exception.isRecoverable})")
                    if (!exception.isRecoverable) {
                        runOnUiThread { finish() }
                    }
                }
            })

            // Start game - game code should be in paths.codeDir
            startGameSafe(GAME_ENTRY).let { code ->
                if (code != ErrorCode.SUCCESS) {
                    Log.e(TAG, "Start game failed: ${ErrorCode.getMessage(code)}")
                }
            }
        }
    }

    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
        session?.updateSurface(holder.surface, width, height)
    }

    override fun surfaceDestroyed(holder: SurfaceHolder) {
        // Do NOT close the session here. The surface is destroyed when the
        // activity goes to background (onStop), but the activity is still alive.
        // Session cleanup happens in onDestroy().
        session?.onSurfaceDestroyed()
        Log.d(TAG, "Surface destroyed (session kept alive)")
    }

    override fun onPause() {
        super.onPause()
        session?.pause()
    }

    override fun onResume() {
        super.onResume()
        session?.resume()
    }

    override fun onDestroy() {
        session?.close()
        super.onDestroy()
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        // When the device rotates (with configChanges declared in manifest),
        // the surface is not recreated but the view dimensions change.
        // We notify Migo of the new dimensions via surfaceChanged,
        // which is called when the SurfaceView's dimensions change.
        // If surfaceChanged is not called automatically, manually update:
        session?.let { sess ->
            val view = (currentFocus as? SurfaceView) ?: return
            val width = view.width
            val height = view.height
            if (width > 0 && height > 0) {
                sess.updateSurface(view.holder.surface, width, height)
                Log.d(TAG, "Rotation handled: $width x $height")
            }
        }
    }
}

// ==================== Extension Functions ====================

/**
 * Extension to simplify session creation with default config.
 */
fun MigoRuntime.quickStart(
    activity: Activity,
    surface: android.view.Surface,
    gameId: String,
    debug: Boolean = false
): GameSession {
    val config = RuntimeConfig.Builder(activity)
        .setDebugEnabled(debug)
        .build()
    return createSession(activity, surface, config, gameId)
}

/**
 * Extension for DSL-style listener setup.
 */
inline fun GameSession.listen(
    crossinline onReady: () -> Unit = {},
    crossinline onExit: (Int) -> Unit = {},
    crossinline onError: (code: Int, message: String, recoverable: Boolean) -> Unit = { _, _, _ -> }
) {
    setListener(object : GameSessionListener {
        override fun onGameReady() = onReady()
        override fun onGameExit(exitCode: Int) = onExit(exitCode)
        override fun onError(exception: MigoException) =
            onError(exception.errorCode, exception.message ?: "", exception.isRecoverable)
    })
}
