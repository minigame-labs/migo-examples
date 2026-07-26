/**
 * WeChat Auth Proxy Script
 *
 * Paste this script into the WeChat mini-game console (opened via
 * WeChatOpenDevTools or similar tooling).
 *
 * It continuously polls relay-server.mjs for auth requests from Android,
 * executes real wx auth APIs, and posts the result back.
 *
 * Before pasting, you may set a gameId to bind this proxy to a specific game:
 *   __MIGO_AUTH_GAME_ID__ = 'my-game-id';
 *
 * Runtime controls (type in console):
 *   __MIGO_AUTH_PROXY__.status()
 *   __MIGO_AUTH_PROXY__.stop()
 *   __MIGO_AUTH_PROXY__.setRelayUrl('http://127.0.0.1:9527')
 *   __MIGO_AUTH_PROXY__.setGameId('new-game-id')
 */
(function () {
  'use strict';

  var VERSION = '1.1.0';
  var DEFAULT_RELAY_URL = 'http://127.0.0.1:9527';
  var PHONE_UNSUPPORTED_ERRNO = -12000;

  var existing = globalThis.__MIGO_AUTH_PROXY__;
  if (existing && existing.running) {
    console.warn('[AuthProxy] Already running. Use __MIGO_AUTH_PROXY__.stop() first.');
    return;
  }

  function normalizeRelayUrl(url) {
    var value = (url || '').trim();
    if (!value) {
      value = DEFAULT_RELAY_URL;
    }
    if (value.endsWith('/')) {
      value = value.slice(0, -1);
    }
    return value;
  }

  var relayUrl = normalizeRelayUrl(globalThis.__MIGO_AUTH_RELAY_URL__ || DEFAULT_RELAY_URL);
  var gameId = (globalThis.__MIGO_AUTH_GAME_ID__ || '').trim();

  if (typeof wx === 'undefined') {
    console.error('[AuthProxy] wx is not available in current console context.');
    return;
  }
  if (typeof wx.login !== 'function' || typeof wx.checkSession !== 'function') {
    console.error('[AuthProxy] wx auth APIs are not available in current context.');
    return;
  }

  function sleep(ms) {
    return new Promise(function (resolve) {
      setTimeout(resolve, ms);
    });
  }

  function getErrorMessage(err) {
    if (!err) return 'unknown error';
    if (typeof err === 'string') return err;
    if (err.errMsg) return String(err.errMsg);
    if (err.message) return String(err.message);
    return String(err);
  }

  function createHttpClient() {
    if (typeof wx.request === 'function') {
      return {
        get: function (url) {
          return new Promise(function (resolve, reject) {
            wx.request({
              url: url,
              method: 'GET',
              success: function (res) {
                resolve({ statusCode: res.statusCode, data: res.data });
              },
              fail: function (err) {
                reject(new Error(getErrorMessage(err)));
              },
            });
          });
        },
        post: function (url, data) {
          return new Promise(function (resolve, reject) {
            wx.request({
              url: url,
              method: 'POST',
              header: { 'Content-Type': 'application/json' },
              data: data,
              success: function (res) {
                resolve({ statusCode: res.statusCode, data: res.data });
              },
              fail: function (err) {
                reject(new Error(getErrorMessage(err)));
              },
            });
          });
        },
      };
    }

    if (typeof fetch === 'function') {
      return {
        get: function (url) {
          return fetch(url).then(function (r) {
            if (r.status === 204) {
              return { statusCode: 204, data: null };
            }
            return r.json().then(function (data) {
              return { statusCode: r.status, data: data };
            });
          });
        },
        post: function (url, data) {
          return fetch(url, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(data),
          }).then(function (r) {
            return r.json().then(function (payload) {
              return { statusCode: r.status, data: payload };
            });
          });
        },
      };
    }

    return null;
  }

  var http = createHttpClient();
  if (!http) {
    console.error('[AuthProxy] Neither wx.request nor fetch is available.');
    return;
  }

  function handleLogin(params) {
    return new Promise(function (resolve) {
      var options = {
        success: function (res) {
          resolve({ code: res && res.code ? res.code : '' });
        },
        fail: function (err) {
          resolve({ error: getErrorMessage(err) });
        },
      };

      var timeout = params && Number(params.timeout);
      if (Number.isFinite(timeout) && timeout > 0) {
        options.timeout = timeout;
      }

      try {
        wx.login(options);
      } catch (err) {
        resolve({ error: getErrorMessage(err) });
      }
    });
  }

  function handleCheckSession() {
    return new Promise(function (resolve) {
      try {
        wx.checkSession({
          success: function () {
            resolve({ valid: true });
          },
          fail: function (err) {
            resolve({ error: getErrorMessage(err) });
          },
        });
      } catch (err) {
        resolve({ error: getErrorMessage(err) });
      }
    });
  }

  function handleGetUserInfo(params) {
    if (typeof wx.getUserInfo !== 'function') {
      return Promise.resolve({ error: 'wx.getUserInfo not available' });
    }

    return new Promise(function (resolve) {
      var opts = {
        withCredentials: !!(params && params.withCredentials),
        lang: (params && params.lang) || 'zh_CN',
        success: function (res) {
          resolve({
            userInfo: res.userInfo,
            rawData: res.rawData,
            signature: res.signature,
            encryptedData: res.encryptedData,
            iv: res.iv,
            cloudID: res.cloudID || null,
          });
        },
        fail: function (err) {
          resolve({ error: getErrorMessage(err) });
        },
      };

      try {
        wx.getUserInfo(opts);
      } catch (err) {
        resolve({ error: getErrorMessage(err) });
      }
    });
  }

  function handleGetPhoneNumber() {
    return Promise.resolve({
      error: 'getPhoneNumber requires user interaction and cannot be proxied from console',
      errno: PHONE_UNSUPPORTED_ERRNO,
    });
  }

  function dispatchAuth(request) {
    var action = request.action;
    var params = request.params || {};

    switch (action) {
      case 'login':
        return handleLogin(params);
      case 'checkSession':
        return handleCheckSession();
      case 'getUserInfo':
        return handleGetUserInfo(params);
      case 'getPhoneNumber':
        return handleGetPhoneNumber();
      default:
        return Promise.resolve({ error: 'unknown action: ' + action });
    }
  }

  var state = {
    running: true,
    relayUrl: relayUrl,
    gameId: gameId,
    loopCount: 0,
    successCount: 0,
    errorCount: 0,
    lastError: null,
    lastAction: null,
    startedAt: Date.now(),
  };

  function status() {
    return {
      running: state.running,
      relayUrl: state.relayUrl,
      gameId: state.gameId || '(any)',
      loopCount: state.loopCount,
      successCount: state.successCount,
      errorCount: state.errorCount,
      lastError: state.lastError,
      lastAction: state.lastAction,
      uptimeMs: Date.now() - state.startedAt,
      version: VERSION,
    };
  }

  function stop() {
    state.running = false;
    console.log('[AuthProxy] Stopping...');
  }

  function setRelayUrl(url) {
    state.relayUrl = normalizeRelayUrl(url);
    console.log('[AuthProxy] Relay URL updated:', state.relayUrl);
  }

  function setGameId(id) {
    state.gameId = (id || '').trim();
    console.log('[AuthProxy] Game ID updated:', state.gameId || '(any)');
  }

  async function pollLoop() {
    while (state.running) {
      state.loopCount += 1;
      try {
        var pendingUrl = state.relayUrl + '/auth/pending';
        if (state.gameId) {
          pendingUrl += '?gameId=' + encodeURIComponent(state.gameId);
        }
        var pendingRes = await http.get(pendingUrl);
        if (!state.running) break;

        if (pendingRes.statusCode === 204) {
          continue;
        }
        if (pendingRes.statusCode !== 200 || !pendingRes.data) {
          state.errorCount += 1;
          state.lastError = 'unexpected /auth/pending status: ' + pendingRes.statusCode;
          await sleep(1000);
          continue;
        }

        var request = pendingRes.data;
        state.lastAction = request.action;
        console.log('[AuthProxy] <<', request.action, '(' + request.id + ')');

        var result;
        try {
          result = await dispatchAuth(request);
        } catch (err) {
          result = { error: getErrorMessage(err) };
        }

        var responseRes = await http.post(state.relayUrl + '/auth/response', {
          id: request.id,
          result: result,
        });

        if (responseRes.statusCode >= 200 && responseRes.statusCode < 300) {
          state.successCount += 1;
          console.log('[AuthProxy] >>', request.action, 'done');
        } else {
          state.errorCount += 1;
          state.lastError = 'unexpected /auth/response status: ' + responseRes.statusCode;
          console.warn('[AuthProxy] Failed to post result:', responseRes.statusCode);
        }
      } catch (err) {
        state.errorCount += 1;
        state.lastError = getErrorMessage(err);
        console.error('[AuthProxy] Loop error:', state.lastError);
        await sleep(2000);
      }
    }

    console.log('[AuthProxy] Stopped.');
  }

  var controller = {
    running: true,
    version: VERSION,
    status: status,
    stop: function () {
      stop();
      this.running = false;
    },
    setRelayUrl: setRelayUrl,
    setGameId: setGameId,
  };

  globalThis.__MIGO_AUTH_PROXY__ = controller;

  console.log('===========================================');
  console.log('[AuthProxy] Started');
  console.log('[AuthProxy] relay:', state.relayUrl);
  console.log('[AuthProxy] gameId:', state.gameId || '(any - receives all requests)');
  console.log('[AuthProxy] controls: __MIGO_AUTH_PROXY__.status() / stop() / setGameId(id)');
  console.log('===========================================');

  pollLoop().finally(function () {
    controller.running = false;
  });
})();
