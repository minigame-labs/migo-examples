package com.minigame.androiddemo;

import android.content.Context;
import android.content.Intent;
import android.os.Bundle;
import android.util.Log;
import android.view.SurfaceHolder;

import com.migo.runtime.GameSession;
import com.migo.runtime.MigoException;
import com.migo.runtime.MigoGameActivity;
import com.migo.runtime.RuntimeConfig;
import com.migo.runtime.SessionState;
import com.migo.runtime.callback.GameSessionListener;
import com.minigame.androiddemo.auth.ProxyAuthHandler;

/**
 * Diagnostic wrapper for MigoGameActivity.
 *
 * Adds high-signal logs for game startup key path:
 * - Activity lifecycle
 * - Surface lifecycle
 * - Game session listener callbacks
 */
public class DebugMigoGameActivity extends MigoGameActivity {

    private static final String TAG = "DebugMigoGameAct";
    public static final String EXTRA_AUTH_RELAY_URL = "auth_relay_url";
    private static final String DEFAULT_AUTH_RELAY_URL = "http://10.0.2.2:9527";

    private String relayUrl = DEFAULT_AUTH_RELAY_URL;
    private String gameId = "";

    public static void launch(Context context, String gameId, String entryPoint, RuntimeConfig config) {
        launch(context, gameId, entryPoint, config, DEFAULT_AUTH_RELAY_URL);
    }

    public static void launch(
            Context context,
            String gameId,
            String entryPoint,
            RuntimeConfig config,
            String relayUrl
    ) {
        Intent intent = buildLaunchIntent(
                context,
                DebugMigoGameActivity.class,
                gameId,
                entryPoint,
                config
        );
        if (relayUrl != null && !relayUrl.trim().isEmpty()) {
            intent.putExtra(EXTRA_AUTH_RELAY_URL, relayUrl.trim());
        }
        context.startActivity(intent);
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        gameId = getIntent().getStringExtra(EXTRA_GAME_ID);
        String entryPoint = getIntent().getStringExtra(EXTRA_ENTRY_POINT);
        String relay = getIntent().getStringExtra(EXTRA_AUTH_RELAY_URL);
        if (relay != null && !relay.trim().isEmpty()) {
            relayUrl = relay.trim();
        }
        Log.i(TAG, "onCreate gameId=" + gameId + ", entryPoint=" + entryPoint);
        Log.i(TAG, "auth relay=" + relayUrl);
    }

    @Override
    protected void onSessionCreated(GameSession session) {
        session.setAuthHandler(new ProxyAuthHandler(relayUrl, gameId));
        session.setGameLogHandler(new DemoGameLogHandler());
        session.setSubpackageHandler(new DemoSubpackageHandler(session.getPaths().getCodeDir()));
        Log.i(TAG, "Host handlers registered: auth/gameLog/subpackage");

        // Demonstrate state change listener
        session.setOnStateChangeListener((s, oldState, newState) ->
            Log.d(TAG, "Session state: " + oldState + " -> " + newState));
    }

    @Override
    protected void onLaunchFailed(int errorCode, String message) {
        Log.e(TAG, "Launch failed: [" + errorCode + "] " + message);
        super.onLaunchFailed(errorCode, message);
    }

    @Override
    public void surfaceCreated(SurfaceHolder holder) {
        Log.i(TAG, "surfaceCreated valid=" + (holder != null && holder.getSurface() != null
                && holder.getSurface().isValid()));
        super.surfaceCreated(holder);
    }

    @Override
    public void surfaceChanged(SurfaceHolder holder, int format, int width, int height) {
        Log.i(TAG, "surfaceChanged format=" + format + ", size=" + width + "x" + height);
        super.surfaceChanged(holder, format, width, height);
    }

    @Override
    public void surfaceDestroyed(SurfaceHolder holder) {
        Log.i(TAG, "surfaceDestroyed");
        super.surfaceDestroyed(holder);
    }

    @Override
    protected void onPause() {
        Log.i(TAG, "onPause");
        super.onPause();
    }

    @Override
    protected void onResume() {
        Log.i(TAG, "onResume");
        super.onResume();
    }

    @Override
    protected void onDestroy() {
        Log.i(TAG, "onDestroy");
        super.onDestroy();
    }

    @Override
    protected GameSessionListener onCreateGameListener() {
        return new GameSessionListener() {
            @Override
            public void onGameReady() {
                Log.i(TAG, "listener.onGameReady");
                // Enable performance profiling after game is loaded.
                // View with: adb logcat | grep "\[MigoPerf\]"
                GameSession s = getGameSession();
                if (s != null) {
                    s.evaluateJavaScript("_perf.enable()");
                }
            }

            @Override
            public void onGameExit(int exitCode) {
                Log.i(TAG, "listener.onGameExit exitCode=" + exitCode);
            }

            @Override
            public void onError(MigoException exception) {
                Log.e(TAG, "listener.onError: " + exception);
                if (!exception.isRecoverable()) {
                    Log.e(TAG, "Fatal error, session must be restarted");
                }
            }

            @Override
            public void onLoadingStart() {
                Log.i(TAG, "listener.onLoadingStart");
            }

            @Override
            public void onLoadingEnd() {
                Log.i(TAG, "listener.onLoadingEnd");
            }

            @Override
            public void onLoadingProgress(float progress, String message) {
                Log.i(TAG, "listener.onLoadingProgress progress=" + progress + ", message=" + message);
            }

            @Override
            public void onPaused() {
                Log.i(TAG, "listener.onPaused");
            }

            @Override
            public void onResumed() {
                Log.i(TAG, "listener.onResumed");
            }

            @Override
            public void onDestroyed() {
                Log.i(TAG, "listener.onDestroyed");
            }
        };
    }
}
