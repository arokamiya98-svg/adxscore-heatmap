//---------------------------------------------------
// Scriptable D1環境札 Widget v1
// XAUUSD 認識ツール（D1大局の「方向 × 拮抗度」2枚ラベル・small）
//
// 仕様: data/scriptable/SPEC_d1_env_widget_v1.md
// 姉妹: data/scriptable/atr_widget.js / ratio_widget.js（既存＝一切触らない。実装パターンのみ踏襲）
// 2026-07-15: DXY環境札（迷い検出札）行を追加
//   仕様: data/scriptable/SPEC_dxy_env_card_v1.md / 指示書: コー_impl_dxy_card_v1.md
//
// データルート（確定値ルート）:
//   VPS EA → daily_aggregate.csv → generate_d1_env_json.py（ブン）
//   → GitHub Pages docs/d1_env.json → 本ウィジェットが fetch
//   ★D1札に Twelve Data は使わない。自前ADX計算へのフォールバックも禁止
//     （D1は日足境界ズレ・二重平滑誤差が大きい＝「確定情報＞計算予測」の対象）。
//     確定値が取れない時はキャッシュ表示 🔌、それも無ければ止まる。
//
// DXY環境札ルート（2026-07-15 追加・D1札とは独立）:
//   Twelve Data /time_series (DXY 1h×1500) → JS内 Wilder ADX(56)/DI± → 深さ4段階ラベル
//   失敗時は dxy_env_cache.json のキャッシュ表示（atr_widget と同パターン）。
//   D1行の表示ロジックには一切影響しない（公開レグ障害でもDXY札は生きる・SPEC §3）。
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

  // 表示更新ヒント: 60分（DXY札のTwelve Dataコール予算節約・指示書§7。
  //   D1確定値は1日1回変化なので 30→60分への引き上げは実害なし）
  refresh_interval_min: 60,

  // ---- DXY環境札（迷い検出札）----
  // SPEC: data/scriptable/SPEC_dxy_env_card_v1.md
  dxy: {
    api_key: "<TWELVE_DATA_API_KEY>",   // ★実キーは端末側であろさんが投入（リポジトリはPUBLIC＝置かない）
    symbol: "DXY",              // プラン都合で変える可能性あり→設定化
    interval: "1h",
    outputsize: 1500,           // ADX(56) Wilder収束用（終端値のみ使用・先頭側は捨て駒）
    adx_period: 56,
    thresholds: [2, 5, 10],     // 拮抗/揺らぎ/優勢/一方通行 の境界（|DI+−DI−|・D1札の閾値とは別物差し）
    cache_file: "dxy_env_cache.json",
    cache_stale_hours: 24,      // キャッシュ表示がこれを超えたら ⚠ を添える
  },
};

// atr_widget.js（2026-06-25 根治後）と同じ FileManager パターン:
// ウィジェット背景更新時の iCloud "Failed writing to disk" 回避のため local()。
// キャッシュは専用ファイルに分離（既存 atr/ratio の state/cache とは混ぜない）。
const FM = FileManager.local();
const CACHE_PATH = FM.joinPath(FM.documentsDirectory(), "d1_env_widget_cache.json");
// DXY札キャッシュも同流儀（atr_widget は 2026-06-25 に iCloud→local() へ根治済み → local に合わせる）
const DXY_CACHE_PATH = FM.joinPath(FM.documentsDirectory(), CONFIG.dxy.cache_file);

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

async function loadDxyCache() { return await readJsonSafe(DXY_CACHE_PATH, null); }
function saveDxyCache(c) { writeJson(DXY_CACHE_PATH, c); }

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
// SPEC: data/scriptable/SPEC_dxy_env_card_v1.md / 指示書: コー_impl_dxy_card_v1.md
// 本質は方向札ではなく「迷い検出札」: |DI+−DI−| の深さ4段階（拮抗/揺らぎ/優勢/一方通行）。
// ★ラベル層。点数化・順風/向かい風の自動判定はしない（SPEC §8 見送り事項）。

