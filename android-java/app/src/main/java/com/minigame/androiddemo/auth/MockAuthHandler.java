package com.minigame.androiddemo.auth;

import android.util.Log;

import com.migo.runtime.callback.AuthHandler;

/**
 * AuthHandler implementation that returns canned, local results.
 * <p>
 * Demonstrates the shape of the interface only. A real integration replaces
 * this with calls to your own backend / identity provider -- {@code login}
 * would exchange a code for a session with your server, {@code getUserInfo}
 * would return your own profile record, and so on.
 *
 * <p>Usage:
 * <pre>
 *   session.setAuthHandler(new MockAuthHandler());
 * </pre>
 */
public class MockAuthHandler implements AuthHandler {

    private static final String TAG = "MockAuthHandler";

    @Override
    public void login(int timeoutMs, LoginCallback callback) {
        Log.d(TAG, "login(timeoutMs=" + timeoutMs + ")");
        if (callback != null) callback.onSuccess("mock-login-code-" + System.currentTimeMillis());
    }

    @Override
    public void checkSession(CheckSessionCallback callback) {
        Log.d(TAG, "checkSession()");
        if (callback != null) callback.onSuccess();
    }

    @Override
    public void getUserInfo(boolean withCredentials, String lang, UserInfoCallback callback) {
        Log.d(TAG, "getUserInfo(withCredentials=" + withCredentials + ", lang=" + lang + ")");
        if (callback == null) return;

        UserInfo userInfo = new UserInfo();
        userInfo.nickName = "Demo Player";
        userInfo.avatarUrl = "";
        userInfo.gender = 0;
        userInfo.country = "";
        userInfo.province = "";
        userInfo.city = "";
        userInfo.language = lang != null ? lang : "zh_CN";

        UserInfoResult result = new UserInfoResult();
        result.userInfo = userInfo;
        callback.onSuccess(result);
    }

    @Override
    public void getPhoneNumber(boolean isRealtime, boolean phoneNumberNoQuotaToast,
                               PhoneNumberCallback callback) {
        Log.d(TAG, "getPhoneNumber(isRealtime=" + isRealtime + ")");
        if (callback != null) {
            callback.onFailure("getPhoneNumber requires a real backend; not implemented in this demo", null);
        }
    }
}
