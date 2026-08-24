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
import android.widget.Toast;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;

import com.migo.runtime.MigoRuntime;
import com.migo.runtime.RuntimeConfig;

/**
 * Demo launcher Activity.
 * <p>
 * Shows three integration approaches:
 * <ol>
 *   <li><b>MigoGameActivity</b> - Zero-boilerplate, launch with one line</li>
 *   <li><b>MigoGameView</b> - Embed a game inside any layout</li>
 *   <li><b>Adapter injection</b> - Run unmodified wx-shaped content via a boot
 *       prelude script, no engine change and no edits to the game's own source</li>
 * </ol>
 */
public class MainActivity extends Activity {

    private static final String TAG = "MigoDemo";

    // Game configuration
    private static final String GAME_ID = "demo";
    private static final String GAME_ENTRY = "game.js";

    // Adapter-injection demo: unmodified wx-shaped content, deployed separately
    // via `scripts/push-game.sh wx-adapter-demo` (see android-java/README.md).
    private static final String WX_DEMO_GAME_ID = "wx-adapter-demo";
    private static final String WX_ADAPTER_ASSET = "migo-wx-adapter.bundle.js";

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

        // Option 3: adapter injection running unmodified wx-shaped content
        Button btn3 = createButton("3. Adapter Injection (unmodified wx game)");
        btn3.setOnClickListener(v -> launchWithWxAdapter());

        root.addView(title);
        root.addView(version);
        root.addView(btn1, buttonParams());
        root.addView(btn2, buttonParams());
        root.addView(btn3, buttonParams());

        setContentView(root);

        // Headless entry, for tooling that has to drive this host without a
        // human to tap a button:
        //
        //   adb shell am start -n com.minigame.androiddemo/.MainActivity \
        //       --es gameId <slot> [--es entry game.js]
        //
        // Migo's own prescreen runner (scripts/prescreen-run.sh in the engine
        // repo) deploys a bundle into <files>/migo/games/<slot>/code and then
        // needs the host to actually open it. Without this, `am start` lands on
        // the menu above -- and a menu screenshot looks exactly as alive as a
        // running game, which is how a report ends up saying a bundle runs when
        // it was never loaded. The extra is read once, on the launching intent,
        // so a normal tap-through is unaffected.
        String requestedGame = getIntent() == null ? null : getIntent().getStringExtra("gameId");
        if (requestedGame != null && !requestedGame.trim().isEmpty()) {
            String entry = getIntent().getStringExtra("entry");
            launchGameById(requestedGame.trim(), entry == null || entry.trim().isEmpty()
                    ? GAME_ENTRY : entry.trim());
        }
    }

    /** Open a game by its slot id, bypassing the menu. See the headless entry above. */
    private void launchGameById(String gameId, String entry) {
        RuntimeConfig.Builder builder = new RuntimeConfig.Builder(this)
                .setDebugEnabled(true)
                .setCodeSigningEnabled(false)
                ;
        RuntimeConfigCompat.injectFromGameConfig(builder, GameConfigLoader.load(this, gameId));
        DebugMigoGameActivity.launch(this, gameId, entry, builder.build());
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
        DebugMigoGameActivity.launch(this, GAME_ID, GAME_ENTRY, config);
    }

    /**
     * Option 2: Launch the embedded MigoGameView demo.
     */
    private void launchEmbeddedView() {
        Intent intent = new Intent(this, EmbeddedGameActivity.class);
        startActivity(intent);
    }

    /**
     * Option 3: run unmodified wx-shaped content by injecting the
     * migo-wx-adapter bundle as a boot prelude script -- no engine change,
     * no edits to the game's own source. {@code games/wx-adapter-demo/game.js}
     * is a real, previously-shipped wx.* file (this demo's own source before
     * migo dropped its built-in wx mirror); it must be deployed separately
     * with {@code android-java/scripts/push-game.sh wx-adapter-demo}, the
     * same way {@code demo} is.
     */
    private void launchWithWxAdapter() {
        String adapterSource;
        try {
            adapterSource = readAsset(WX_ADAPTER_ASSET);
        } catch (IOException e) {
            Log.e(TAG, "failed to read " + WX_ADAPTER_ASSET, e);
            Toast.makeText(this, "missing " + WX_ADAPTER_ASSET + " in assets/", Toast.LENGTH_LONG).show();
            return;
        }

        RuntimeConfig.Builder builder = new RuntimeConfig.Builder(this)
                .setDebugEnabled(true)
                .setCodeSigningEnabled(false)
                .addPreludeScript(WX_ADAPTER_ASSET, adapterSource);
        RuntimeConfigCompat.injectFromGameConfig(builder, GameConfigLoader.load(this, WX_DEMO_GAME_ID));
        RuntimeConfig config = builder.build();
        DebugMigoGameActivity.launch(this, WX_DEMO_GAME_ID, GAME_ENTRY, config);
    }

    // ---- Helpers ----

    private String readAsset(String name) throws IOException {
        StringBuilder out = new StringBuilder();
        try (InputStream in = getAssets().open(name);
             BufferedReader reader = new BufferedReader(new InputStreamReader(in, StandardCharsets.UTF_8))) {
            char[] buf = new char[8192];
            int n;
            while ((n = reader.read(buf)) >= 0) {
                out.append(buf, 0, n);
            }
        }
        return out.toString();
    }

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
