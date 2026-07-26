package com.minigame.androiddemo;

import android.util.Log;

import com.migo.runtime.callback.SubpackageHandler;

import java.io.File;

/**
 * Sample SubpackageHandler implementation.
 *
 * This demo handler does not download remote bundles.
 * It succeeds only when the subpackage directory already exists under codeDir.
 */
public final class DemoSubpackageHandler implements SubpackageHandler {

    private static final String TAG = "DemoSubpackage";

    private final File codeDir;

    public DemoSubpackageHandler(File codeDir) {
        if (codeDir == null) {
            throw new IllegalArgumentException("codeDir cannot be null");
        }
        this.codeDir = codeDir;
    }

    @Override
    public void download(SubpackageRequest request, DownloadCallback callback) {
        if (callback == null) {
            return;
        }
        if (request == null || request.root == null || request.root.trim().isEmpty()) {
            callback.onFailure("invalid subpackage request");
            return;
        }

        String root = request.root.trim();
        if (root.contains("..")) {
            callback.onFailure("invalid subpackage root: " + root);
            return;
        }

        File targetDir = new File(codeDir, root);
        if (targetDir.isDirectory()) {
            // Local directory already exists — no zip to provide.
            // Pass null zipPath so the runtime skips ingest and mounts
            // directly from the existing files.
            callback.onProgress(100, 1, 1);
            callback.onSuccess(null);
            Log.i(TAG, "Using existing subpackage: " + targetDir.getAbsolutePath());
            return;
        }

        String message = "subpackage not found: " + targetDir.getAbsolutePath();
        Log.w(TAG, message);
        callback.onFailure(message);
    }
}
