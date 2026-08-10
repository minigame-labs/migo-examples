// Simple solid color test
const canvas = wx.createCanvas();
const ctx = canvas.getContext('2d');

ctx.fillStyle = '#ff0000';  // Red
ctx.fillRect(0, 0, canvas.width, canvas.height);

ctx.fillStyle = '#00ff00';  // Green
ctx.fillRect(100, 100, 200, 200);

ctx.fillStyle = '#ffffff';
ctx.font = '48px sans-serif';
ctx.fillText('RED BG + GREEN BOX', 20, 100);
