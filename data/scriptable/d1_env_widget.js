//---------------------------------------------------
// Scriptable D1環境札 Widget v1
// XAUUSD 認識ツール（D1大局の「方向 × 拮抗度」2枚ラベル・small）
//
// 仕様: data/scriptable/SPEC_d1_env_widget_v1.md
// 姉妹: data/scriptable/atr_widget.js / ratio_widget.js（既存＝一切触らない。実装パターンのみ踏襲）
//
// データルート（確定値ルート）:
//   VPS EA → daily_aggregate.csv → generate_d1_env_json.py（ブン）
//   → GitHub Pages docs/d1_env.json → 本ウィジェットが fetch
//   ★Twelve Data は使わない。自前ADX計算へのフォールバックも禁止
//     （D1は日足境界ズレ・二重平滑誤差が大きい＝「確定情報＞計算予測」の対象）。
//     確定値が取れない時はキャッシュ表示 🔌、それも無ければ止まる。
//
// ★重大原則（SPEC §4 禁止事項）:
//   - 点数化・スコア合成なし（ラベル層厳守。ADXスコアは週次ヒートマップの領分）
//   - 連続グラデーションなし（段階ラベルのみ＝あろさんの認識粒度は段階）
//   - 売買方向の示唆なし（「売り環境」等の文言禁止。DI事実の表示まで）
//   - 色はDI方向のみ（BEAR=赤/BULL=青/RANGE=グレー）。ATR行・拮抗度行に色を焼かない
//---------------------------------------------------

const CONFIG = {
  // GitHub Pages 上の確定値JSON（run_daily_calendar.sh が publish・ブン担当）
  json_url: "https://arokamiya98-svg.github.io/adxscore-heatmap/d1_env.json",

  // 鮮度ガード: updated が今日から stale_days 日を超えて古い → ヘッダ ⚠️
  //   SPEC §4 は「3営業日超過」。実装は暦日 >3 で近似（金曜データを月曜に見る=3日でセーフ、
  //   火曜まで更新無し=4日で⚠️）。週末を跨ぐ動脈停止の検知には十分。
  stale_days: 3,

  // 表示更新ヒント（VPS毎時push・D1確定値は1日1回変化 → 30分で十分）
  refresh_interval_min: 30,
};

// atr_widget.js（2026-06-25 根治後）と同じ FileManager パターン:
// ウィジェット背景更新時の iCloud "Failed writing to disk" 回避のため local()。
// キャッシュは専用ファイルに分離（既存 atr/ratio の state/cache とは混ぜない）。
const FM = FileManager.local();
const CACHE_PATH = FM.joinPath(FM.documentsDirectory(), "d1_env_widget_cache.json");

// ---------------- ファイル I/O（atr_widget.js から踏襲）----------------
// downloadFileFromiCloud は Promise を返すので await 必須
// （local() では isFileDownloaded が常に true で download 分岐は不発＝無害）。
async function readJsonSafe(path, fallback) {
  try {
    if (!FM.fileExists(path)) return fallback;
    if (!FM.isFileDownloaded(path)) await FM.downloadFileFromiCloud(path);
    const text = FM.readString(path);
    const parsed = JSON.parse(text);
    // JSON.parse("null") は例外を投げず null を返す。壊れた非オブジェクトは fallback に倒す。
    if (parsed === null || typeof parsed !== "object") return fallback;
    return parsed;
  } catch (e) {
    console.warn(`readJsonSafe failed for ${path}: ${e}`);
    return fallback;
  }
}

function writeJson(path, obj) {
  // 書き込み失敗（ロック中の保護・容量・I/O）でもウィジェットを落とさず次回更新で追いつく。
  try {
    FM.writeString(path, JSON.stringify(obj, null, 2));
  } catch (e) {
    console.warn(`writeJson failed for ${path}: ${e}`);
  }
}

async function loadCache() { return await readJsonSafe(CACHE_PATH, null); }
function saveCache(c) { writeJson(CACHE_PATH, c); }

// ---------------- データ取得 ----------------
// docs/d1_env.json（SPEC §3 スキーマ）を fetch。壊れた応答は throw してキャッシュ側に倒す。
async function fetchEnvJson() {
  const req = new Request(CONFIG.json_url);
  req.timeoutInterval = 25;   // 既存widget同様、モバイル回線考慮で25秒
  const json = await req.loadJSON();

  if (json === null || typeof json !== "object") {
    throw new Error("d1_env.json: not an object");
  }
  // 表示に必須のフィールドだけ検証（spread_range_5d は欠けても行3を N/A にして生かす）
  const required = ["updated", "adx22", "adx_state", "di_spread",
                    "spread_label", "atr_cross_dir", "atr_cross_days"];
  for (const k of required) {
    if (!(k in json)) throw new Error(`d1_env.json: missing field "${k}"`);
  }
  return json;
}

