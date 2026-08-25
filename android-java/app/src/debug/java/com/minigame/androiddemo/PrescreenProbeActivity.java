package com.minigame.androiddemo;

/**
 * The entry point `scripts/prescreen-run.sh` starts, and the only activity in
 * this app that adb is allowed to start.
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
 * It deliberately adds no behaviour. Everything -- config, handlers, the key-path
 * logging a prescreen report is read against -- is inherited, so what the probe
 * runs is what a host built from this example runs. A probe that behaved
 * differently from the example would be measuring itself.
 */
public class PrescreenProbeActivity extends DebugMigoGameActivity {
}
