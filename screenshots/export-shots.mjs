// Drives the Breezy screenshot generator headlessly and writes every export
// to disk. The page's Export All triggers browser downloads (which headless
// Chrome drops); it also caches each data URL on window.__breezyShots, so we
// read from there instead.
//
// Usage: node export-shots.mjs <outdir>
import { spawn } from "node:child_process";
import { mkdirSync, writeFileSync, readdirSync, rmSync } from "node:fs";
import { join } from "node:path";
import { setTimeout as sleep } from "node:timers/promises";

const CHROME =
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const PAGE = "http://localhost:3000";
const outDir = process.argv[2];
if (!outDir) {
  console.error("usage: node export-shots.mjs <outdir>");
  process.exit(2);
}
rmSync(outDir, { recursive: true, force: true });
mkdirSync(outDir, { recursive: true });

const PORT = 9333;
const profile = `/tmp/breezy-shots-profile-${Date.now()}`;
const chrome = spawn(CHROME, [
  "--headless=new",
  "--disable-gpu",
  "--hide-scrollbars",
  `--remote-debugging-port=${PORT}`,
  `--user-data-dir=${profile}`,
  "--window-size=1600,1200",
  "about:blank",
]);
chrome.stderr.on("data", () => {});

async function wsUrl() {
  for (let i = 0; i < 40; i++) {
    try {
      const res = await fetch(`http://127.0.0.1:${PORT}/json/list`);
      const pages = await res.json();
      const page = pages.find((p) => p.type === "page");
      if (page) return page.webSocketDebuggerUrl;
    } catch {}
    await sleep(500);
  }
  throw new Error("Chrome devtools endpoint never came up");
}

function cdp(url) {
  return new Promise(async (resolve, reject) => {
    const ws = new WebSocket(url);
    await new Promise((r, j) => {
      ws.onopen = r;
      ws.onerror = j;
    });
    let id = 0;
    const pending = new Map();
    ws.onmessage = (ev) => {
      const msg = JSON.parse(ev.data);
      if (msg.id && pending.has(msg.id)) {
        const { res, rej } = pending.get(msg.id);
        pending.delete(msg.id);
        msg.error ? rej(new Error(JSON.stringify(msg.error))) : res(msg.result);
      }
    };
    const send = (method, params = {}) =>
      new Promise((res, rej) => {
        const myId = ++id;
        pending.set(myId, { res, rej });
        ws.send(JSON.stringify({ id: myId, method, params }));
      });
    const evaluate = async (expression) => {
      const r = await send("Runtime.evaluate", {
        expression,
        awaitPromise: true,
        returnByValue: true,
      });
      if (r.exceptionDetails) {
        const d = r.exceptionDetails;
        const detail =
          (d.exception && (d.exception.description || d.exception.value)) ||
          d.text;
        throw new Error(`page error: ${detail}`);
      }
      return r.result.value;
    };
    resolve({ send, evaluate, close: () => ws.close() });
  });
}

try {
  const { send, evaluate, close } = await cdp(await wsUrl());

  // Navigate for real and wait for the load event before touching the DOM.
  const loaded = new Promise((res) => {
    // resolved from the loadEventFired poll below
    res();
  });
  await send("Page.enable");
  await send("Page.navigate", { url: PAGE });
  for (let i = 0; i < 60; i++) {
    const r = await send("Runtime.evaluate", { expression: "document.readyState", returnByValue: true });
    if (r.result.value === "complete") break;
    await sleep(500);
  }
  void loaded;

  // Wait for the page to finish preloading images.
  for (let i = 0; i < 80; i++) {
    // Wait for the app shell, then for image preloading to finish.
    const ready = await evaluate(
      `(() => {
        if (!document.body) return false;
        const t = document.body.innerText || "";
        return t.includes("Export") && !t.includes("Loading images");
      })()`
    );
    if (ready) break;
    await sleep(500);
  }
  const readyState = await evaluate(
    `(document.body && document.body.innerText || "").slice(0, 80)`
  );
  console.log("page ready state:", JSON.stringify(readyState));

  const SIZES = [
    ["6.9", 1320, 2868],
    ["6.5", 1284, 2778],
    ["6.3", 1206, 2622],
    ["6.1", 1125, 2436],
  ];

  const manifest = [];
  for (let idx = 0; idx < SIZES.length; idx++) {
    const [label, w, h] = SIZES[idx];
    // Select the size, then run Export All.
    await evaluate(`(() => {
      const sel = document.querySelector("select");
      sel.value = "${idx}";
      sel.dispatchEvent(new Event("change", { bubbles: true }));
      window.__breezyShots = {};
      window.__breezyShotsDone = false;
      return true;
    })()`);
    await sleep(600);
    await evaluate(`(() => {
      const btn = [...document.querySelectorAll("button")]
        .find((b) => b.textContent.includes("Export"));
      btn.click();
      return true;
    })()`);

    // Export All is sequential and slow (two renders per slide).
    let done = false;
    for (let i = 0; i < 240; i++) {
      done = await evaluate(`window.__breezyShotsDone === true`);
      if (done) break;
      await sleep(1000);
    }
    if (!done) throw new Error(`Export All timed out for ${label}"`);

    const shots = await evaluate(`JSON.stringify(window.__breezyShots || {})`);
    const parsed = JSON.parse(shots);
    const ids = Object.keys(parsed);
    if (ids.length === 0) throw new Error(`no slides exported for ${label}"`);

    for (const id of ids) {
      const b64 = parsed[id].split(",")[1];
      const file = join(
        outDir,
        `${String(ids.indexOf(id) + 1).padStart(2, "0")}-${id}-en-${w}x${h}.png`
      );
      writeFileSync(file, Buffer.from(b64, "base64"));
      manifest.push(file);
    }
    console.log(`${label}" (${w}x${h}): ${ids.length} slides`);
  }
  close();
  console.log(`TOTAL: ${manifest.length} files -> ${outDir}`);
} finally {
  chrome.kill("SIGKILL");
  // Chrome writes to its profile as it dies; retry so cleanup can't mask
  // the real result of the run.
  for (let i = 0; i < 10; i++) {
    try {
      rmSync(profile, { recursive: true, force: true });
      break;
    } catch {
      await sleep(500);
    }
  }
}
