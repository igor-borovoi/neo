"use strict";

// Key codes shared with src/wasm_main.zig
const KEY = { UP: 0x101, DOWN: 0x102, RIGHT: 0x103, LEFT: 0x104, ESC: 27 };

// Mirrors types.Color enum order
const COLOR_IDS = {
  green: 1, green2: 2, green3: 3, yellow: 4, orange: 5, red: 6, blue: 7,
  cyan: 8, gold: 9, rainbow: 10, purple: 11, pink: 12, pink2: 13,
  vaporwave: 14, gray: 15,
};

// Mirrors types.Charset enum values
const CHARSET_IDS = {
  english: 0x1, digits: 0x2, punc: 0x4, ascii: 0x7, extended: 0xE,
  katakana: 0x8, greek: 0x10, cyrillic: 0x20, arabic: 0x40, hebrew: 0x80,
  binary: 0x100, hex: 0x200, devanagari: 0x400, braille: 0x800,
  runic: 0x1000, mix: 0x2000,
};

const FONT = 'Menlo, Monaco, Consolas, "Courier New", monospace';
const FONT_PX = 18;

const canvas = document.getElementById("screen");
const ctx = canvas.getContext("2d");
const notification = document.getElementById("notification");
const hint = document.getElementById("hint");

let wasm = null;
let cellW = 0;
let cellH = 0;
let cols = 0;
let lines = 0;
let lastFrame = 0;
let notifyTimer = 0;

async function main() {
  let instance;
  try {
    ({ instance } = await WebAssembly.instantiateStreaming(fetch("neo.wasm"), {}));
  } catch (err) {
    const el = document.getElementById("error");
    el.textContent = location.protocol === "file:"
      ? "Serve this directory over HTTP, e.g.: python3 -m http.server -d zig-out/web"
      : "Failed to load neo.wasm: " + err.message;
    el.style.display = "block";
    return;
  }
  wasm = instance.exports;

  ctx.font = FONT_PX + "px " + FONT;
  cellW = Math.ceil(Math.max(ctx.measureText("M").width, ctx.measureText("ｱ").width));
  cellH = Math.round(FONT_PX * 1.2);

  const params = new URLSearchParams(location.search);
  const colorId = COLOR_IDS[params.get("color")] ?? COLOR_IDS.green;
  const charsetId = CHARSET_IDS[params.get("charset")] ?? CHARSET_IDS.mix;
  const fps = parseFloat(params.get("speed")) || 20;
  let seed = new Uint32Array(2);
  if (params.has("seed")) {
    const n = BigInt(params.get("seed"));
    seed[0] = Number(n & 0xFFFFFFFFn);
    seed[1] = Number((n >> 32n) & 0xFFFFFFFFn);
  } else {
    crypto.getRandomValues(seed);
  }

  wasm.neoInit(seed[0], seed[1], colorId, charsetId, fps);
  resize();

  window.addEventListener("resize", resize);
  window.addEventListener("keydown", onKey);
  setTimeout(() => { hint.style.opacity = "0"; }, 6000);
  watchForChanges();
  requestAnimationFrame(loop);
}

// Dev auto-reload: only active on localhost so deployed copies don't poll.
function watchForChanges() {
  if (location.hostname !== "localhost" && location.hostname !== "127.0.0.1") return;
  const files = ["neo.wasm", "neo.js", "index.html"];
  let stamp = null;
  setInterval(async () => {
    try {
      const parts = await Promise.all(files.map(async (f) => {
        const res = await fetch(f, { method: "HEAD", cache: "no-store" });
        return res.headers.get("last-modified") + "|" + res.headers.get("content-length");
      }));
      const cur = parts.join(";");
      if (stamp === null) stamp = cur;
      else if (cur !== stamp) location.reload();
    } catch {
      // Server briefly down mid-rebuild; retry on the next tick.
    }
  }, 1000);
}

function resize() {
  const dpr = window.devicePixelRatio || 1;
  canvas.width = Math.floor(innerWidth * dpr);
  canvas.height = Math.floor(innerHeight * dpr);
  canvas.style.width = innerWidth + "px";
  canvas.style.height = innerHeight + "px";
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  ctx.textAlign = "center";
  ctx.textBaseline = "middle";
  cols = Math.max(8, Math.floor(innerWidth / cellW));
  lines = Math.max(4, Math.floor(innerHeight / cellH));
  wasm.neoReset(lines, cols, performance.now());
  ctx.fillStyle = "#000";
  ctx.fillRect(0, 0, innerWidth, innerHeight);
}

function loop(now) {
  requestAnimationFrame(loop);
  const targetMs = 1000 / wasm.neoTargetFps();
  if (now - lastFrame < targetMs - 0.5) return;
  lastFrame = now;

  const words = wasm.neoFrame(now);
  if (wasm.neoClearRequested()) {
    ctx.fillStyle = "#000";
    ctx.fillRect(0, 0, innerWidth, innerHeight);
  }
  if (words === 0) return;

  const ops = new Uint32Array(wasm.memory.buffer, wasm.neoOpsPtr(), words);
  let curFont = "";
  for (let i = 0; i < words; i += 3) {
    const y = ops[i] >>> 16;
    const x = ops[i] & 0xFFFF;
    const cp = ops[i + 1];
    const style = ops[i + 2];
    const px = x * cellW;
    const py = y * cellH;

    ctx.fillStyle = "#000";
    ctx.fillRect(px, py, cellW, cellH);
    if (cp === 32 || cp === 0) continue;

    const font = (style & 1 ? "bold " : "") + FONT_PX + "px " + FONT;
    if (font !== curFont) {
      ctx.font = font;
      curFont = font;
    }
    ctx.fillStyle = "#" + ((style >>> 8) & 0xFFFFFF).toString(16).padStart(6, "0");
    ctx.fillText(String.fromCodePoint(cp), px + cellW / 2, py + cellH / 2);
  }
}

function onKey(e) {
  if (e.metaKey || e.ctrlKey || e.altKey) return;
  let code = null;
  switch (e.key) {
    case "ArrowUp": code = KEY.UP; break;
    case "ArrowDown": code = KEY.DOWN; break;
    case "ArrowLeft": code = KEY.LEFT; break;
    case "ArrowRight": code = KEY.RIGHT; break;
    case "Escape": code = KEY.ESC; break;
    default:
      if (e.key.length === 1) code = e.key.codePointAt(0);
  }
  if (code === null) return;

  const result = wasm.neoOnKey(code, performance.now());
  switch (result) {
    case 2: hideNotification(); break;
    case 3: notify(" Speed: " + Math.round(wasm.neoTargetFps()) + " "); break;
    case 4: notify(" Charset: " + charsetName() + " "); break;
    case 5: notify(" Stopped - press Space to restart ", 0); break;
  }
  if (result !== 0) e.preventDefault();
}

function charsetName() {
  const bytes = new Uint8Array(wasm.memory.buffer, wasm.neoCharsetNamePtr(), wasm.neoCharsetNameLen());
  return new TextDecoder().decode(bytes);
}

function notify(text, timeoutMs = 5000) {
  notification.textContent = text;
  notification.style.display = "block";
  clearTimeout(notifyTimer);
  if (timeoutMs > 0) notifyTimer = setTimeout(hideNotification, timeoutMs);
}

function hideNotification() {
  notification.style.display = "none";
}

main();
