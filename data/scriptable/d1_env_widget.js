//---------------------------------------------------
// Scriptable D1環境札 Widget v1
// XAUUSD 認識ツール（D1大局の「方向 × 拮抗度」2枚ラベル・small）
//
// 仕様: data/scriptable/SPEC_d1_env_widget_v1.md
// 姉妹: data/scriptable/atr_widget.js / ratio_widget.js（既存＝一切触らない。実装パターンのみ踏襲）
// 2026-07-15: DXY環境札（迷い検出札）行を追加
//   仕様: data/scriptable/SPEC_dxy_env_card_v1.md / 指示書: コー_impl_dxy_card_v2_vps.md
//
// データルート（確定値ルート）:
//   VPS EA → daily_aggregate.csv → generate_d1_env_json.py（ブン）
//   → GitHub Pages docs/d1_env.json → 本ウィジェットが fetch
//   ★D1札に Twelve Data は使わない。自前ADX計算へのフォールバックも禁止
//     （D1は日足境界ズレ・二重平滑誤差が大きい＝「確定情報＞計算予測」の対象）。
//     確定値が取れない時はキャッシュ表示 🔌、それも無ければ止まる。
//
// DXY環境札ルート（2026-07-15 v2: VPSルートへ切替・SPEC「ルート決定の経緯」参照）:
//   VPS EA（XAUUSD_DailyBatch_EA_v1）が iADX("USDIndex",H1,56) 確定バー値を
//   dxy_env.csv へ毎時出力 → generate_d1_env_json.py が d1_env.json の "dxy"
//   ブロックにマージ → 本ウィジェットは既にfetch済みの d1_env.json を整形表示するだけ。
//   ★Twelve fetch / JS内Wilder計算 / dxy_env_cache.json / APIキーは全廃
//     （TwelveにDXY指数が存在しない・Yahoo代替はラベル一致率33%で不合格）。
//   深さラベル判定は generator 側で一元化＝widget内で再判定しない。
//   dxyキー無し → 「DXY ─ 取得待ち」/ dxy.date が2営業日以上古い → 行に ⚠。
//   ★深さ閾値 2/5/10 は D1環境札の 5/10/16 とは別の物差し（混同禁止・SPEC §2）
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

  // 表示更新ヒント: 60分（d1_env.json は動脈が毎時publish＝これ以上の頻度は不要）
  refresh_interval_min: 60,

  // ---- DXY環境札（迷い検出札）----
  // SPEC: data/scriptable/SPEC_dxy_env_card_v1.md（VPSルート確定版）
  // データは d1_env.json の "dxy" ブロック（深さ判定は generator 一元化）
  // → widget側の設定は鮮度閾値のみ
  dxy: {
    stale_business_days: 2,   // dxy.date がこれ以上（営業日）古い → 行に ⚠
  },
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

// ---------------- DXY環境札（迷い検出札）----------------
// SPEC: data/scriptable/SPEC_dxy_env_card_v1.md / 指示書: コー_impl_dxy_card_v2_vps.md
// 本質は方向札ではなく「迷い検出札」: |DI+−DI−| の深さ4段階（拮抗/揺らぎ/優勢/一方通行）。
// ★ラベル層。点数化・順風/向かい風の自動判定はしない（SPEC §8 見送り事項）。
// v2: データは既にfetch済みの d1_env.json の "dxy" ブロック。
//     depth_label は JSON の値をそのまま使う（判定ロジックは generator 一元化）。

// dxy.date（"YYYY-MM-DD"）が今日から threshold 営業日以上古い → true（行に ⚠）
// 営業日カウント: date の翌日〜今日のうち月〜金の日数。
// 例) 金曜データを月曜に見る = 1営業日 → セーフ / 火曜まで更新無し = 2営業日 → ⚠
function isDxyStaleBusinessDays(dateStr, threshold) {
  const p = parseUpdated(dateStr);
  if (!p) return true;   // 解釈不能は警告側に倒す（isStale と同思想）
  const now = new Date();
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  let count = 0;
  const cur = new Date(p.y, p.m - 1, p.d);
  cur.setDate(cur.getDate() + 1);
  // 上限60日ガード（日付異常でも回り続けない。60日超過は count が threshold を超えて確定済み）
  for (let i = 0; i < 60 && cur.getTime() <= today.getTime(); i++) {
    const wd = cur.getDay();
    if (wd !== 0 && wd !== 6) count++;
    cur.setDate(cur.getDate() + 1);
  }
  return count >= threshold;
}

