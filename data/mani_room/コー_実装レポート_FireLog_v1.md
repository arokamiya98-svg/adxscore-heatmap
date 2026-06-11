# コー実装レポート: Signal_Fire_Logger_v1.mq5

> 作成: 2026-06-11 コー
> 指示書: `data/mani_room/コー_指示書_シグナル発火ログ_v0.1.md`
> 成果物: `signals/Signal_Fire_Logger_v1.mq5`（Script 型、約780行）
> 出力: `MQL5/Files/signal_fires.csv`（UTF-8 BOM、全量上書き、65列）

---

## 1. 実装方針（最重要設計判断）

### Indicator → Script 変換の shift 規約

v4 は OnCalculate で **series 配列（idx=0 が最新）上の各バー i を、そのバー自身の指標値で判定**している。Logger はこの構造をそのまま再現する:

- 全指標（H1/H4/D1 の ATR/ADX/DI/MA）を CopyBuffer で series 配列に一括コピー
- v4 と**同一のインデックス演算**（`i + ATR_Vel_Bars` 等）で判定
- **shift 変換を一切挟まない** = OnCalculate→OnStart 変換でズレが混入する経路を構造的に断った

走査は **i >= 1（確定バーのみ）**。i=0（形成中バー）は判定しない。
v4 の歴史バー描画 = 確定バーの指標値による判定なので、これが「v4 実機チャートの矢印」との一致条件。

### フィルターの扱い

- v4 `ApplyFilters` は「抑制したら発火を消す」。Logger は**全9条件を個別 TRUE/FALSE ラベル化**し除外しない（指示書 §3.2）
- v4 の input ON/OFF は**全 ON（デフォルト）を定数として固定**
- `pass_all` = 9本すべて FALSE = v4 実機で矢印が出た発火
- **共通NG（H1_ADX>40 / ATR_Ratio>2.0 / 指標値<=0）は v4 の発火前提条件**（v3bywavelog 継承部分）なので、フィルターではなく「発火なし」として行自体を出さない（v4 と同一挙動。ここを「ラベル化」すると v4 に存在しない発火を捏造することになる）

---

## 2. v4 からの移植箇所対応表

| v4 (ATR_WidthSignal_v4.mq5) | Logger 側 | 備考 |
|---|---|---|
| L82-163 input デフォルト値 | 定数ブロック（L75-140 付近） | 全て `const` 化。input 化禁止遵守 |
| L262-274 ハンドル生成 | OnStart 冒頭 | H4 MA(46) のみ省略（v4 で取得のみ・判定未使用） |
| L339-387 `ApplyFilters` | `ComputeFilters()` | 条件式は 1:1。戻り値 bool → 9個の個別ラベルに分解 |
| L342 MID-H 派生ラベル | `ComputeFilters()` 内 `is_mid_h` | NORMAL && ratio>1.0 同一 |
| L406-421 `CalcATRMedian` | `CalcATRMedian()` | **同一実装**（コピー） |
| L428-452 `FindATRCross` | `FindATRCross()` | **同一実装**（コピー） |
| L459-468 `AtrPattern` | `AtrPattern()` | 同一。閾値のみ定数参照に置換 |
| L474-481 `FindBarIndexAtOrBefore` | 同名関数 | 同一。size に実取得本数を渡す点のみ安全側修正（§5-4） |
| L495 `median_bars` 計算 | OnStart | 8\*5\*24=960 同一 |
| L508 copy_size 余裕設計 | OnStart | +80（v4 は +20。クロス検索50本分を上乗せ） |
| L510-563 H1/H4/D1 一括コピー | OnStart | 同構成 + price 系(High/Low/Close/Time)追加 |
| L575-582 H1基本値・無効値スキップ | メインループ | 同一 |
| L585 共通NG: ADX>40 | メインループ | 同一（continue） |
| L588-594 中央値・ratio・Zone | メインループ | 同一（NG_ATR_Ratio_Max 含む） |
| L597-599 H1 pair/phase | メインループ | 同一 |
| L602-603 H1クロス検索 | **移植せず** | v4 でダッシュボード表示のみ・判定未使用 |
| L606-617 vel3/accel | メインループ | 同一（境界チェックは実取得本数 h1_size 基準） |
| L622-635 PatE用 CONTRACTING_SLOW 遡及 | メインループ | 同一 |
| L638-648 ADX zone/DI/MA位置 | メインループ | 同一（ma_pos 5分類ラベルは判定未使用のため列のみ ma_dist 出力） |
| L651-664 H4該当バー探索・無効値スキップ | メインループ | 同一 |
| L667-668 H4クロス (max_look=20) | メインループ | 同一。即値20を定数 `H4_CROSS_LOOKBACK` 化 |
| L670-677 h4_cross_bars_in_h1 | **移植せず** | v4 で計算のみ・判定未使用 |
| L679-682 H4 adz/spread/strength/up | メインループ | 同一 |
| L685-700 D1該当バー探索・クロス (max_look=30)・BU/PD/NONE・UP/DN | メインループ | 同一。即値30を定数 `D1_CROSS_LOOKBACK` 化 |
| L702-710 EnvSnapshot 構築 | `FireRow` env 部分 | 拡張（CSV 用に全状態量を保持） |
| L717-732 PatA 判定 | メインループ PatA ブロック | 条件式同一。矢印描画 → `RecordFire()` |
| L737-752 PatB 判定 | 同 PatB | 同一 |
| L757-773 PatC 判定 | 同 PatC | 同一 |
| L780-803 PatD 判定 | 同 PatD | 同一（h4_cross_recent / patD_h1_pat_ok 含む） |
| L810-832 PatE 判定 | 同 PatE | 同一（had_contract_slow / ma_close 含む） |
| L837-870 ダッシュボード | **移植せず** | 表示専用 |

