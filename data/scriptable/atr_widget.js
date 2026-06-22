//---------------------------------------------------
// Scriptable ATR Widget v1
// XAUUSD 認識ツール（価格非依存・H1/H4 ATR + 週次トレード回数）
//
// 仕様: data/scriptable/SPEC_atr_widget_v1.md
// 実装指示: data/scriptable/コー_impl_spec.md
//---------------------------------------------------

const CONFIG = {
  // Twelve Data API
  api_key: "<TWELVE_DATA_API_KEY>",
  symbol: "XAU/USD",

  // ATR 加熱境界（HIGH のみ、1本ライン）
  // ※これらは設定ダイアログでも編集可能。編集後は config.json が優先。
  h1_atr16_high:  13.3,
  h1_atr32_high:  13.3,
  h4_atr8_high:   30.0,

  // 今週トレード回数（コード固定、ダイアログ編集対象外）
  weekly_ideal:   3,     // 余裕→注意の境界
  weekly_limit:   5,     // 注意→超過の境界
  reset_weekday:  1,     // 0=日, 1=月... 月曜00:00 にリセット

  // 表示
  refresh_interval_min: 15,
};

const FM = FileManager.iCloud();
const STATE_PATH  = FM.joinPath(FM.documentsDirectory(), "atr_widget_state.json");
const CONFIG_PATH = FM.joinPath(FM.documentsDirectory(), "atr_widget_config.json");
const CACHE_PATH  = FM.joinPath(FM.documentsDirectory(), "atr_widget_cache.json");

// ---------------- ファイル I/O ----------------
// downloadFileFromiCloud は Promise を返すので await 必須。
// await 漏れだと「キャッシュは存在するが iCloud 同期未完で読めず N/A」になる。
async function readJsonSafe(path, fallback) {
  try {
    if (!FM.fileExists(path)) return fallback;
    if (!FM.isFileDownloaded(path)) await FM.downloadFileFromiCloud(path);
    const text = FM.readString(path);
    return JSON.parse(text);
  } catch (e) {
    console.warn(`readJsonSafe failed for ${path}: ${e}`);
    return fallback;
  }
}

function writeJson(path, obj) {
  FM.writeString(path, JSON.stringify(obj, null, 2));
}

async function loadState() {
  return await readJsonSafe(STATE_PATH, {
    week_count: 0,
    last_reset: null,
    prev_status: { h1_atr16: null, h1_atr32: null, h4_atr8: null },
  });
}
function saveState(state) { writeJson(STATE_PATH, state); }

async function loadConfig() {
  const fileConfig = await readJsonSafe(CONFIG_PATH, null);
  if (!fileConfig) return { ...CONFIG };
  // ATR 3値のみファイル優先、他は CONFIG（コード側）を使う
  const merged = { ...CONFIG };
  for (const k of ["h1_atr16_high", "h1_atr32_high", "h4_atr8_high"]) {
    if (typeof fileConfig[k] === "number" && fileConfig[k] > 0) {
      merged[k] = fileConfig[k];
    }
  }
  return merged;
}
function saveConfig(config) {
  writeJson(CONFIG_PATH, {
    h1_atr16_high: config.h1_atr16_high,
    h1_atr32_high: config.h1_atr32_high,
    h4_atr8_high:  config.h4_atr8_high,
  });
}

async function loadCache() { return await readJsonSafe(CACHE_PATH, null); }
function saveCache(c){ writeJson(CACHE_PATH, c); }

// ---------------- リセット境界判定 ----------------
// reset_weekday から、直近の該当曜日の日付（YYYY-MM-DD）を返す
function getLastResetIso() {
  const now = new Date();
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  let diff = today.getDay() - CONFIG.reset_weekday;
  if (diff < 0) diff += 7;
  const target = new Date(today);
  target.setDate(today.getDate() - diff);
  // ISO date のみ抜き出し（時刻無し）
  const y = target.getFullYear();
  const m = String(target.getMonth() + 1).padStart(2, "0");
  const d = String(target.getDate()).padStart(2, "0");
  return `${y}-${m}-${d}`;
}

// state を必要に応じてリセットして返す
function checkWeeklyReset(state) {
  const lastResetIso = getLastResetIso();
  if (!state.last_reset || state.last_reset < lastResetIso) {
    state.week_count = 0;
    state.last_reset = lastResetIso;
    saveState(state);
  }
  return state;
}