// ---------------- 日付・鮮度 ----------------
function parseUpdated(s) {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(s || ""));
  if (!m) return null;
  return { y: +m[1], m: +m[2], d: +m[3] };
}

// ヘッダ表示用 "M/D"（例: "2026-07-09" → "7/9"）
function fmtHeaderDate(updatedStr) {
  const p = parseUpdated(updatedStr);
  return p ? `${p.m}/${p.d}` : "--";
}

// updated が今日から stale_days 日超過 → true（解釈不能も警告側に倒す）
function isStale(updatedStr) {
  const p = parseUpdated(updatedStr);
  if (!p) return true;
  const upd = new Date(p.y, p.m - 1, p.d);
  const now = new Date();
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const diffDays = Math.round((today.getTime() - upd.getTime()) / 86400000);
  return diffDays > CONFIG.stale_days;
}

// ---------------- 表示整形 ----------------
// 拮抗度ラベル → 絵文字（ラベル文字列は JSON の spread_label をそのまま使う。js側は絵文字マップのみ）
const SPREAD_EMOJI = {
  "拮抗":     "🌫",
  "揺らぎ":   "〰",
  "優勢":     "➡",
  "一方通行": "🔥",
};

// DI現値: 符号付き小数1桁（"-9.5" / "+4.2"）
function fmtSigned1(v) {
  if (typeof v !== "number" || !isFinite(v)) return "N/A";
  return (v > 0 ? "+" : "") + v.toFixed(1);
}

// 5日レンジ: 符号付き整数（モック準拠 "-2 〜 -10"。-10.4 → -10）
function fmtSignedInt(v) {
  if (typeof v !== "number" || !isFinite(v)) return "?";
  const r = Math.round(v);
  return (r > 0 ? "+" : "") + String(r);
}

// 行4テキスト: ラベルのみ・ratio数値は出さない（幅の実値は ratio_widget の領分）
function atrPhaseText(env) {
  const days = env.atr_cross_days;
  const daysStr = (typeof days === "number" && isFinite(days))
    ? (days >= 99 ? "99+" : String(Math.round(days)))   // 99 = 「跨ぎ無し」固定値 → "99+日目"
    : "?";
  if (env.atr_cross_dir === "UP")   return `ATR ↑拡張 ${daysStr}日目`;
  if (env.atr_cross_dir === "DOWN") return `ATR ↓収束 ${daysStr}日目`;
  return "ATR —";   // 想定外値（生成側バグ）は方向を出さない
}

// ---------------- 色（既存widget群と同一パレット）----------------
const COLOR_BG    = new Color("#1c1c1e");
const COLOR_FG    = Color.white();
const COLOR_DIM   = Color.gray();
// ★色を持つのは DI方向（行1）のみ。行2〜4はニュートラル（白/グレー）で固定。
const COLOR_BEAR  = new Color("#ff453a");   // 赤（atr_widget COLOR_DANGER と同hex）
const COLOR_BULL  = new Color("#0a84ff");   // 青（atr_widget COLOR_LINK と同hex）
const COLOR_RANGE = new Color("#98989d");   // グレー（RANGE=方向なし）

function stateColor(state) {
  if (state === "BEAR") return COLOR_BEAR;
  if (state === "BULL") return COLOR_BULL;
  return COLOR_RANGE;   // "RANGE" と想定外値はグレー
}

// ---------------- ウィジェット構築 ----------------
// ヘッダ共通部: 「D1 環境」+（🔌/⚠️）+ 日付
function addHeader(widget, dateStr, flags) {
  const header = widget.addStack();
  header.layoutHorizontally();
  header.centerAlignContent();

  const title = header.addText("D1 環境");
  title.font = Font.semiboldSystemFont(11);
  title.textColor = COLOR_FG;

  header.addSpacer();

  // 🔌 = fetch失敗（キャッシュ表示中） / ⚠️ = 鮮度切れ（動脈停止の検知）。併発時は両方出す。
  const icons = `${flags.offline ? "🔌" : ""}${flags.stale ? "⚠️" : ""}`;
  if (icons) {
    const iconText = header.addText(icons);
    iconText.font = Font.systemFont(10);
    header.addSpacer(3);
  }

  const dateText = header.addText(dateStr);
  dateText.font = Font.systemFont(10);
  dateText.textColor = COLOR_DIM;
}