multi-fire 仕様: v4 は同一バーで複数パターンが独立に矢印を出す。Logger も同一バーで条件成立した全 pattern×direction を個別行で記録（構造そのまま）。

### 他ファイルからの流用

| 流用元 | 内容 |
|---|---|
| XAUUSD_Daily_MFE_MAE_v1.mq5 `TraceMaeMfe_Segmented` | 12/24/36/48h 累積セグメント方式・MathMax(0,…)・bar_idx は48hのみ。Logger では既コピー済み series 配列を直接走査する実装に書き換え（`TraceFireMaeMfe`）。**発火方向基準**（BUY: favor=high-entry / SELL: favor=entry-low）に拡張 |
| Trade_Snapshot_Builder.mq5 | `ServerToJst`（auto offset）、`WriteUtf8Bom`/`WriteUtf8String`、構造体集約 WriteRow（64引数上限回避） |

---

## 3. CSV 列定義（65列）

| グループ | 列 | 型/値 |
|---|---|---|
| キー [1-7] | fire_id, date, time_jst, time_server, pattern, direction, entry_price | 連番 / YYYY-MM-DD(JST) / YYYY-MM-DD HH:MM ×2 / PatA〜PatE / BUY,SELL / 発火バーclose |
| H1 ATR [8-13] | h1_atr16, h1_atr32, h1_atr_median, h1_atr_ratio, atr_zone, h1_pair | ratio=atr16/中央値（v4のatr_ratio）/ LOW,NORMAL,HIGH / pair=atr16/atr32 |
| H1 パターン [14-17] | h1_pair_state, h1_pattern, h1_vel3, h1_accel | EXPAND,NEUTRAL,CONTRACT / RISING_DECEL等6種 |
| H1 ADX [18-22] | h1_adx32, h1_adx_zone, h1_di_plus, h1_di_minus, h1_di_spread | zone=LOW(<20),MID(<30),HIGH |
| H1 MA [23-24] | h1_ma, h1_ma_dist | dist=(close-MA)/ATR32（PatE判定入力） |
| H4 [25-35] | h4_atr8, h4_atr46, h4_pair, h4_pair_state, h4_adx46, h4_adx_zone, h4_di_plus, h4_di_minus, h4_di_spread, h4_cross_bars, h4_cross_dir | cross_bars=H4バー数(-1=20本内なし) / dir=UP,DOWN,NONE |
| D1 [36-43] | d1_atr22, d1_atr42, d1_adx22, d1_di_plus, d1_di_minus, d1_di_dir, cross_dir, d1_cross_bars | di_dir=UP,DN / cross_dir=BU,PD,NONE（v4 d1_atr_cross_dir）/ cross_bars=-1=30本内なし |
| フィルター [44-53] | f1_none_sell 〜 f9_pata_weakup_sell, pass_all | TRUE/FALSE。TRUE=抑制対象。pass_all=TRUE が v4 実機表示分 |
| 追跡 [54-65] | mfe_12h, mae_12h, mfe_24h, mae_24h, mfe_36h, mae_36h, mfe_48h, mae_48h, mfe_bar_idx_48h, mae_bar_idx_48h, bars_traced | USD。発火方向基準。bar_idx=発火後1..48本目 |

指示書 §3.4 案からの裁量調整: `pair_state` は H1/H4 別々に出力（`h1_pair_state`/`h4_pair_state`）。値は v4 実装通り **EXPAND/NEUTRAL/CONTRACT**（指示書の「FLAT」表記は v4 に存在しないため NEUTRAL を採用）。h1_pattern / vel3 / accel / ma_dist / cross_bars 系は v4 の判定入力なので追加。

---

## 4. 入力パラメータ（期間指定のみ・指示書遵守）

- `BT_StartTime` = 2025.03.01 00:00（**サーバー時刻として解釈**。JST 指定が必要ならメインおぱ判断で）
- `BT_EndTime` = 0（= 実行時点）
- `Verbose` = true（進捗 Print のみ。判定に影響なし）

