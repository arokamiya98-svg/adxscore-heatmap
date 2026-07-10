//---------------------------------------------------
// Scriptable ATR Ratio 基準線 Widget v1 （H4版）
// XAUUSD 認識ツール（価格非依存・ATR Ratio の $基準線 3本 / H4 時間軸）
//
// 仕様: data/scriptable/SPEC_ratio_widget_v1.md
// 根拠: data/bt/PATTERN_REGIME_MAP_v2_AtrRatioEdge.md（0.7/1.2 の由来）
// 姉妹: data/scriptable/ratio_widget.js（H1版・同一ロジック）/ atr_widget.js（既存＝加熱ウィジェット。本ファイルは一切それを触らない）
//
// 役割:
//   ATR Ratio の「基準線」を $絶対値 で常時表示する（H4 版）。
//   中央値(Ratio 1.0) / 0.7値(収束下限) / 1.2値(拡張) の 3つの $基準値だけ を出す。
//
// ★重大原則（あろさん・認識ツール思想）:
//   - 方向（買い/売り）は焼かない。0.7/1.2 での方向は局面（レンジ/BU/DN）で変化する変数。
//     値幅の基準線は不変の指標、方向は可変、をきっぱり分離する（ATRは値幅・方向と混同しない）。
//   - よって色は「値幅局面色」のみ。平均(中央値1.0)=灰(ニュートラル) / 0.7=収束(紫) / 1.2=拡張(琥珀)。
//     ※琥珀=拡張・紫=収束の"値幅局面色"であり、方向(買い/売り)では断じてない
//       （カレンダー v0.9 の BU=琥珀 / PD=紫 と統一）。
//
// 中央値は BT (data/bt/ATR_WidthSignal_BT_v3bywavelog_gen2.mq5 の CalcMedian) と
// 寸分同じ定義で組む（H1版と同一ロジック。周期・本数だけ H4 パラメータへ差し替え）。
//---------------------------------------------------

const CONFIG = {
  // Twelve Data API（api_key は atr_widget.js と同一の実キーを端末側で設定する）
  api_key: "<TWELVE_DATA_API_KEY>",
  symbol: "XAU/USD",

  // ATR 系列の周期（H4 ATR短期=8。XAUUSD H4 指標周期 ATR8/46 の短期側）
  atr_period: 8,

  // 中央値の対象本数（H4定義: ATR_Median_Weeks(8) * 5営業日 * 6本/日 = 240）
  // 履歴が満たなければ「取れた分」で算出（calcMedianBT 側でフォールバック）。
  median_bars: 8 * 5 * 6,   // = 240

  // Ratio 基準（中央値=1.0 に対する倍率。H1版と同じ 0.7/1.2 を踏襲）
  ratio_low:  0.7,   // 収束下限
  ratio_high: 1.2,   // 拡張

  // 取得本数。UTC土日フィルタ後に median_bars(240) を確保する余裕を持たせる。
  // 実機の履歴深度が足りなくても calcMedianBT が「取れた分」に自動フォールバック。
  outputsize: 400,

  // 表示
  refresh_interval_min: 15,
};

// atr_widget.js と同様、iCloud 書き込みの "Failed writing to disk" 回避のため local。
// キャッシュは専用ファイルに分離（H1版 ratio_widget_cache / 既存 atr_widget の state とは混ぜない）。
const FM = FileManager.local();
const CACHE_PATH = FM.joinPath(FM.documentsDirectory(), "ratio_widget_h4_cache.json");

// ---------------- ファイル I/O（atr_widget.js から踏襲）----------------
// downloadFileFromiCloud は Promise を返すので await 必須。
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

// ---------------- API（atr_widget.js から踏襲）----------------
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

// ---------------- ATR 計算 ----------------
// 既存 atr_widget.js の calculateWilderATR をそのまま踏襲（最後の1本のみ返す）。
// 本ウィジェットの表示自体には未使用だが、系列版との等価性（末尾一致）の基準として残す。
function calculateWilderATR(candles, period) {
  if (!Array.isArray(candles) || candles.length < period + 1) return null;

  const trArr = [];
  for (let i = 1; i < candles.length; i++) {
    const h = candles[i].high;
    const l = candles[i].low;
    const pc = candles[i - 1].close;
    const tr = Math.max(h - l, Math.abs(h - pc), Math.abs(l - pc));
    trArr.push(tr);
  }
  if (trArr.length < period) return null;

  let atr = 0;
  for (let i = 0; i < period; i++) atr += trArr[i];
  atr /= period;

  for (let i = period; i < trArr.length; i++) {
    atr = (atr * (period - 1) + trArr[i]) / period;
  }

  return atr;
}

