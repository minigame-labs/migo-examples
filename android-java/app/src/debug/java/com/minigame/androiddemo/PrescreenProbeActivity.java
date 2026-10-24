package com.minigame.androiddemo;

import android.util.Log;

import com.migo.runtime.RuntimeConfig;

import java.io.File;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;

/**
 * The entry point `scripts/prescreen-run.sh` in the engine repo starts, and the
 * only game activity in this app that adb is allowed to start.
 *
 * Why it exists rather than exporting {@link DebugMigoGameActivity}:
 * `android:exported="false"` on a game activity is the correct default and this
 * example should keep teaching it. An exported activity can be started by any
 * app on the device with extras of its choosing, and a game activity takes a
 * game id and loads code from the app's private directory -- not a surface to
 * open by accident in a host someone copies from here.
 *
 * So the export is separated into a thing whose entire job is to be driven from
 * outside, and it lives in `src/debug/` so it does not exist in a release build
 * at all. That boundary is not arbitrary: prescreen deploys the bundle with
 * `run-as`, which already requires a debuggable build, so a probe that exists
 * only in debug builds is present in exactly the situations where prescreen can
 * work anyway.
 *
 * It runs the example's own configuration, handlers and key-path logging, all
 * inherited, so what the probe runs is what a host built from this example runs.
 * The one thing it adds is what the runner asks for and puts in
 * `files/migo-prescreen/`: the adapter the content is written against, and the
 * compatibility recorder, which logs at INFO. Each is logged with its digest when
 * injected, and the run report confirms what it asked for by that line.
 */
public class PrescreenProbeActivity extends DebugMigoGameActivity {

    static final String EXTRA_ADAPTER = "migo_prescreen_adapter";
    static final String EXTRA_RECORD = "migo_prescreen_record";
    private static final String TAG = "PrescreenProbe";

    @Override
    protected RuntimeConfig onCreateRuntimeConfig() {
        RuntimeConfig.Builder builder = exampleConfig();
        File dir = new File(getFilesDir(), "migo-prescreen");
        if (getIntent().getBooleanExtra(EXTRA_ADAPTER, false)) {
            inject(builder, new File(dir, "adapter.js"), "<prescreen-adapter>");
        }
        if (getIntent().getBooleanExtra(EXTRA_RECORD, false)
                && inject(builder, new File(dir, "recorder.js"), "<migo-compat-recorder>")) {
            builder.setLogLevel(RuntimeConfig.LogLevel.INFO);
        }
        return builder.build();
    }

    /**
     * After whatever was injected before it. A file that cannot be read, or that the runtime
     * refuses (an empty one), runs without it, and says so.
     */
    private static boolean inject(RuntimeConfig.Builder builder, File file, String name) {
        byte[] source;
        try {
            source = Files.readAllBytes(file.toPath());
            builder.addPreludeScript(name, new String(source, StandardCharsets.UTF_8));
        } catch (IOException | IllegalArgumentException e) {
            Log.e(TAG, "not injected " + name + ": " + e);
            return false;
        }
        Log.i(TAG, "injected " + name + " sha256=" + sha256(source));
        return true;
    }

    private static String sha256(byte[] bytes) {
        try {
            StringBuilder hex = new StringBuilder();
            for (byte b : MessageDigest.getInstance("SHA-256").digest(bytes)) {
                hex.append(String.format("%02x", b));
            }
            return hex.toString();
        } catch (NoSuchAlgorithmException e) {
            throw new AssertionError(e);
        }
    }
}
