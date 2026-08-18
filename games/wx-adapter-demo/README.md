# wx-adapter-demo

Content written against `wx.*`, unmodified. There is no `migo.*` anywhere in
`game.js` — it calls `wx.createCanvas()`, `wx.onTouchStart()` and so on, exactly
as content distributed by a mini-game platform does.

Migo itself never installs `wx`. The engine only ever provides `migo.*`; `wx` is
supplied by injecting the
[migo-wx-adapter](https://github.com/minigame-labs/migo-wx-adapter) IIFE bundle
as a **prelude script**, before the game's main module runs. That is what makes
the content runnable without editing it, and it is the host's job, not the
engine's.

## Running it

**Android** — supported. `MainActivity`'s third button does exactly this; see
[android-java/README.md](../../android-java/README.md#option-3-adapter-injection-unmodified-wx-shaped-content).
The adapter bundle is committed at
`android-java/app/src/main/assets/migo-wx-adapter.bundle.js`.

**Linux, Windows, OpenHarmony** — not as-is. Those hosts drive the engine
through the C ABI, which exposes no way to install a prelude script, so nothing
defines `wx` and the content stops on its first line:

```
bash linux-cmake/run.sh games/wx-adapter-demo
...
ReferenceError: wx is not defined
```

That is the expected result today, not a broken checkout. Prelude injection
exists in the engine (`InitOptions::with_prelude_script`) and is reachable from
the Android binding; the C ABI does not carry it.

## What C ABI hosts can do instead

Prepend the adapter to the content rather than injecting it at boot — one file
that is adapter-then-game. `migo-bench`'s bunnymark does this, and its first
line says so:

```js
// migo-web-adapter prelude (browser globals -> migo.*) + bunnymark game. Auto-generated.
```

It runs on the Linux example unchanged. The tradeoff is the point of this demo:
pre-bundling means the shipped bytes are no longer the platform's bytes, while
injection leaves the content byte-identical to what a game centre distributed.