// ---------------- API & 計算 ----------------
async function fetchOHLC(interval, outputsize) {
  const params = [
    `symbol=${encodeURIComponent(CONFIG.symbol)}`,
    `interval=${encodeURIComponent(interval)}`,
    `outputsize=${outputsize}`,
    `apikey=${encodeURIComponent(CONFIG.api_key)}`,
    `format=JSON`,
  ].join("&");

  const url = `https://api.twelvedata.com/time_series?${params}`;
  const req = new Request(url);
  req.timeoutInterval = 25;       // 25秒（モバイル回線で 10秒は短く N/A の主因だった）
  const json = await req.loadJSON();

  if (json.status === "error") {
    throw new Error(`Twelve Data: ${json.message || "unknown"}`);
  }
  if (!Array.isArray(json.values)) {
    throw new Error("Twelve Data: values missing");
  }

  // values は新しい順 → 古い順にして、土日バー除外 → 数値変換
  // 週またぎ時に Twelve Data が休場中の TR=0 バーを返して ATR が圧縮される問題への対応
  const candles = json.values.slice().reverse()
    .filter(v => {
      const day = new Date(v.datetime).getUTCDay();
      return day !== 0 && day !== 6;  // 0=日, 6=土 を除外（UTC基準）
    })
    .map(v => ({
      datetime: v.datetime,
      high:  parseFloat(v.high),
      low:   parseFloat(v.low),
      close: parseFloat(v.close),
    }));
  return candles;
}

function calculateWilderATR(candles, period) {
  // candles: 古い順、{high, low, close}
  if (!Array.isArray(candles) || candles.length < period + 1) return null;

  // True Range 配列（i=1 から）
  const trArr = [];
  for (let i = 1; i < candles.length; i++) {
    const h = candles[i].high;
    const l = candles[i].low;
    const pc = candles[i - 1].close;
    const tr = Math.max(h - l, Math.abs(h - pc), Math.abs(l - pc));
    trArr.push(tr);
  }
  if (trArr.length < period) return null;

  // 初期 ATR = 最初の period本の TR の単純平均
  let atr = 0;
  for (let i = 0; i < period; i++) atr += trArr[i];
  atr /= period;

  // Wilder smoothing
  for (let i = period; i < trArr.length; i++) {
    atr = (atr * (period - 1) + trArr[i]) / period;
  }

  return atr;
}

// ---------------- 設定ダイアログ ----------------
async function showSettingsDialog(currentConfig) {
  const alert = new Alert();
  alert.title = "ATR 閾値設定";
  alert.message = "加熱境界（HIGH）を編集";
  alert.addTextField("H1 ATR(16) HIGH", String(currentConfig.h1_atr16_high));
  alert.addTextField("H1 ATR(32) HIGH", String(currentConfig.h1_atr32_high));
  alert.addTextField("H4 ATR(8) HIGH",  String(currentConfig.h4_atr8_high));
  alert.addAction("保存");
  alert.addCancelAction("キャンセル");

  // present() は action index を返す。cancel は -1。
  const choice = await alert.present();
  if (choice === -1) return null;

  const v1 = parseFloat(alert.textFieldValue(0));
  const v2 = parseFloat(alert.textFieldValue(1));
  const v3 = parseFloat(alert.textFieldValue(2));

  const ok = [v1, v2, v3].every(v => Number.isFinite(v) && v > 0);
  if (!ok) {
    const err = new Alert();
    err.title = "無効な値";
    err.message = "正の数値を入力してください";
    err.addAction("OK");
    await err.present();
    return null;
  }

  return { h1_atr16_high: v1, h1_atr32_high: v2, h4_atr8_high: v3 };
}

// ---------------- ウィジェット構築 ----------------
const COLOR_BG     = new Color("#1c1c1e");
const COLOR_FG     = Color.white();
const COLOR_DIM    = Color.gray();
const COLOR_OK     = new Color("#34c759");   // green
const COLOR_WARN   = new Color("#ffcc00");   // yellow
const COLOR_DANGER = new Color("#ff453a");   // red
const COLOR_LINK   = new Color("#0a84ff");   // blue

const URL_INC      = "scriptable:///run/atr_widget?action=increment";
const URL_RESET    = "scriptable:///run/atr_widget?action=reset";
const URL_SETTINGS = "scriptable:///run/atr_widget?action=settings";

// 内部判定用：value と threshold から "red"/"green"/null を返す（下抜け通知のエッジ検出用）
function statusOf(value, threshold) {
  if (value == null) return null;
  return value >= threshold ? "red" : "green";
}

function statusEmojiAtr(value, threshold) {
  if (value == null) return "⚪";
  return value >= threshold ? "🔴" : "🟢";
}
function statusEmojiCount(count, ideal, limit) {
  if (count >= limit) return "🔴";
  if (count >= ideal) return "🟡";
  return "🟢";
}