// ★新規: calculateWilderATR と同一ロジックで、平滑の各ステップ atr を配列で返す。
//   末尾が最新。series[series.length-1] === calculateWilderATR(candles, period) が成立する。
//   中央値は「各バーの ATR 系列」が要るのでこの関数を足す（既存は最後の1本しか返さない）。
function calculateWilderATRSeries(candles, period) {
  if (!Array.isArray(candles) || candles.length < period + 1) return [];

  // True Range 配列（i=1 から）: calculateWilderATR と完全同一
  const trArr = [];
  for (let i = 1; i < candles.length; i++) {
    const h = candles[i].high;
    const l = candles[i].low;
    const pc = candles[i - 1].close;
    const tr = Math.max(h - l, Math.abs(h - pc), Math.abs(l - pc));
    trArr.push(tr);
  }
  if (trArr.length < period) return [];

  const series = [];

  // 初期 ATR = 最初の period本 TR の単純平均（= 系列の先頭要素）
  let atr = 0;
  for (let i = 0; i < period; i++) atr += trArr[i];
  atr /= period;
  series.push(atr);

  // Wilder smoothing の各ステップを配列化（末尾が最新）
  for (let i = period; i < trArr.length; i++) {
    atr = (atr * (period - 1) + trArr[i]) / period;
    series.push(atr);
  }

  return series;
}

// ★新規: BT の CalcMedian 移植（BTと寸分同じにするのが命）。
//   ソース: data/bt/ATR_WidthSignal_BT_v3bywavelog_gen2.mq5 L364-377
//     double CalcMedian(const double &arr[], int idx, int bars){
//        int sz=ArraySize(arr); if(idx+bars>=sz) return 0;   // ← 履歴不足時のハード return 0
//        double tmp[]; ArrayResize(tmp,bars); int cnt=0;
//        for(int k=idx;k<idx+bars;k++) if(arr[k]>0) tmp[cnt++]=arr[k]; // atr>0 のみ採用
//        if(cnt<10) return 0;                                  // 有効本数<10 は無効
//        ArrayResize(tmp,cnt); ArraySort(tmp);                 // 昇順ソート
//        return tmp[cnt/2];                                    // 偶数=上側中央値（整数除算=floor）
//     }
//   series=true の窓 [idx, idx+bars) は「idx（=最新側）から過去 bars 本」。
//   本ウィジェットの series は chronological(末尾=最新)なので、その窓 = 末尾 bars 本 = slice(-bars)。
//   ★BTからの唯一の緩和: 履歴不足時の `return 0` を廃し「取れた分で算出」にする（あろさん明示の
//     フォールバック）。中央値ロジック本体（atr>0 除外 / <10→null / 昇順 / 上側中央値）は不変。
function calcMedianBT(series) {
  if (!Array.isArray(series) || series.length === 0) return null;

  // 直近 median_bars 本（末尾240。無ければある分）。BT series=true 窓 [idx, idx+bars) に相当。
  const window = series.slice(-CONFIG.median_bars);

  // atr>0 のみ採用（BT: if(arr[k] > 0) tmp[cnt++] = arr[k];）
  const tmp = window.filter(v => typeof v === "number" && isFinite(v) && v > 0);
  const cnt = tmp.length;

  // 有効本数 < 10 は無効（BT: if(cnt < 10) return 0; → JS では null）
  if (cnt < 10) return null;

  // 昇順ソート（BT: ArraySort(tmp);）
  tmp.sort((a, b) => a - b);

  // 偶数時は上側中央値（BT: return tmp[cnt/2]; の整数除算 = Math.floor。下側との平均は取らない）
  return tmp[Math.floor(cnt / 2)];
}

// ---------------- 色（値幅局面色。カレンダー v0.9 の BU=琥珀 / PD=紫 と統一）----------------
// ※ COLOR_CONTRACT(紫)/COLOR_EXPAND(琥珀) は「値幅局面色」であり買い/売りの方向色ではない。
//   0.7=収束は紫（＝カレンダー PD=収縮）, 1.2=拡張は琥珀（＝カレンダー BU=拡張）。方向は局面で変化する変数。
const COLOR_BG       = new Color("#1c1c1e");
const COLOR_FG       = Color.white();
const COLOR_DIM      = Color.gray();
const COLOR_NEUTRAL  = new Color("#888888");   // 灰 （＝中央値1.0のニュートラル基準。方向でも局面でもない中立）
const COLOR_CONTRACT = new Color("#966ecd");   // 紫 （＝収束の値幅局面色。カレンダー PD=収縮 と統一。売りではない）
const COLOR_EXPAND   = new Color("#ebaf37");   // 琥珀（＝拡張の値幅局面色。カレンダー BU=拡張 と統一。買いではない）