// Twelve Data の datetime（timezone=UTC 指定 → "YYYY-MM-DD HH:MM:SS"）を明示UTCでパース
function parseUtcMs(dt) {
  const s = String(dt);
  const iso = s.includes("T") ? s : s.replace(" ", "T") + "Z";
  const t = Date.parse(iso);
  return isNaN(t) ? null : t;
}

// DXY 1h×1500本を取得 → 古い順・土日除外・確定バーのみに整形（atr_widget fetchOHLC の流儀）
async function fetchDxySeries() {
  const c = CONFIG.dxy;
  // 実キー未投入（プレースホルダーのまま）→ 即 throw してキャッシュ/取得待ちパスへ
  // （無効キーで10秒の無駄なネットワーク待ちをしない）
  if (typeof c.api_key !== "string" || c.api_key.startsWith("<")) {
    throw new Error("DXY: api_key未設定（プレースホルダー）");
  }

  const params = [
    `symbol=${encodeURIComponent(c.symbol)}`,
    `interval=${encodeURIComponent(c.interval)}`,
    `outputsize=${c.outputsize}`,
    `timezone=UTC`,
    `apikey=${encodeURIComponent(c.api_key)}`,
    `format=JSON`,
  ].join("&");

  const req = new Request(`https://api.twelvedata.com/time_series?${params}`);
  req.timeoutInterval = 10;   // 指示書§2指定。※atr_widget は回線都合で25sに伸ばした経緯あり
                              //   → キャッシュ落ちが頻発するようならここを 25 に引き上げる
  const json = await req.loadJSON();

  if (json === null || typeof json !== "object") {
    throw new Error("DXY: not an object");
  }
  if (json.status === "error") {
    throw new Error(`Twelve Data: ${json.message || "unknown"}`);
  }
  if (!Array.isArray(json.values)) {
    throw new Error("Twelve Data: values missing");
  }

  // values は新しい順 → 古い順に反転。土日バーは除外
  // （休場中の薄い/TR=0バーで平滑が汚れる問題への対応・atr_widget と同じ）
  let candles = json.values.slice().reverse()
    .filter(v => {
      const t = parseUtcMs(v.datetime);
      if (t === null) return false;
      const day = new Date(t).getUTCDay();
      return day !== 0 && day !== 6;  // 0=日, 6=土 を除外（UTC基準）
    })
    .map(v => ({
      datetime: v.datetime,
      high:  parseFloat(v.high),
      low:   parseFloat(v.low),
      close: parseFloat(v.close),
    }));

  // 確定バーのみ: 最新バーが現在UTC時のバー（形成中）なら捨てる。パース不能も安全側で捨てる
  if (candles.length > 0) {
    const lastT = parseUtcMs(candles[candles.length - 1].datetime);
    const hourStartUtc = Math.floor(Date.now() / 3600000) * 3600000;
    if (lastT === null || lastT >= hourStartUtc) {
      candles = candles.slice(0, -1);
    }
  }
  return candles;
}

