// Migo integration self-check content.
//
// Two things are observable without any tooling:
//   - the bar sweeps across the screen every frame, so motion means the engine
//     is driving requestAnimationFrame and painting;
//   - the background changes colour on touch, so a colour change means input
//     crossed the host boundary and reached JS.
const canvas = wx.createCanvas();
const ctx = canvas.getContext('2d');

const IDLE = '#101828';
const TOUCHED = '#0b6b3a';

let background = IDLE;
let touches = 0;
let frames = 0;

wx.onTouchStart(function (e) {
  touches = ((e && e.touches) || []).length;
  background = TOUCHED;
});

function onTouchEnd() {
  touches = 0;
  background = IDLE;
}

wx.onTouchEnd(onTouchEnd);
// A cancelled gesture (finger leaves the surface, a system gesture takes
// over) never fires onTouchEnd. Without this, a cancel would leave the
// background stuck green -- a false pass for a probe whose only job is to
// show that input reached JS right now.
wx.onTouchCancel(onTouchEnd);

function paint() {
  frames += 1;

  const w = canvas.width;
  const h = canvas.height;

  ctx.fillStyle = background;
  ctx.fillRect(0, 0, w, h);

  // Sweeping bar: position is a pure function of the frame counter, so a still
  // screenshot taken twice shows different positions only if frames advanced.
  const barWidth = Math.max(8, w * 0.08);
  const travel = w - barWidth;
  const phase = (frames % 240) / 240;
  const x = travel * (phase < 0.5 ? phase * 2 : (1 - phase) * 2);

  ctx.fillStyle = '#f5b301';
  ctx.fillRect(x, h * 0.45, barWidth, h * 0.1);

  ctx.fillStyle = '#e6e8ec';
  ctx.font = '32px sans-serif';
  ctx.fillText('migo demo', 24, 80);
  ctx.fillText('frames ' + frames, 24, 128);
  ctx.fillText('touches ' + touches, 24, 176);

  requestAnimationFrame(paint);
}

paint();