// ---------------- 動的ステータスメッセージ ----------------
const STATUS_MESSAGES = {
  all_green: [
    "🍜 冷やし中華始めました",
    "🟢 営業中〜",
    "🍻 ご新規いらっしゃい",
    "☕ お席空いてます",
    "🍣 寿司、握ります",
  ],
  mixed: [
    "♨️ お湯沸いてます",
    "🥢 仕込み中",
    "⏳ もうしばらくお待ちを",
    "🍳 準備中",
  ],
  all_red: [
    "🔥 仕込み真っ最中",
    "🚫 ただいま準備中",
    "🔴 まだ早いっす",
    "🍲 出汁とり中",
  ],
  count_over: [
    "🏪 本日は店じまい",
    "⛔ 営業終了、お疲れさん",
    "🍻 一杯やりますか",
  ],
};

function getStatusKey(data) {
  if (data.state.week_count >= CONFIG.weekly_limit) return "count_over";
  const cfg = data.config;
  const red = [
    data.h1_atr16 != null && data.h1_atr16 >= cfg.h1_atr16_high,
    data.h1_atr32 != null && data.h1_atr32 >= cfg.h1_atr32_high,
    data.h4_atr8  != null && data.h4_atr8  >= cfg.h4_atr8_high,
  ].filter(x => x).length;
  if (red === 0) return "all_green";
  if (red === 3) return "all_red";
  return "mixed";
}

function pickStatusMessage(key) {
  const list = STATUS_MESSAGES[key] || ["XAUUSD"];
  return list[Math.floor(Math.random() * list.length)];
}

function buildWidget(data) {
  const widget = new ListWidget();
  widget.backgroundColor = COLOR_BG;
  widget.setPadding(10, 12, 10, 12);

  // ----- ヘッダー（動的ステータスメッセージ） -----
  const header = widget.addStack();
  header.layoutHorizontally();
  const title = header.addText(pickStatusMessage(getStatusKey(data)));
  title.font = Font.semiboldSystemFont(11);
  title.textColor = COLOR_FG;
  header.addSpacer();
  const now = new Date();
  const hh = String(now.getHours()).padStart(2, "0");
  const mm = String(now.getMinutes()).padStart(2, "0");
  const timeText = header.addText(`${hh}:${mm}`);
  timeText.font = Font.systemFont(10);
  timeText.textColor = COLOR_DIM;

  widget.addSpacer(4);

  // ----- ATR 3行 -----
  addAtrRow(widget, "H1 ATR(16)", data.h1_atr16, data.config.h1_atr16_high);
  addAtrRow(widget, "H1 ATR(32)", data.h1_atr32, data.config.h1_atr32_high);
  addAtrRow(widget, "H4 ATR(8)",  data.h4_atr8,  data.config.h4_atr8_high);

  widget.addSpacer(4);

  // ----- トレード回数 -----
  addCountRow(widget, data.state.week_count, CONFIG.weekly_ideal, CONFIG.weekly_limit);

  return widget;
}

function addAtrRow(widget, label, value, threshold) {
  const row = widget.addStack();
  row.layoutHorizontally();
  row.centerAlignContent();

  const labelText = row.addText(label);
  labelText.font = Font.systemFont(11);
  labelText.textColor = COLOR_FG;

  row.addSpacer();

  const valueStr = (value == null) ? "N/A" : value.toFixed(2);
  const valueText = row.addText(valueStr);
  valueText.font = new Font("Menlo", 11);
  valueText.textColor = COLOR_FG;

  row.addSpacer(8);

  const threshText = row.addText(`>${threshold.toFixed(1)}`);
  threshText.font = Font.systemFont(10);
  threshText.textColor = COLOR_LINK;
  threshText.url = URL_SETTINGS;

  row.addSpacer(4);

  const statusText = row.addText(statusEmojiAtr(value, threshold));
  statusText.font = Font.systemFont(11);
}

function addCountRow(widget, count, ideal, limit) {
  const row = widget.addStack();
  row.layoutHorizontally();
  row.centerAlignContent();

  const labelText = row.addText("今週");
  labelText.font = Font.systemFont(11);
  labelText.textColor = COLOR_FG;

  row.addSpacer(6);

  const plusText = row.addText("[+1]");
  plusText.font = Font.semiboldSystemFont(11);
  plusText.textColor = COLOR_LINK;
  plusText.url = URL_INC;

  row.addSpacer();

  const countText = row.addText(`${count} / ${limit}`);
  countText.font = new Font("Menlo", 11);
  countText.textColor = COLOR_FG;

  row.addSpacer(4);

  const statusText = row.addText(statusEmojiCount(count, ideal, limit));
  statusText.font = Font.systemFont(11);

  row.addSpacer(8);

  const resetText = row.addText("⟲");
  resetText.font = Font.systemFont(9);
  resetText.textColor = COLOR_DIM;
  resetText.url = URL_RESET;
}

