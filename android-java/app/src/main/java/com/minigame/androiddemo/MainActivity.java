package com.minigame.androiddemo;

import android.app.Activity;
import android.Manifest;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.os.Bundle;
import android.util.Log;
import android.view.Gravity;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.TextView;

import com.migo.runtime.MigoRuntime;
import com.migo.runtime.RuntimeConfig;

/**
 * Demo launcher Activity.
 * <p>
 * Shows two integration approaches:
 * <ol>
 *   <li><b>MigoGameActivity</b> - Zero-boilerplate, launch with one line</li>
 *   <li><b>MigoGameView</b> - Embed a game inside any layout</li>
 * </ol>
 */
public class MainActivity extends Activity {

    private static final String TAG = "MigoDemo";

    // Game configuration
    private static final String GAME_ID = "hxddd";
//    private static final String GAME_ID = "migo-test-suit";
    private static final String GAME_ENTRY = "game.js";

    // Auth relay URL used by demo AuthHandler proxy.
    // - Emulator:    http://10.0.2.2:9527
    // - Real device: http://<PC_LAN_IP>:9527
    private static final String AUTH_RELAY_URL = "http://10.0.2.2:9527";

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        // Request permissions that game APIs might need
        requestPermissionsIfNeeded();

        MigoRuntime runtime = MigoRuntime.getInstance();
        if (!runtime.isDeviceSupported()) {
            Log.e(TAG, "Device not supported");
            finish();
            return;
        }

        Log.i(TAG, "Migo Runtime v" + runtime.getVersion()
                + " (native: " + runtime.getNativeVersion() + ")");

        // Build a simple launcher UI
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setGravity(Gravity.CENTER);
        root.setPadding(dp(24), dp(48), dp(24), dp(24));

        TextView title = new TextView(this);
        title.setText("Migo Android Demo");
        title.setTextSize(24);
        title.setGravity(Gravity.CENTER);

        TextView version = new TextView(this);
        version.setText("v" + runtime.getVersion());
        version.setTextSize(14);
        version.setGravity(Gravity.CENTER);
        version.setPadding(0, dp(4), 0, dp(32));

        // Option 1: MigoGameActivity with diagnostic logs
        Button btn1 = createButton("1. MigoGameActivity (Debug Logs)");
        btn1.setOnClickListener(v -> launchWithGameActivity());

        // Option 2: Embedded MigoGameView (handlers registered after session creation)
        Button btn2 = createButton("2. Embedded MigoGameView (+Handlers)");
        btn2.setOnClickListener(v -> launchEmbeddedView());

        root.addView(title);
        root.addView(version);
        root.addView(btn1, buttonParams());
        root.addView(btn2, buttonParams());

        setContentView(root);
    }

    /**
     * Option 1: Launch game using MigoGameActivity.
     * This is the simplest integration - one line of code.
     */
    private void launchWithGameActivity() {
        RuntimeConfig.Builder builder = new RuntimeConfig.Builder(this)
                .setDebugEnabled(true)
                .setCodeSigningEnabled(false)
                ;
        RuntimeConfigCompat.injectFromGameConfig(builder, GameConfigLoader.load(this, GAME_ID));
        RuntimeConfig config = builder.build();
        DebugMigoGameActivity.launch(this, GAME_ID, GAME_ENTRY, config, AUTH_RELAY_URL);
    }

    /**
     * Option 2: Launch the embedded MigoGameView demo.
     */
    private void launchEmbeddedView() {
        Intent intent = new Intent(this, EmbeddedGameActivity.class);
        intent.putExtra(EmbeddedGameActivity.EXTRA_AUTH_RELAY_URL, AUTH_RELAY_URL);
        startActivity(intent);
    }

    // ---- Helpers ----

    private void requestPermissionsIfNeeded() {
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
            String[] perms = {
                    Manifest.permission.RECORD_AUDIO,
                    Manifest.permission.CAMERA,
            };
            for (String perm : perms) {
                if (checkSelfPermission(perm) != PackageManager.PERMISSION_GRANTED) {
                    requestPermissions(perms, 200);
                    break;
                }
            }
        }
    }

    private Button createButton(String text) {
        Button btn = new Button(this);
        btn.setText(text);
        btn.setAllCaps(false);
        btn.setTextSize(16);
        return btn;
    }

    private LinearLayout.LayoutParams buttonParams() {
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT);
        lp.bottomMargin = dp(12);
        return lp;
    }

    private int dp(int dp) {
        return (int) (dp * getResources().getDisplayMetrics().density);
    }
}