---

## 5. 未確認事項・リスク（机上レビューで不安が残る箇所）

コンパイル環境がないため、以下を必ず確認してほしい。

1. **【最重要・照合】H4/D1 値の「確定」問題（仕様通りだが番人レビュー対象）**
   v4 は H1 バー i に対し `FindBarIndexAtOrBefore` で「その H1 を含む H4/D1 バー」の指標値を使う。歴史再計算ではこの H4/D1 値は**そのバーの close 確定値**（= H1 発火時点より最大3時間/23時間後に確定する値）。Logger はこれを**そのまま移植**した。指示書の「v4 の shift 規約から一切ずらさない」に従った結果であり、v4 実機チャートの歴史矢印とは一致する。ただし C5 の厳密解釈（発火時点で利用可能な値）とは異なる。**Trade_Snapshot_Builder v1.32 が採った sh+1 補正は適用していない**。これは「v4 の再現」が目的だから。番人判断でズレなら指摘を。
   ※同様に、H1 バー i 自身の指標値も歴史再計算では close 確定値。v4 リアルタイムでは tick 中間値で矢印が点滅し得るが、「バー確定時点の最終判定」は Logger と一致する。

2. **メモリ・処理時間（Mac 8GB 環境）**
   2025-03〜実行時点 ≈ H1 約 7,800本 + 中央値窓 960 + 余裕 ≈ **約 8,900 本 × 10配列**。配列自体は数MB で問題ないが、`CalcATRMedian` が**バー毎に 960 要素の ArraySort** を回すため、約 7,800 バー走査で数十秒〜数分かかる可能性。v4 も同じ計算をしているので動くはずだが、初回実行は気長に。

3. **チャートの「最大バー数」設定**
   H1 で約 8,900 本 + その履歴が必要（中央値窓のため実質 2024-12 頃まで遡る）。チャート設定の最大バー数が小さいと CopyBuffer が部分取得になり、期間前半のバーが `atr_med<=0` でスキップされる（WARN Print あり）。**実行前に最大バー数 ≥ 50,000 程度を推奨**。

4. **`FindBarIndexAtOrBefore` の size 引数**
   v4 は要求サイズ（h4_copy_size）をそのまま渡すが、Logger は**実取得本数（ArraySize の最小値）**を渡す。CopyBuffer が満額返す通常ケースでは挙動同一。部分取得時のみ Logger が安全側（範囲外アクセス回避）。判定結果に差が出る経路ではないと判断したが、机上確認のみ。

5. **`input datetime BT_EndTime = 0;`**
   datetime input にリテラル 0 を与える書き方。MQL5 では通るはずだが、コンパイラが嫌がったら `D'1970.01.01 00:00'` に書き換えを。

6. **JST 表記の DST ズレ**
   `ServerToJst` は実行時の TimeTradeServer-TimeGMT 差を全期間に適用（Trade_Snapshot_Builder と同じ規約・同じ制約）。2025-03〜の DST 境界（3月末/10月末）を跨ぐ過去バーは **time_jst が最大1時間ズレる**可能性。`time_server` 列が厳密値なので、照合はそちらで。

7. **直近48時間以内の発火**
   MFE/MAE 追跡が 48 本に満たない（`bars_traced < 48`）。形成中バー（idx=0）も「現時点までの実績」として走査に含めたため、**再実行すると直近発火の MFE/MAE 値が変わり得る**。bars_traced 列で識別可能。

8. **`Sleep(3000)` のインジ計算待ち**
   Script からの iATR/iADX ハンドルは初回計算に時間がかかることがある。3秒待ちで不足なら CopyBuffer が失敗し FATAL Print で止まる仕様（黙って空振りはしない）。失敗したら再実行で解決するはず。

---

## 6. あろさん実機テスト項目

1. MT5 でコンパイル（エラーが出たら §5-5 を最初に疑う）
2. **XAUUSD H1 チャート**で実行（シンボル制約あり、他チャートは FATAL で止まる）
3. ログの `fires recorded` / `pass_all=TRUE` 件数を確認
4. **pass_all=TRUE の行 5箇所以上を v4 実機チャートの矢印と目視照合**（指示書 §5 完了条件。日時は time_server 列とチャート時刻で照合）
5. 照合 NG があれば、該当行の pattern/direction/時刻をコーに戻す（§5-1 の H4/D1 境界バーが第一容疑）

---

## 7. メインおぱへの番人レビュー依頼ポイント

- §5-1: H4/D1 値の確定タイミング解釈（v4 忠実 vs C5 厳密のトレードオフ）— 指示書通り v4 忠実を採ったが、明示確認したい
- 共通NG を「発火なし」扱いにした判断（§1）— 指示書「フィルター前の全件」の解釈として正か
- BT_StartTime をサーバー時刻解釈にした点（§4）
