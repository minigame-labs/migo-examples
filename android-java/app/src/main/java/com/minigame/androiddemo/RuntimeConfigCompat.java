package com.minigame.androiddemo;

import android.util.Log;

import com.migo.runtime.RuntimeConfig;

import java.lang.reflect.Method;

/**
 * Compatibility helpers for RuntimeConfig.Builder across SDK versions.
 */
public final class RuntimeConfigCompat {

    private static final String TAG = "RuntimeConfigCompat";

    private RuntimeConfigCompat() {}

    /**
     * Inject workers path if the current SDK exposes setWorkersPath(String).
     */
    public static RuntimeConfig.Builder injectWorkersPath(RuntimeConfig.Builder builder, String workersPath) {
        if (builder == null || workersPath == null) {
            return builder;
        }
        String path = workersPath.trim();
        if (path.isEmpty()) {
            return builder;
        }
        try {
            Method method = RuntimeConfig.Builder.class.getMethod("setWorkersPath", String.class);
            method.invoke(builder, path);
        } catch (Exception e) {
            Log.w(TAG, "setWorkersPath() not found in current SDK, skip workers config injection");
        }
        return builder;
    }

    /**
     * Inject one subpackage definition if addSubPackage(String, String) exists.
     */
    public static RuntimeConfig.Builder injectSubPackage(
            RuntimeConfig.Builder builder,
            String name,
            String root
    ) {
        if (builder == null || name == null || root == null) {
            return builder;
        }
        String n = name.trim();
        String r = root.trim();
        if (n.isEmpty() || r.isEmpty()) {
            return builder;
        }
        try {
            Method method = RuntimeConfig.Builder.class.getMethod(
                    "addSubPackage", String.class, String.class);
            method.invoke(builder, n, r);
        } catch (Exception e) {
            Log.w(TAG, "addSubPackage() not found in current SDK, skip subpackage injection");
        }
        return builder;
    }

    /**
     * Inject startup orientation if setStartupOrientation(String) exists.
     */
    public static RuntimeConfig.Builder injectStartupOrientation(
            RuntimeConfig.Builder builder,
            String startupOrientation
    ) {
        if (builder == null || startupOrientation == null) {
            return builder;
        }
        String value = startupOrientation.trim();
        if (value.isEmpty()) {
            return builder;
        }
        try {
            Method method = RuntimeConfig.Builder.class.getMethod(
                    "setStartupOrientation", String.class);
            method.invoke(builder, value);
        } catch (Exception e) {
            Log.w(TAG, "setStartupOrientation() not found in current SDK, skip startup orientation injection");
        }
        return builder;
    }

    /**
     * Inject parsed host game config fields into RuntimeConfig.Builder.
     */
    public static RuntimeConfig.Builder injectFromGameConfig(
            RuntimeConfig.Builder builder,
            GameConfigLoader.GameConfig gameConfig
    ) {
        if (builder == null || gameConfig == null) {
            return builder;
        }

        injectWorkersPath(builder, gameConfig.workersPath);
        for (GameConfigLoader.SubpackageDef subPackage : gameConfig.subPackages) {
            injectSubPackage(builder, subPackage.name, subPackage.root);
        }
        injectStartupOrientation(builder, gameConfig.startupOrientation);
        return builder;
    }
}