// ---------------- 下抜け通知 ----------------
// 🔴加熱 → 🟢落ち着き へ切り替わったラインを 1通知にまとめて配信する。
// ウィジェット文脈から Notification が飛ぶかは実機確認事項
// （飛ばない場合はショートカットのバックグラウンド実行に切り替える保険を取る）。
async function fireSettleNotification(crossed) {
  const n = new Notification();
  const names = crossed.map(c => c.label).join(", ");
  n.title = `💧 落ち着き下抜け: ${names}`;
  n.body = crossed
    .map(c => `${c.label}  ${c.value.toFixed(2)} 🟢  (閾値 ${c.threshold.toFixed(1)})`)
    .join("\n");
  n.sound = "default";
  try {
    await n.schedule();
  } catch (e) {
    console.warn(`Notification schedule failed: ${e}`);
  }
}

// ---------------- メイン ----------------
async function main() {
  // 1. State load + 週次リセット判定
  let state = await loadState();
  state = checkWeeklyReset(state);

  // 2. Config load
  let config = await loadConfig();

  // 3. アクション処理
  const action = (args.queryParameters && args.queryParameters.action) || null;

  if (action === "increment") {
    state.week_count += 1;
    saveState(state);
  } else if (action === "reset") {
    state.week_count = 0;
    state.last_reset = getLastResetIso();
    saveState(state);
  } else if (action === "settings") {
    const updated = await showSettingsDialog(config);
    if (updated) {
      config = { ...config, ...updated };
      saveConfig(config);
    }
  }

  // 4. データ取得（API、失敗時はキャッシュ）
  let data;
  try {
    // outputsize: 土日フィルタ後も Wilder ATR smoothing が安定する本数を確保
    // H1: 200本 → 土日除外で約 150本（H1 ATR32 の smoothing 十分）
    // H4: 80本  → 土日除外で約 60本（H4 ATR8 の smoothing 十分）
    // Promise.all で並列化：直列だと合計 50秒待つことになるが並列なら最大 25秒で済む
    const [h1, h4] = await Promise.all([
      fetchOHLC("1h", 200),
      fetchOHLC("4h", 80),
    ]);
    data = {
      h1_atr16: calculateWilderATR(h1, 16),
      h1_atr32: calculateWilderATR(h1, 32),
      h4_atr8:  calculateWilderATR(h4, 8),
    };
    saveCache({
      h1_atr16: data.h1_atr16,
      h1_atr32: data.h1_atr32,
      h4_atr8:  data.h4_atr8,
      saved_at: new Date().toISOString(),
    });
  } catch (e) {
    console.warn(`API failed: ${e}`);
    const cached = await loadCache();
    if (cached) {
      data = {
        h1_atr16: cached.h1_atr16,
        h1_atr32: cached.h1_atr32,
        h4_atr8:  cached.h4_atr8,
        error: "API Err（キャッシュ表示）",
      };
    } else {
      data = { error: "Loading..." };
    }
  }
  data.state = state;
  data.config = config;

  // 4.5 下抜け通知（🔴加熱 → 🟢落ち着き のエッジを各ライン独立で検出）
  //  - 自動更新／背景タップ時のみ判定（手動の +1・リセット・設定変更では鳴らさない）
  //  - settings で閾値を変えた直後の見かけ上の遷移で誤発火しないよう action を限定
  //  - prev_status は有効値のときだけ更新 = API一時失敗を跨いでも遷移を取りこぼさない
  if (!state.prev_status) {
    state.prev_status = { h1_atr16: null, h1_atr32: null, h4_atr8: null };
  }
  const notifyLines = [
    { key: "h1_atr16", label: "H1(16)", value: data.h1_atr16, threshold: config.h1_atr16_high },
    { key: "h1_atr32", label: "H1(32)", value: data.h1_atr32, threshold: config.h1_atr32_high },
    { key: "h4_atr8",  label: "H4(8)",  value: data.h4_atr8,  threshold: config.h4_atr8_high },
  ];
  const doNotify = (action === null || action === undefined);
  const crossedDown = [];
  for (const ln of notifyLines) {
    const now = statusOf(ln.value, ln.threshold);
    const prev = state.prev_status[ln.key] ?? null;
    if (doNotify && prev === "red" && now === "green") {
      crossedDown.push(ln);
    }
    if (now !== null) state.prev_status[ln.key] = now;
  }
  saveState(state);
  if (crossedDown.length > 0) {
    await fireSettleNotification(crossedDown);
  }

  // 5. ウィジェット構築 & 登録
  const widget = buildWidget(data);

  if (config.runInApp) {
    // Scriptable アプリ内で実行されたとき（デバッグ用）
    await widget.presentMedium();
  } else {
    Script.setWidget(widget);
  }

  Script.complete();
}

await main();
