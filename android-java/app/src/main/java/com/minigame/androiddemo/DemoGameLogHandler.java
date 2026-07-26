package com.minigame.androiddemo;

import android.util.Log;

import com.migo.runtime.callback.GameLogHandler;

/**
 * Sample GameLogHandler implementation for demo integration.
 */
public final class DemoGameLogHandler implements GameLogHandler {

    private static final String TAG = "DemoGameLog";

    @Override
    public void onLog(String logJson) {
        Log.i(TAG, logJson != null ? logJson : "{}");
    }
}
