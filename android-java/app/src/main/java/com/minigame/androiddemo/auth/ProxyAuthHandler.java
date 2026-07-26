package com.minigame.androiddemo.auth;

import android.util.Log;

import com.migo.runtime.callback.AuthHandler;

import org.json.JSONException;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * AuthHandler implementation that proxies all auth requests to a relay server.
 * <p>
 * The relay server forwards requests to a proxy script injected into a real
 * WeChat mini-game running on PC (via WeChatOpenDevTools), which calls the
 * real wx.login / wx.checkSession / wx.getUserInfo / wx.getPhoneNumber APIs.
 *
 * <p>Usage:
 * <pre>
 *   session.setAuthHandler(new ProxyAuthHandler("http://192.168.1.100:9527", "my-game"));
 * </pre>
 */
public class ProxyAuthHandler implements AuthHandler {

    private static final String TAG = "ProxyAuthHandler";
    private static final ExecutorService AUTH_EXECUTOR = Executors.newCachedThreadPool(r -> {
        Thread t = new Thread(r, "proxy-auth");
        t.setDaemon(true);
        return t;
    });

    private final String relayUrl;
    private final String gameId;

    /**
     * @param relayUrl base URL of the relay server, e.g. "http://192.168.1.100:9527"
     * @param gameId   game identifier for routing to the correct WeChat proxy (may be null)
     */
    public ProxyAuthHandler(String relayUrl, String gameId) {
        if (relayUrl == null || relayUrl.trim().isEmpty()) {
            throw new IllegalArgumentException("relayUrl cannot be null or empty");
        }
        relayUrl = relayUrl.trim();
        // Strip trailing slash
        this.relayUrl = relayUrl.endsWith("/")
                ? relayUrl.substring(0, relayUrl.length() - 1)
                : relayUrl;
        this.gameId = gameId != null ? gameId.trim() : "";
    }

    /** Convenience constructor without gameId (matches any proxy). */
    public ProxyAuthHandler(String relayUrl) {
        this(relayUrl, "");
    }

    @Override
    public void login(int timeoutMs, LoginCallback callback) {
        runAsync(() -> {
            try {
                JSONObject params = new JSONObject();
                params.put("timeout", timeoutMs);

                JSONObject result = sendRequest("login", params);
                Log.d(TAG, "login result: " + result);

                if (result.has("error")) {
                    if (callback != null) callback.onFailure(result.getString("error"));
                } else {
                    if (callback != null) callback.onSuccess(result.optString("code", ""));
                }
            } catch (Exception e) {
                Log.e(TAG, "login proxy error", e);
                if (callback != null) callback.onFailure("proxy error: " + e.getMessage());
            }
        });
    }

    @Override
    public void checkSession(CheckSessionCallback callback) {
        runAsync(() -> {
            try {
                JSONObject result = sendRequest("checkSession", new JSONObject());
                Log.d(TAG, "checkSession result: " + result);

                if (result.has("error")) {
                    if (callback != null) callback.onFailure(result.getString("error"));
                } else {
                    if (callback != null) callback.onSuccess();
                }
            } catch (Exception e) {
                Log.e(TAG, "checkSession proxy error", e);
                if (callback != null) callback.onFailure("proxy error: " + e.getMessage());
            }
        });
    }

    @Override
    public void getUserInfo(boolean withCredentials, String lang, UserInfoCallback callback) {
        runAsync(() -> {
            try {
                JSONObject params = new JSONObject();
                params.put("withCredentials", withCredentials);
                params.put("lang", lang != null ? lang : "zh_CN");

                JSONObject result = sendRequest("getUserInfo", params);
                Log.d(TAG, "getUserInfo result: " + result);

                if (result.has("error")) {
                    if (callback != null) callback.onFailure(result.getString("error"));
                } else {
                    UserInfoResult uir = parseUserInfoResult(result);
                    if (callback != null) callback.onSuccess(uir);
                }
            } catch (Exception e) {
                Log.e(TAG, "getUserInfo proxy error", e);
                if (callback != null) callback.onFailure("proxy error: " + e.getMessage());
            }
        });
    }

