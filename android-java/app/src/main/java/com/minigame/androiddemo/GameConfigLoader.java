package com.minigame.androiddemo;

import android.content.Context;
import android.util.Log;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

/**
 * Loads game.json from app private game code directory.
 */
public final class GameConfigLoader {

    private static final String TAG = "GameConfigLoader";

    private GameConfigLoader() {}

    public static final class SubpackageDef {
        public final String name;
        public final String root;

        SubpackageDef(String name, String root) {
            this.name = name;
            this.root = root;
        }
    }

    public static final class GameConfig {
        public final List<SubpackageDef> subPackages = new ArrayList<>();
        public String workersPath = null;
        public String startupOrientation = null;
    }

    public static GameConfig load(Context context, String gameId) {
        GameConfig out = new GameConfig();
        if (context == null || gameId == null || gameId.trim().isEmpty()) {
            return out;
        }

        File gameJson = new File(getCodeDir(context, gameId), "game.json");
        if (!gameJson.isFile()) {
            return out;
        }

        final String json;
        try {
            json = readUtf8(gameJson);
        } catch (IOException e) {
            Log.w(TAG, "Failed to read game.json: " + gameJson.getAbsolutePath(), e);
            return out;
        }

        try {
            JSONObject root = new JSONObject(json);
            parseSubPackages(root, out);
            parseWorkers(root, out);
            parseStartupOrientation(root, out);
        } catch (JSONException e) {
            Log.w(TAG, "Invalid game.json: " + gameJson.getAbsolutePath(), e);
        }

        return out;
    }

    private static File getCodeDir(Context context, String gameId) {
        File migoDir = new File(context.getFilesDir(), "migo");
        File gamesDir = new File(migoDir, "games");
        File gameDir = new File(gamesDir, gameId);
        return new File(gameDir, "code");
    }

    private static void parseSubPackages(JSONObject root, GameConfig out) {
        JSONArray arr = root.optJSONArray("subPackages");
        if (arr == null) {
            arr = root.optJSONArray("subpackages");
        }
        if (arr == null) {
            return;
        }

        for (int i = 0; i < arr.length(); i++) {
            JSONObject item = arr.optJSONObject(i);
            if (item == null) {
                continue;
            }

            String rawRoot = trim(item.optString("root", ""));
            if (rawRoot.isEmpty()) {
                rawRoot = trim(item.optString("name", ""));
            }
            String rootNorm = normalizeRoot(rawRoot);
            if (rootNorm.isEmpty()) {
                continue;
            }

            String name = trim(item.optString("name", ""));
            if (name.isEmpty()) {
                name = deriveNameFromRoot(rootNorm);
            }
            if (name.isEmpty()) {
                continue;
            }

            out.subPackages.add(new SubpackageDef(name, rootNorm));
        }
    }

    private static void parseWorkers(JSONObject root, GameConfig out) {
        Object workers = root.opt("workers");
        String path = "";

        if (workers instanceof String) {
            path = (String) workers;
        } else if (workers instanceof JSONObject) {
            path = ((JSONObject) workers).optString("path", "");
        }

        path = normalizeRoot(path);
        if (!path.isEmpty()) {
            out.workersPath = path;
        }
    }

    private static void parseStartupOrientation(JSONObject root, GameConfig out) {
        String orientation = trim(root.optString("deviceOrientation", ""));
        if (orientation.isEmpty()) {
            return;
        }

        String normalized = orientation.toLowerCase(Locale.US);
        if ("landscape".equals(normalized) || "portrait".equals(normalized)) {
            out.startupOrientation = normalized;
        }
    }

    private static String trim(String s) {
        return s == null ? "" : s.trim();
    }

    private static String normalizeRoot(String root) {
        String value = trim(root);
        while (value.startsWith("./")) {
            value = value.substring(2);
        }
        while (value.startsWith("/")) {
            value = value.substring(1);
        }
        while (value.endsWith("/")) {
            value = value.substring(0, value.length() - 1);
        }
        if (value.isEmpty()) {
            return "";
        }

        String[] parts = value.split("/");
        for (String part : parts) {
            if ("..".equals(part)) {
                return "";
            }
        }
        return value;
    }

    private static String deriveNameFromRoot(String root) {
        String normalized = normalizeRoot(root);
        if (normalized.isEmpty()) {
            return "";
        }
        int idx = normalized.lastIndexOf('/');
        return idx >= 0 ? normalized.substring(idx + 1) : normalized;
    }

    private static String readUtf8(File file) throws IOException {
        try (FileInputStream in = new FileInputStream(file);
             ByteArrayOutputStream out = new ByteArrayOutputStream()) {
            byte[] buf = new byte[4096];
            int read;
            while ((read = in.read(buf)) != -1) {
                out.write(buf, 0, read);
            }
            return out.toString("UTF-8");
        }
    }
}