// DXY札: d1_env.json の "dxy" ブロックを表示用に整形するだけ（fetch も計算もしない）。
// dxy キー無し / 必須フィールド欠け → null（「DXY ─ 取得待ち」表示）
function getDxy(env) {
  if (!env || typeof env !== "object") return null;
  const d = env.dxy;
  if (!d || typeof d !== "object") return null;
  if (typeof d.di_spread !== "number" || !isFinite(d.di_spread)) return null;
  if (typeof d.depth_label !== "string") return null;
  return {
    spread: d.di_spread,                 // 符号付き小数1桁（+ = USD_UP・generator丸め済み）
    depth_label: d.depth_label,          // generator 判定値をそのまま（再判定しない）
    range5d: (d.spread_range_5d && typeof d.spread_range_5d === "object")
      ? d.spread_range_5d : null,
    date: d.date,
    stale: isDxyStaleBusinessDays(d.date, CONFIG.dxy.stale_business_days),
  };
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

// ---- DXY行専用色（既存D1行のパレットには一切触れない）----
// ★方向色はDI基準のみ（DI+優勢=青 / DI-優勢=赤 ＝ D1札の BULL/BEAR と同じ規則）。
//   良し悪しの色付け禁止（USD_UP優勢×BUYが最強セルという逆説が根拠・SPEC §5）
const COLOR_DXY_AMBER   = new Color("#ffcc00");   // 揺らぎ=警戒（atr_widget COLOR_WARN と同hex）
const COLOR_DXY_UP_DEEP = new Color("#007aff");   // 一方通行⬆＝方向色濃（#0a84ff の深色系統）
const COLOR_DXY_DN_DEEP = new Color("#ff3b30");   // 一方通行⬇＝方向色濃（#ff453a の深色系統）
const COLOR_HAIRLINE    = new Color("#3a3a3c");   // ヘアライン区切り（iOS separator dark）

// DXY行テキスト（SPEC §5 UI表・指示書§6）
function dxyRowText(d) {
  if (d.depth_label === "拮抗") return "DXY ─ 拮抗";   // 方向・数値なし＝「DXY読まない」
  const num = fmtSigned1(d.spread);
  if (d.depth_label === "揺らぎ") return `DXY 〰 迷い ${num}`;
  const arrow = d.spread > 0 ? "⬆" : "⬇";
  // 5dレンジ表示は優勢以上のみ（モック準拠: 丸め整数 min~max）
  const r = d.range5d;
  const rangeStr = (r && typeof r === "object" && isFinite(r.min) && isFinite(r.max))
    ? ` (5d ${Math.round(r.min)}~${Math.round(r.max)})`
    : "";
  if (d.depth_label === "優勢") return `DXY ${arrow} 優勢 ${num}${rangeStr}`;
  if (d.depth_label === "一方通行") return `DXY ${arrow}${arrow} 一方通行※ ${num}${rangeStr}`;
  return `DXY ${num}`;   // 想定外ラベル（キャッシュ破損等）は事実の数値のみ
}

function dxyRowColor(d) {
  if (d.depth_label === "揺らぎ") return COLOR_DXY_AMBER;
  if (d.depth_label === "優勢") return d.spread > 0 ? COLOR_BULL : COLOR_BEAR;
  if (d.depth_label === "一方通行") return d.spread > 0 ? COLOR_DXY_UP_DEEP : COLOR_DXY_DN_DEEP;
  return COLOR_RANGE;   // 拮抗・想定外はグレー
}

// ヘアライン区切り + DXY行を widget 末尾に追加（既存D1行のレイアウトは変更しない）
// d = getDxy() の戻り値（整形済み or null）
function addDxySection(widget, d) {
  widget.addSpacer(5);
  const sep = widget.addStack();
  sep.size = new Size(0, 1);          // 高さ1pt・幅は内側spacerで全幅に伸ばす
  sep.backgroundColor = COLOR_HAIRLINE;
  sep.addSpacer();
  widget.addSpacer(5);

  const row = widget.addStack();
  row.layoutHorizontally();
  row.centerAlignContent();

  if (!d) {
    // d1_env.json に dxy キー無し（VPS側 dxy_env.csv 未着 等）→ グレーで取得待ち
    const waitText = row.addText("DXY ─ 取得待ち");
    waitText.font = Font.systemFont(11);
    waitText.textColor = COLOR_RANGE;
    waitText.lineLimit = 1;
    row.addSpacer();
    return;
  }

  const mainText = row.addText(dxyRowText(d));
  // 一方通行のみ semibold（「方向色濃」の視覚強調。※印が「過信しない」を併記）
  mainText.font = (d.depth_label === "一方通行")
    ? Font.semiboldSystemFont(11)
    : Font.systemFont(11);
  mainText.textColor = dxyRowColor(d);
  mainText.lineLimit = 1;
  mainText.minimumScaleFactor = 0.6;   // small幅で "(5d ...)" まで出す保険

  if (d.stale) {
    row.addSpacer(3);
    // dxy.date が2営業日以上古い＝DXYレグ停滞の鮮度警告（D1札の⚠と同じ視覚言語）
    const note = row.addText("⚠");
    note.font = Font.systemFont(9);
    note.textColor = COLOR_DIM;
    note.lineLimit = 1;
  }
  row.addSpacer();
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

function buildWidget(env, flags, dxy) {
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

  // ----- 行5: DXY環境札（迷い検出札・ヘアライン区切りの下）-----
  addDxySection(widget, dxy);

  widget.addSpacer();   // 残余は下に逃がして上詰めレイアウト

  return widget;
}

// fetch失敗かつキャッシュ無し: 確定値ルートが完全に取れない → 止まる（外部APIには落ちない）
// ※DXY行の枠はここでも出す（v2: DXYも d1_env.json 相乗りなので、この場合は「取得待ち」表示）
function buildErrorWidget(message, dxy) {
  const widget = new ListWidget();
  widget.backgroundColor = COLOR_BG;
  widget.setPadding(10, 12, 10, 12);

  addHeader(widget, "--", { offline: true, stale: false });

  widget.addSpacer();

  const errText = widget.addText(message);
  errText.font = Font.systemFont(11);
  errText.textColor = COLOR_DIM;

  widget.addSpacer();

  addDxySection(widget, dxy);

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

  // DXY札: fetch済み env（or キャッシュ）の dxy ブロックを整形（追加fetchなし）
  const dxy = getDxy(env);

  let widget;
  if (env) {
    widget = buildWidget(env, { offline: offline, stale: isStale(env.updated) }, dxy);
  } else {
    widget = buildErrorWidget("取得失敗\nキャッシュなし", dxy);
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
