# コー向け実装指示書 — Scriptable ATR Widget v1

> 作成: 2026-06-05 / メインおぱ
> 実装担当: コー
> 出力先: `data/scriptable/atr_widget.js`
> 関連仕様書: `data/scriptable/SPEC_atr_widget_v1.md`（先にこちらを読むこと）
> 配信先: あろさんの iPad（Scriptable アプリ、iOS 17+）

---

## 0. このドキュメントの位置づけ

- **仕様書**（`SPEC_atr_widget_v1.md`）= **何を作るか** の確定文書
- **本指示書** = **どう作るか** の実装テンプレ集

メインおぱとあろさんでブレスト〜仕様確定まで完了済み。コーは本書のテンプレを基に、`atr_widget.js` を1ファイルで完成させる。

---

## 1. 前提

| 項目 | 値 |
|---|---|
| 言語 | JavaScript（Scriptable は ES2017+ サポート） |
| 実行環境 | iOS Scriptable アプリ（iOS 17+） |
| ウィジェットサイズ | medium（4x2） |
| ファイル | `atr_widget.js`（単一ファイル、外部依存なし） |
| 外部API | Twelve Data `/time_series` のみ |
| 永続化 | iCloud Drive 上の JSON 2ファイル |

### 主要 Scriptable API（一覧）

| API | 用途 |
|---|---|
| `Request` | HTTP fetch（Twelve Data API 呼び出し） |
| `FileManager.iCloud()` | iCloud Drive の I/O |
| `ListWidget`, `WidgetStack`, `WidgetText` | ウィジェット UI 構築 |
| `Color`, `Font` | 配色・タイポ |
| `Alert` | 設定ダイアログ |
| `Script.setWidget()` | ウィジェット登録 |
| `Script.complete()` | スクリプト終了 |
| `args.queryParameters` | URL Scheme から受け取るパラメータ |

---

## 2. ファイル全体構造（雛形）

```javascript
//---------------------------------------------------
// Scriptable ATR Widget v1
// XAUUSD 認識ツール（価格非依存・H1/H4 ATR + 週次トレード回数）
//
// 仕様: data/scriptable/SPEC_atr_widget_v1.md
//---------------------------------------------------

const CONFIG = {
  api_key: "<TWELVE_DATA_API_KEY>",
  symbol: "XAU/USD",
  
  h1_atr16_high:  13.3,
  h1_atr32_high:  13.3,
  h4_atr8_high:   30.0,
  
  weekly_ideal:   3,
  weekly_limit:   5,
  reset_weekday:  1,
  
  refresh_interval_min: 15,
};

const FM = FileManager.iCloud();
const STATE_PATH  = FM.joinPath(FM.documentsDirectory(), "atr_widget_state.json");
const CONFIG_PATH = FM.joinPath(FM.documentsDirectory(), "atr_widget_config.json");
const CACHE_PATH  = FM.joinPath(FM.documentsDirectory(), "atr_widget_cache.json");

// ---------------- ファイル I/O ----------------
function readJsonSafe(path, fallback) { ... }
function writeJson(path, obj) { ... }
function loadState()  { ... }
function saveState(s) { ... }
function loadConfig() { ... }   // CONFIG とマージ
function saveConfig(c){ ... }
function loadCache()  { ... }
function saveCache(c) { ... }

// ---------------- リセット境界判定 ----------------
function getLastResetIso() { ... }
function checkWeeklyReset(state) { ... }

// ---------------- API & 計算 ----------------
async function fetchOHLC(interval, outputsize) { ... }
function calculateWilderATR(candles, period)  { ... }

// ---------------- 設定ダイアログ ----------------
async function showSettingsDialog(currentConfig) { ... }

// ---------------- ウィジェット構築 ----------------
function buildWidget(data) { ... }
function addAtrRow(stack, label, value, threshold) { ... }
function addCountRow(stack, count, ideal, limit) { ... }

// ---------------- メイン ----------------
async function main() { ... }

await main();
```

---

## 3. 関数仕様

### 3.1 ファイル I/O

```javascript
function readJsonSafe(path, fallback) {
  try {
    if (!FM.fileExists(path)) return fallback;
    if (!FM.isFileDownloaded(path)) FM.downloadFileFromiCloud(path);
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

function loadState() {
  return readJsonSafe(STATE_PATH, { week_count: 0, last_reset: null });
}
function saveState(state) { writeJson(STATE_PATH, state); }

function loadConfig() {
  const fileConfig = readJsonSafe(CONFIG_PATH, null);
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

function loadCache() { return readJsonSafe(CACHE_PATH, null); }
function saveCache(c){ writeJson(CACHE_PATH, c); }
```