// ---------------- ウィジェット構築 ----------------
function buildWidget(data) {
  const widget = new ListWidget();
  widget.backgroundColor = COLOR_BG;
  widget.setPadding(10, 12, 10, 12);

  // ----- ヘッダー（タイトル + 現在時刻）: atr_widget.js の作りを踏襲 -----
  const header = widget.addStack();
  header.layoutHorizontally();
  const title = header.addText("XAUUSD ATR基準 H4");
  title.font = Font.semiboldSystemFont(11);
  title.textColor = COLOR_FG;
  header.addSpacer();
  const now = new Date();
  const hh = String(now.getHours()).padStart(2, "0");
  const mm = String(now.getMinutes()).padStart(2, "0");
  const timeText = header.addText(`${hh}:${mm}`);
  timeText.font = Font.systemFont(10);
  timeText.textColor = COLOR_DIM;

  widget.addSpacer(6);

  // ----- 基準線 3行（方向ラベルなし・値幅局面色のみ）-----
  addRatioRow(widget, "平均", "(1.0)", data.median, COLOR_NEUTRAL);
  addRatioRow(widget, "0.7", "収束",  data.v07,    COLOR_CONTRACT);
  addRatioRow(widget, "1.2", "拡張",  data.v12,    COLOR_EXPAND);

  if (data.error) {
    widget.addSpacer(4);
    const errText = widget.addText(data.error);
    errText.font = Font.systemFont(9);
    errText.textColor = COLOR_DIM;
  }

  return widget;
}

// 1行: [レベル] [状態ラベル] .... [$値]
//   level  : "平均" / "0.7" / "1.2"
//   sub    : "(1.0)" / "収束" / "拡張"（← 収束/拡張の値幅状態のみ。買い/売りは書かない）
//   value  : $値（null なら N/A）
//   color  : 値の色（値幅局面色）
function addRatioRow(widget, level, sub, value, color) {
  const row = widget.addStack();
  row.layoutHorizontally();
  row.centerAlignContent();

  const levelText = row.addText(level);
  levelText.font = Font.semiboldSystemFont(12);
  levelText.textColor = color;

  row.addSpacer(6);

  const subText = row.addText(sub);
  subText.font = Font.systemFont(11);
  subText.textColor = COLOR_DIM;

  row.addSpacer();

  const valueStr = (value == null || !isFinite(value)) ? "N/A" : value.toFixed(1);
  const valueText = row.addText(valueStr);
  valueText.font = new Font("Menlo", 14);
  valueText.textColor = color;

  widget.addSpacer(2);
}

// ---------------- メイン ----------------
async function main() {
  let data;

  try {
    // H4 を1 call 取得（outputsize=400）。土日フィルタ後に ATR(8) 系列 → 直近240本の中央値。
    const h4 = await fetchOHLC("4h", CONFIG.outputsize);
    const series = calculateWilderATRSeries(h4, CONFIG.atr_period);
    const median = calcMedianBT(series);   // 直近240本（無ければある分）/ 有効<10 は null

    if (median == null) {
      // 履歴が浅く中央値が出せない → N/A（画面は殺さない）
      data = { median: null, v07: null, v12: null, error: "履歴不足（N/A）" };
    } else {
      data = {
        median: median,
        v07: median * CONFIG.ratio_low,
        v12: median * CONFIG.ratio_high,
      };
      saveCache({
        median: data.median,
        v07: data.v07,
        v12: data.v12,
        bars_used: Math.min(series.length, CONFIG.median_bars),
        saved_at: new Date().toISOString(),
      });
    }
  } catch (e) {
    // API 失敗 → キャッシュ表示にフォールバック（atr_widget.js と同方針）
    console.warn(`API failed: ${e}`);
    const cached = await loadCache();
    if (cached) {
      data = {
        median: cached.median,
        v07: cached.v07,
        v12: cached.v12,
        error: "API Err（キャッシュ表示）",
      };
    } else {
      data = { median: null, v07: null, v12: null, error: "Loading..." };
    }
  }

  const widget = buildWidget(data);

  // 定期更新のヒント（基準線は頻繁に動かないので 15分間隔で十分）
  widget.refreshAfterDate = new Date(Date.now() + CONFIG.refresh_interval_min * 60 * 1000);

  if (config.runsInWidget) {
    Script.setWidget(widget);
  } else {
    // Scriptable アプリ内で実行されたとき（デバッグ用）
    await widget.presentMedium();
  }

  Script.complete();
}

await main();
