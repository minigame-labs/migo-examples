package com.minigame.androiddemo;

import android.app.Activity;
import android.os.Bundle;
import android.util.Log;
import android.view.Gravity;
import android.view.ViewGroup;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.TextView;

import com.migo.runtime.GameSession;
import com.migo.runtime.MigoException;
import com.migo.runtime.MigoGameView;
import com.migo.runtime.RuntimeConfig;
import com.migo.runtime.callback.GameSessionListener;
import com.minigame.androiddemo.auth.ProxyAuthHandler;

/**
 * Demo Activity showing how to embed a game using MigoGameView.
 * <p>
 * MigoGameView is a self-contained FrameLayout that manages the entire
 * game lifecycle internally. Just add it to your layout, configure it,
 * and call {@code loadGame()}.
 * <p>
 * This is ideal when you want to embed a game alongside other UI elements
 * (e.g., a title bar, native buttons, ads, etc.).
 */
public class EmbeddedGameActivity extends Activity {

    private static final String TAG = "EmbeddedGameActivity";

    private static final String GAME_ID = "migo-test-suit";
    private static final String GAME_ENTRY = "game.js";
    public static final String EXTRA_AUTH_RELAY_URL = "auth_relay_url";

    // Auth proxy relay server URL
    private static final String DEFAULT_AUTH_RELAY_URL = "http://10.0.2.2:9527";

    private MigoGameView gameView;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        String relayUrl = getIntent().getStringExtra(EXTRA_AUTH_RELAY_URL);
        if (relayUrl == null || relayUrl.trim().isEmpty()) {
            relayUrl = DEFAULT_AUTH_RELAY_URL;
        }
        final String finalRelayUrl = relayUrl;

        // Root layout: vertical - title bar on top, game view below
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);

        // Title bar
        FrameLayout titleBar = new FrameLayout(this);
        titleBar.setBackgroundColor(0xFF333333);
        int barHeight = (int) (44 * getResources().getDisplayMetrics().density);

        TextView titleText = new TextView(this);
        titleText.setText("Embedded MigoGameView");
        titleText.setTextColor(0xFFFFFFFF);
        titleText.setTextSize(16);
        FrameLayout.LayoutParams titleLp = new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT);
        titleLp.gravity = Gravity.CENTER;
        titleBar.addView(titleText, titleLp);

        TextView closeBtn = new TextView(this);
        closeBtn.setText("X");
        closeBtn.setTextColor(0xFFFFFFFF);
        closeBtn.setTextSize(18);
        closeBtn.setPadding(dp(16), 0, dp(16), 0);
        closeBtn.setGravity(Gravity.CENTER);
        closeBtn.setOnClickListener(v -> finish());
        FrameLayout.LayoutParams closeLp = new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.MATCH_PARENT);
        closeLp.gravity = Gravity.END | Gravity.CENTER_VERTICAL;
        titleBar.addView(closeBtn, closeLp);

        root.addView(titleBar, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, barHeight));

        // Game view - takes remaining space
        gameView = new MigoGameView(this);

        // Configure
        RuntimeConfig.Builder builder = new RuntimeConfig.Builder(this)
                .setDebugEnabled(true)
                .setCodeSigningEnabled(false)
                ;
        RuntimeConfigCompat.injectFromGameConfig(builder, GameConfigLoader.load(this, GAME_ID));
        RuntimeConfig config = builder.build();
        gameView.setConfig(config);

        gameView.setSessionCreatedListener(new MigoGameView.SessionCreatedListener() {
            @Override
            public void onSessionCreated(GameSession session) {
                session.setGameLogHandler(new DemoGameLogHandler());
                session.setSubpackageHandler(new DemoSubpackageHandler(session.getPaths().getCodeDir()));
                session.setAuthHandler(new ProxyAuthHandler(finalRelayUrl, GAME_ID));
                Log.i(TAG, "Host handlers registered: auth/gameLog/subpackage, relay=" + finalRelayUrl);
            }
        });

        // Set listener
        gameView.setGameListener(new GameSessionListener() {
            @Override
            public void onGameReady() {
                Log.i(TAG, "Embedded game is ready!");
            }

            @Override
            public void onGameExit(int exitCode) {
                Log.i(TAG, "Embedded game exited: " + exitCode);
                runOnUiThread(() -> finish());
            }

            @Override
            public void onError(MigoException exception) {
                Log.e(TAG, "Game error: " + exception);
            }
        });

        root.addView(gameView, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, 0, 1.0f));

        setContentView(root);

        // Load game
        gameView.loadGame(GAME_ID, GAME_ENTRY);
    }

    private int dp(int dp) {
        return (int) (dp * getResources().getDisplayMetrics().density);
    }
}