### 3.2 リセット境界判定

```javascript
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
```

### 3.3 Twelve Data API 呼び出し

```javascript
async function fetchOHLC(interval, outputsize) {
  // Scriptable は URLSearchParams 非サポートのため手動で組み立てる
  const params = [
    `symbol=${encodeURIComponent(CONFIG.symbol)}`,
    `interval=${encodeURIComponent(interval)}`,
    `outputsize=${outputsize}`,
    `apikey=${encodeURIComponent(CONFIG.api_key)}`,
    `format=JSON`,
  ].join("&");
  
  const url = `https://api.twelvedata.com/time_series?${params}`;
  const req = new Request(url);
  req.timeoutInterval = 10;       // 10秒
  const json = await req.loadJSON();
  
  if (json.status === "error") {
    throw new Error(`Twelve Data: ${json.message || "unknown"}`);
  }
  if (!Array.isArray(json.values)) {
    throw new Error("Twelve Data: values missing");
  }
  
  // values は新しい順 → 古い順にして数値変換
  const candles = json.values.slice().reverse().map(v => ({
    datetime: v.datetime,
    high:  parseFloat(v.high),
    low:   parseFloat(v.low),
    close: parseFloat(v.close),
  }));
  return candles;
}
```

### 3.4 Wilder ATR 計算

```javascript
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
```

### 3.5 設定ダイアログ

```javascript
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
```

### 3.6 ウィジェット構築

```javascript
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

function statusEmojiAtr(value, threshold) {
  if (value == null) return "⚪";
  return value >= threshold ? "🔴" : "🟢";
}
function statusEmojiCount(count, ideal, limit) {
  if (count >= limit) return "🔴";
  if (count >= ideal) return "🟡";
  return "🟢";
}

