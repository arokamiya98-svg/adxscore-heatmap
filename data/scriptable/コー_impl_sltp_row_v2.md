# コー実装指示書: SL/TP 物差し行の載せ替え (v2)

> 発注: おぱ / 承認: あろさん 2026-07-10
> **v1（`コー_impl_sltp_row_v1.md`）を上書きする**: v1では atr_widget.js に実装したが、あろさんの意図は「ATR INFO H1」＝ ratio_widget（基準線ウィジェット）側だった。載せ替える。
> 前提: `ratio_widget 2.js` → `ratio_widget.js` への正本一本化はおぱ側で実施済み（配色v0.9版・タイトル「XAUUSD ATR基準 H1」）。

## A. atr_widget.js から v1実装を完全撤去（revert）

対象: `data/scriptable/atr_widget.js`（585行版）

1. `calculateWilderATRSeries` 関数を削除
2. `addSlTpRow` 関数と `buildWidget` 内の呼び出しを削除（セクションコメントは `// ----- ATR 3行 -----` に戻す）
3. main() の `h1Atr16Series` / `data.h1_atr_avg32` / saveCache の `h1_atr_avg32` / キャッシュフォールバックの `h1_atr_avg32` 行を削除
4. **6/25 の local()化・writeJson try/catch・ヘッダーコメントは触らない**
5. `SPEC_atr_widget_v1.md` の §3.5（SL/TP行の節）を節ごと削除

**revert 完了の決定的チェック**: `diff atr_widget_FIX.js atr_widget.js` の差分が **api_key の1行だけ** になること（FIX = 6/25版+実キーのため）。

## B. ratio_widget.js（ATR INFO H1）に SL/TP 行を追加

対象: `data/scriptable/ratio_widget.js`（正本化済み）。**`ratio_widget_h4.js` は触らない（H1のみ）**。

### 式（B1確定・v1と同一）

```
ATR_Avg32 = 直近32本の H1 ATR(16) 単純平均
SL_dist   = ATR_Avg32 × 2.0
TP_dist   = SL_dist × 1.6
```

- 既存の `calculateWilderATRSeries(h1, CONFIG.atr_period)` の返値 series から `series.slice(-32)` 平均で算出（新規関数は不要のはず）。32本未満は null
- 出典: `data/bt/SPEC_new_BT.md` §2（B1確定）
- **単位: ドル距離をそのまま整数表示**（あろさんの「SL60」と同じ数え方。SPEC_new_BT の「×100 pips」換算は使わない）

### 表示

- 基準線3行（平均/0.7/1.2）の**下に1行**追加
- ラベル `SL/TP`: COLOR_DIM（基準線と区別、物差し感）。値 `${Math.round(sl)} / ${Math.round(tp)}`: Menlo・COLOR_FG。null 時 "N/A"
- 絵文字・閾値・通知なし。既存 addRatioRow の行構造に馴染ませる（流用でも新関数でも可）
- ウィジェットサイズで行が窮屈ならスペーサー微調整可

### キャッシュ

- `saveCache` に `atr_avg32` を追加し、APIフォールバック時も SL/TP 行が生きるように（旧キャッシュにキー無し → N/A に倒す）

### SPEC 追記

`SPEC_ratio_widget_v1.md` に「SL/TP 物差し行」の節を追記: 式・単位（ドル距離整数・×100換算不使用）・B1出典・「物差しでありルールではない」位置づけ・キャッシュ対応。

## 検証（必須）

1. 計算部を Node スモーク: 合成OHLC 60本以上で ATR_Avg32（slice/reduce vs 手計算ループ）・SL×2.0・TP×1.6 の一致確認
2. `node --check` 構文チェック: atr_widget.js / ratio_widget.js の両方
3. A項の決定的チェック（diff が api_key 1行のみ）
4. テスト用一時ファイルは削除
