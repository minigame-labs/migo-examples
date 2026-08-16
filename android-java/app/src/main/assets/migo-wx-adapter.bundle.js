/* @minigame-labs/migo-wx-adapter — IIFE bundle. Source: src/index.js */
(() => {
  // src/index.js
  var NON_WX = /* @__PURE__ */ new Set([
    "getGamepads",
    "onGamepadConnected",
    "offGamepadConnected",
    "onGamepadDisconnected",
    "offGamepadDisconnected"
  ]);
  if (!globalThis.__migoWxAdapterInjected) {
    globalThis.__migoWxAdapterInjected = true;
    if (typeof globalThis.migo !== "object" || globalThis.migo === null) {
      throw new Error(
        "@minigame-labs/migo-wx-adapter: globalThis.migo is not present. This adapter must load after the migo runtime has booted (migo installs its namespace during bootstrap, before any content runs)."
      );
    }
    const wx = {};
    const keys = Object.getOwnPropertyNames(globalThis.migo);
    for (let i = 0; i < keys.length; i++) {
      const key = keys[i];
      if (NON_WX.has(key)) continue;
      const desc = Object.getOwnPropertyDescriptor(globalThis.migo, key);
      if (desc) Object.defineProperty(wx, key, desc);
    }
    Object.defineProperty(globalThis, "wx", {
      value: wx,
      writable: true,
      enumerable: true,
      configurable: true
    });
  }
  var index_default = globalThis.wx;
})();