    @Override
    public void getPhoneNumber(boolean isRealtime, boolean phoneNumberNoQuotaToast,
                               PhoneNumberCallback callback) {
        runAsync(() -> {
            try {
                JSONObject params = new JSONObject();
                params.put("isRealtime", isRealtime);
                params.put("phoneNumberNoQuotaToast", phoneNumberNoQuotaToast);

                JSONObject result = sendRequest("getPhoneNumber", params);
                Log.d(TAG, "getPhoneNumber result: " + result);

                if (result.has("error")) {
                    String error = result.getString("error");
                    Integer errno = result.has("errno") ? result.getInt("errno") : null;
                    if (callback != null) callback.onFailure(error, errno);
                } else {
                    if (callback != null) callback.onSuccess(result.optString("code", ""));
                }
            } catch (Exception e) {
                Log.e(TAG, "getPhoneNumber proxy error", e);
                if (callback != null) callback.onFailure("proxy error: " + e.getMessage(), null);
            }
        });
    }

    // ---- Internal helpers ----

    private JSONObject sendRequest(String action, JSONObject params) throws Exception {
        JSONObject body = new JSONObject();
        body.put("action", action);
        body.put("params", params);
        if (!gameId.isEmpty()) {
            body.put("gameId", gameId);
        }

        URL url = new URL(relayUrl + "/auth/request");
        HttpURLConnection conn = (HttpURLConnection) url.openConnection();
        try {
            conn.setRequestMethod("POST");
            conn.setRequestProperty("Content-Type", "application/json; charset=UTF-8");
            conn.setDoOutput(true);
            conn.setConnectTimeout(5000);
            conn.setReadTimeout(35000); // relay has 30s internal timeout

            byte[] payload = body.toString().getBytes(StandardCharsets.UTF_8);
            try (OutputStream os = conn.getOutputStream()) {
                os.write(payload);
            }

            int code = conn.getResponseCode();
            boolean ok = code >= 200 && code < 300;

            InputStream stream = ok ? conn.getInputStream() : conn.getErrorStream();
            String responseBody = "";
            if (stream != null) {
                StringBuilder sb = new StringBuilder();
                try (BufferedReader br = new BufferedReader(new InputStreamReader(stream, StandardCharsets.UTF_8))) {
                    String line;
                    while ((line = br.readLine()) != null) {
                        sb.append(line);
                    }
                }
                responseBody = sb.toString();
            }

            if (!ok) {
                throw new RuntimeException("HTTP " + code + ": " + responseBody);
            }
            return responseBody.isEmpty() ? new JSONObject() : new JSONObject(responseBody);
        } finally {
            conn.disconnect();
        }
    }

    private static UserInfoResult parseUserInfoResult(JSONObject result) throws JSONException {
        UserInfoResult uir = new UserInfoResult();
        if (result.has("userInfo")) {
            JSONObject ui = result.getJSONObject("userInfo");
            uir.userInfo = new UserInfo();
            uir.userInfo.nickName = ui.optString("nickName", "");
            uir.userInfo.avatarUrl = ui.optString("avatarUrl", "");
            uir.userInfo.gender = ui.optInt("gender", 0);
            uir.userInfo.country = ui.optString("country", "");
            uir.userInfo.province = ui.optString("province", "");
            uir.userInfo.city = ui.optString("city", "");
            uir.userInfo.language = ui.optString("language", "zh_CN");
        }
        uir.rawData = result.optString("rawData", null);
        uir.signature = result.optString("signature", null);
        uir.encryptedData = result.optString("encryptedData", null);
        uir.iv = result.optString("iv", null);
        uir.cloudID = result.optString("cloudID", null);
        return uir;
    }

    private static void runAsync(Runnable task) {
        AUTH_EXECUTOR.execute(task);
    }
}