// 標準 Wilder ADX/DI±（candles: 古い順・atr_widget calculateWilderATR と同じ配列向き/初期化流儀）
function calculateWilderADX(candles, period) {
  // ADX初期化に period本のDX が要る → 最低 2*period+1 本（1500本取得なら余裕）
  if (!Array.isArray(candles) || candles.length < period * 2 + 1) return null;

  // 1. TR / +DM / -DM（i=1 から。tr[j] は candles[j+1] に対応）
  const tr = [], dmP = [], dmM = [];
  for (let i = 1; i < candles.length; i++) {
    const h = candles[i].high, l = candles[i].low, pc = candles[i - 1].close;
    tr.push(Math.max(h - l, Math.abs(h - pc), Math.abs(l - pc)));
    const up = h - candles[i - 1].high;
    const dn = candles[i - 1].low - l;
    dmP.push((up > dn && up > 0) ? up : 0);
    dmM.push((dn > up && dn > 0) ? dn : 0);
  }

  // 2. 初期値 = 最初の period本の単純和 → 以後 Wilder平滑 X = X - X/period + x
  let smTR = 0, smDMP = 0, smDMM = 0;
  for (let j = 0; j < period; j++) { smTR += tr[j]; smDMP += dmP[j]; smDMM += dmM[j]; }

  const spreadSeries = [];   // {datetime, spread} DI定義バーごと（5dレンジ用）
  const dxInit = [];
  let adx = null;
  let diP = 0, diM = 0;

  for (let j = period - 1; j < tr.length; j++) {
    if (j >= period) {
      smTR  = smTR  - smTR  / period + tr[j];
      smDMP = smDMP - smDMP / period + dmP[j];
      smDMM = smDMM - smDMM / period + dmM[j];
    }
    // 3. DI+ = 100 * SmoothedDM+ / SmoothedTR（DI- 同様）
    diP = (smTR > 0) ? 100 * smDMP / smTR : 0;
    diM = (smTR > 0) ? 100 * smDMM / smTR : 0;
    // 4. DX = 100 * |DI+ - DI-| / (DI+ + DI-) → ADX（初期は period本平均、以後 Wilder平滑）
    const diSum = diP + diM;
    const dx = (diSum > 0) ? 100 * Math.abs(diP - diM) / diSum : 0;
    if (adx === null) {
      dxInit.push(dx);
      if (dxInit.length === period) {
        adx = dxInit.reduce((a, b) => a + b, 0) / period;
      }
    } else {
      adx = (adx * (period - 1) + dx) / period;
    }
    spreadSeries.push({ datetime: candles[j + 1].datetime, spread: diP - diM });
  }

  // 5. 使用するのは終端（最終確定バー）の値のみ。先頭側は収束用で表示に使わない
  return {
    adx56: adx,
    di_plus: diP,
    di_minus: diM,
    spread: diP - diM,          // 6. 符号付き（+ = USD_UP）
    spreadSeries: spreadSeries,
    lastDatetime: candles[candles.length - 1].datetime,
  };
}

// 深さラベル（SPEC §2）: <2 拮抗 / 2-5 揺らぎ / 5-10 優勢 / ≥10 一方通行
// ★D1環境札の閾値（<5/5-10/10-16/≥16）とは別の物差し。混同しない
function dxyDepthLabel(spreadRounded) {
  const a = Math.abs(spreadRounded);
  const t = CONFIG.dxy.thresholds;
  if (a < t[0]) return "拮抗";
  if (a < t[1]) return "揺らぎ";
  if (a < t[2]) return "優勢";
  return "一方通行";
}

// 5dレンジ: spread系列をUTC日付でグループ → 土日除外（fetch段階で除外済＋二重ガード）
// → 各営業日の最終バーspread → 直近5営業日の min/max
function calcDxyRange5d(spreadSeries) {
  const lastByDay = {};
  const dayOrder = [];
  for (const p of spreadSeries) {
    const day = String(p.datetime).slice(0, 10);
    if (!(day in lastByDay)) dayOrder.push(day);
    lastByDay[day] = p.spread;   // 古い順走査 → 最後の代入 = その日の最終バー
  }
  const bizDays = dayOrder.filter(day => {
    const t = Date.parse(day + "T00:00:00Z");
    if (isNaN(t)) return false;
    const wd = new Date(t).getUTCDay();
    return wd !== 0 && wd !== 6;
  });
  const recent = bizDays.slice(-5);
  if (recent.length === 0) return null;
  const vals = recent.map(d => lastByDay[d]);
  return { min: Math.min(...vals), max: Math.max(...vals) };
}

// キャッシュ鮮度: fetched_at が hours 超過 → true（解釈不能は警告側に倒す＝isStale と同思想）
function isDxyCacheOlderThan(fetchedAt, hours) {
  const t = Date.parse(String(fetchedAt || ""));
  if (isNaN(t)) return true;
  return (Date.now() - t) > hours * 3600000;
}