function buildWidget(data) {
  const widget = new ListWidget();
  widget.backgroundColor = COLOR_BG;
  widget.setPadding(10, 12, 10, 12);
  
  // ----- ヘッダー -----
  const header = widget.addStack();
  header.layoutHorizontally();
  const title = header.addText("XAUUSD Live");
  title.font = Font.semiboldSystemFont(11);
  title.textColor = COLOR_FG;
  header.addSpacer();
  const now = new Date();
  const hh = String(now.getHours()).padStart(2, "0");
  const mm = String(now.getMinutes()).padStart(2, "0");
  const timeText = header.addText(`${hh}:${mm}`);
  timeText.font = Font.systemFont(10);
  timeText.textColor = COLOR_DIM;
  
  if (data.error) {
    const errText = widget.addText(data.error);
    errText.font = Font.systemFont(9);
    errText.textColor = COLOR_WARN;
  }
  
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
```

### 3.7 メイン処理

```javascript
async function main() {
  // 1. State load + 週次リセット判定
  let state = loadState();
  state = checkWeeklyReset(state);
  
  // 2. Config load
  let config = loadConfig();
  
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
    const h1 = await fetchOHLC("1h", 64);
    const h4 = await fetchOHLC("4h", 24);
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
    const cached = loadCache();
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
```

---

## 4. URL Scheme 動作確認

ウィジェットからスクリプトをタップ起動するための URL Scheme:

| アクション | URL |
|---|---|
| インクリメント | `scriptable:///run/atr_widget?action=increment` |
| リセット | `scriptable:///run/atr_widget?action=reset` |
| 設定編集 | `scriptable:///run/atr_widget?action=settings` |

`atr_widget` の部分は **Scriptable アプリ内のスクリプト名と一致** している必要がある。あろさん側で `atr_widget` という名前でスクリプトを保存することを前提とする。スクリプト名が変わる場合、`URL_INC` 等の定数も合わせて変更する。

---

## 5. 注意事項

### 5.1 ATR(32) のための outputsize

H1 ATR(32) は最低 32本 + バッファ必要。本実装では `outputsize=64` で十分余裕。

### 5.2 iCloud File ダウンロード

Scriptable で iCloud File を読む際、まだダウンロードされていないことがある（特に初回起動時）。`isFileDownloaded()` + `downloadFileFromiCloud()` のパターンを使うこと（`readJsonSafe` 内で実装済み）。

### 5.3 API キーの保護

`atr_widget.js` を `data/scriptable/` 配下に置く場合、API キーをそのまま埋め込むかどうか注意：
- **このリポジトリは PUBLIC ではない場合のみ**直書きで OK
- PUBLIC の場合: `<TWELVE_DATA_API_KEY>` プレースホルダのまま納品し、あろさんが iPad で実機にコピーする時に書き換える運用

→ ADXSCORE リポジトリは PUBLIC のため、**プレースホルダで納品**。あろさんは iPad の Scriptable で開いて直接書き換える。

### 5.4 Color のリテラル

iOS のシステムカラーを直接使うこともできる（`Color.systemGreen()` 等）。本仕様では Hex 直書きで明示。

### 5.5 設定ダイアログのキャンセル戻り値

`Alert.present()` の cancel タップは `-1` を返す。`choice === -1` で判定。

### 5.6 Widget Refresh Policy

iOS の WidgetKit が自動更新するため、`Script.setWidget()` を呼ぶだけで OK。
特定のリフレッシュタイミングを指示したい場合は `widget.refreshAfterDate = new Date(Date.now() + 15 * 60 * 1000)` で15分後を指定可能（任意）。

---

## 6. 完成チェックリスト（コー自己確認用）

実装ファイル `data/scriptable/atr_widget.js` が以下を満たしているか：

- [ ] 単一ファイル、外部依存なし
- [ ] `CONFIG` オブジェクトが冒頭にある（あろさん編集対象）
- [ ] iCloud File パス 3種（state / config / cache）を定義
- [ ] `loadState/saveState/loadConfig/saveConfig/loadCache/saveCache` 実装
- [ ] `getLastResetIso/checkWeeklyReset` の境界判定実装
- [ ] `fetchOHLC` で Twelve Data から OHLC 取得（タイムアウト10秒・エラー時 throw）
- [ ] `calculateWilderATR` で Wilder ATR を実装（初期=単純平均、その後 smoothing）
- [ ] `showSettingsDialog` で `Alert` ベースの設定 UI
- [ ] `buildWidget/addAtrRow/addCountRow` で 4行 + ヘッダーのレイアウト
- [ ] 状態色: ATR=緑/赤、回数=緑/黄/赤
- [ ] タップ領域: 閾値→settings、[+1]→increment、⟲→reset
- [ ] `main()` で action 分岐 → API 取得 → ウィジェット登録 → `Script.complete()`
- [ ] API 失敗時はキャッシュ表示 + "API Err" ラベル
- [ ] 初回起動でデータ無し時は "Loading..." 表示
- [ ] `await main()` がファイル末尾にある

---

## 7. テスト想定（あろさん iPad 実機）

1. **初回コンパイル** — Scriptable アプリで `atr_widget` スクリプト作成 → 本ファイルの内容を貼り付け → API キーを実値に書き換え → 「Run Script」でエラー無く動作（デバッグ用に `config.runInApp = true` でも可）
2. **ホーム画面ウィジェット配置** — medium サイズで Scriptable ウィジェットを配置 → スクリプトを `atr_widget` に紐付け → 数値が表示される
3. **+1 ボタン** — タップでカウントが 1 増える、状態色が変わる
4. **⟲ リセット** — タップでカウントが 0 になる
5. **閾値タップ** — タップで設定ダイアログが開く、編集→保存で次回更新時に反映
6. **週次リセット** — `atr_widget_state.json` の `last_reset` を手動で前週日付に書き換えてみて、起動時に自動リセットされることを確認
7. **API 失敗** — 機内モードで起動 → キャッシュ表示 + "API Err" ラベル
8. **MT5 整合性** — MT5 の iATR(16/32/8) と Scriptable 表示値を 1週間並べて記録、許容範囲内か確認

---

## 8. 納品

- 完成ファイル: `data/scriptable/atr_widget.js`
- 報告: メインおぱへ「実装完了・自己テスト結果・実装上の判断事項（特に Scriptable API のクセや iOS バージョン互換）」を返す

---

## 9. 関連ファイル・メモリ

- 仕様書: `data/scriptable/SPEC_atr_widget_v1.md`
- CLAUDE.md Stage 9 — Scriptable 構想
- `[[trading-method-summary]]` — ATR は「タイミング指標」
- `[[roadmap-sensory-to-logic-phase]]` — フェーズ2のロジック化文脈
- `[[hardware-mac-environment]]` — Mac/iPad の環境前提