function buildWidget(env, flags) {
  const widget = new ListWidget();
  widget.backgroundColor = COLOR_BG;
  widget.setPadding(10, 12, 10, 12);

  // ----- ヘッダ: 「D1 環境」 + updated（M/D）-----
  addHeader(widget, fmtHeaderDate(env.updated), flags);

  widget.addSpacer(8);

  // ----- 行1: 方向 × ADX実値（最大サイズ・色はここだけ）-----
  // adx_state は生成側で RANGE 変換済（ADX<20 で方向文字を出さない）。js は色マップのみ。
  const row1 = widget.addStack();
  row1.layoutHorizontally();
  row1.centerAlignContent();

  const stateText = row1.addText(String(env.adx_state));
  stateText.font = Font.boldSystemFont(18);
  stateText.textColor = stateColor(env.adx_state);
  stateText.lineLimit = 1;
  stateText.minimumScaleFactor = 0.8;   // "RANGE ADX 18" が small 幅で切れない保険

  row1.addSpacer();

  const adxLabel = row1.addText("ADX ");
  adxLabel.font = Font.systemFont(11);
  adxLabel.textColor = COLOR_DIM;

  const adxVal = (typeof env.adx22 === "number" && isFinite(env.adx22))
    ? String(Math.round(env.adx22)) : "N/A";
  const adxText = row1.addText(adxVal);
  adxText.font = new Font("Menlo", 16);
  adxText.textColor = COLOR_FG;

  widget.addSpacer(4);

  // ----- 行2: DI現値 + 拮抗度ラベル（ニュートラル色＝拮抗度は方向情報ではない）-----
  const row2 = widget.addStack();
  row2.layoutHorizontally();
  row2.centerAlignContent();

  const diLabel = row2.addText("DI ");
  diLabel.font = Font.systemFont(11);
  diLabel.textColor = COLOR_DIM;

  const diText = row2.addText(fmtSigned1(env.di_spread));
  diText.font = new Font("Menlo", 13);
  diText.textColor = COLOR_FG;

  row2.addSpacer();

  const emoji = SPREAD_EMOJI[env.spread_label] || "";
  const labelStr = emoji ? `${emoji} ${env.spread_label}` : String(env.spread_label || "N/A");
  const spreadText = row2.addText(labelStr);
  spreadText.font = Font.systemFont(12);
  spreadText.textColor = COLOR_FG;
  spreadText.lineLimit = 1;

  widget.addSpacer(3);

  // ----- 行3: 直近5日レンジ（小フォント・サブ色）: 「5日: {max} 〜 {min}」-----
  const r5 = env.spread_range_5d;
  const rangeStr = (r5 && typeof r5 === "object")
    ? `5日: ${fmtSignedInt(r5.max)} 〜 ${fmtSignedInt(r5.min)}`
    : "5日: N/A";
  const rangeText = widget.addText(rangeStr);
  rangeText.font = Font.systemFont(10);
  rangeText.textColor = COLOR_DIM;
  rangeText.lineLimit = 1;

  widget.addSpacer(4);

  // ----- 行4: ATRクロスフェーズ（ラベルのみ・色なし・ratio数値なし）-----
  const atrText = widget.addText(atrPhaseText(env));
  atrText.font = Font.systemFont(11);
  atrText.textColor = COLOR_FG;
  atrText.lineLimit = 1;

  widget.addSpacer();   // 残余は下に逃がして上詰めレイアウト

  return widget;
}

// fetch失敗かつキャッシュ無し: 確定値ルートが完全に取れない → 止まる（Twelve Data には落ちない）
function buildErrorWidget(message) {
  const widget = new ListWidget();
  widget.backgroundColor = COLOR_BG;
  widget.setPadding(10, 12, 10, 12);

  addHeader(widget, "--", { offline: true, stale: false });

  widget.addSpacer();

  const errText = widget.addText(message);
  errText.font = Font.systemFont(11);
  errText.textColor = COLOR_DIM;

  widget.addSpacer();

  return widget;
}

// ---------------- メイン ----------------
async function main() {
  let env = null;
  let offline = false;

  try {
    env = await fetchEnvJson();
    saveCache({ env: env, saved_at: new Date().toISOString() });
  } catch (e) {
    // fetch失敗 → キャッシュした前回JSONで描画（🔌）。自前計算フォールバックはしない。
    console.warn(`fetch failed: ${e}`);
    offline = true;
    const cached = await loadCache();
    if (cached && cached.env && typeof cached.env === "object") {
      env = cached.env;
    }
  }

  let widget;
  if (env) {
    widget = buildWidget(env, { offline: offline, stale: isStale(env.updated) });
  } else {
    widget = buildErrorWidget("取得失敗\nキャッシュなし");
  }

  widget.refreshAfterDate = new Date(Date.now() + CONFIG.refresh_interval_min * 60 * 1000);

  if (config.runsInWidget) {
    Script.setWidget(widget);
  } else {
    // Scriptable アプリ内で実行されたとき（デバッグ用・small想定）
    await widget.presentSmall();
  }

  Script.complete();
}

await main();