// DXY札の取得〜判定一式。★絶対に throw しない（D1行の描画に影響させない）
// 戻り値: { data: <キャッシュschema>|null, fromCache: bool, stale: bool }
async function getDxy() {
  try {
    const candles = await fetchDxySeries();
    const r = calculateWilderADX(candles, CONFIG.dxy.adx_period);
    if (!r || !isFinite(r.spread)) {
      throw new Error("DXY: 計算不能（バー不足/欠損値）");
    }

    // 表示値=小数1桁に丸めてから判定（数値とラベルの見た目矛盾防止・d1_env生成器と同規約）
    const spreadRounded = Math.round(r.spread * 10) / 10;
    const label = dxyDepthLabel(spreadRounded);
    const data = {
      fetched_at: new Date().toISOString(),
      adx56: r.adx56,
      di_plus: r.di_plus,
      di_minus: r.di_minus,
      spread: spreadRounded,
      depth_label: label,
      di_dir: spreadRounded > 0 ? "UP" : (spreadRounded < 0 ? "DOWN" : "FLAT"),
      range5d: calcDxyRange5d(r.spreadSeries),
    };

    // 検収ログ（指示書§3: date, adx56, di+, di-, spread, label）
    console.log(
      `[DXY] date=${r.lastDatetime}` +
      ` adx56=${r.adx56 == null ? "null" : r.adx56.toFixed(2)}` +
      ` di+=${r.di_plus.toFixed(2)} di-=${r.di_minus.toFixed(2)}` +
      ` spread=${spreadRounded.toFixed(1)} label=${label}` +
      ` 5d=${data.range5d ? `${data.range5d.min.toFixed(1)}~${data.range5d.max.toFixed(1)}` : "null"}`
    );

    saveDxyCache(data);
    return { data: data, fromCache: false, stale: false };
  } catch (e) {
    // 失敗 → キャッシュがあれば表示（24h超は⚠）。無ければ「取得待ち」へ
    console.warn(`DXY failed: ${e}`);
    const cached = await loadDxyCache();
    if (cached && typeof cached.spread === "number" && typeof cached.depth_label === "string") {
      return {
        data: cached,
        fromCache: true,
        stale: isDxyCacheOlderThan(cached.fetched_at, CONFIG.dxy.cache_stale_hours),
      };
    }
    return { data: null, fromCache: false, stale: false };
  }
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
function addDxySection(widget, dxy) {
  widget.addSpacer(5);
  const sep = widget.addStack();
  sep.size = new Size(0, 1);          // 高さ1pt・幅は内側spacerで全幅に伸ばす
  sep.backgroundColor = COLOR_HAIRLINE;
  sep.addSpacer();
  widget.addSpacer(5);

  const row = widget.addStack();
  row.layoutHorizontally();
  row.centerAlignContent();

  if (!dxy || !dxy.data) {
    // キャッシュも無い初回失敗（or APIキー未投入）→ グレーで取得待ち
    const waitText = row.addText("DXY ─ 取得待ち");
    waitText.font = Font.systemFont(11);
    waitText.textColor = COLOR_RANGE;
    waitText.lineLimit = 1;
    row.addSpacer();
    return;
  }

  const d = dxy.data;
  const mainText = row.addText(dxyRowText(d));
  // 一方通行のみ semibold（「方向色濃」の視覚強調。※印が「過信しない」を併記）
  mainText.font = (d.depth_label === "一方通行")
    ? Font.semiboldSystemFont(11)
    : Font.systemFont(11);
  mainText.textColor = dxyRowColor(d);
  mainText.lineLimit = 1;
  mainText.minimumScaleFactor = 0.6;   // small幅で "(5d ...)" まで出す保険

  if (dxy.fromCache) {
    row.addSpacer(3);
    // fetch失敗中＝キャッシュ表示の注記。24h超は⚠（D1札の鮮度警告と同じ視覚言語）
    const note = row.addText(dxy.stale ? "⚠(キャッシュ)" : "(キャッシュ)");
    note.font = Font.systemFont(8);
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

// fetch失敗かつキャッシュ無し: 確定値ルートが完全に取れない → 止まる（Twelve Data には落ちない）
// ※DXY行はここでも出す（D1公開レグ障害でもDXY札は生きる・SPEC §3 の設計理由）
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
  // DXY札の取得を先に開始（D1 fetch と並列・getDxy は throw しない設計 → allSettled 不要）
  const dxyPromise = getDxy();

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

  const dxy = await dxyPromise;

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
