# 新規BT仕様書（v3bywavelogベース・フラットセンサーBT）

> 作成: 2026-06-02 / 最終更新: 2026-06-02（B/C確定）
> 目的: 現用インジ `ATR_WidthSignal_v3bywavelog` のシグナル反応精度を、フラット記録で確認し、構造分析でパターン別の挙動を解明する。
> 原則: [[memory: feedback_bt-analysis-principles]] — 結果フィッティング禁止、構造分析優先。
> 思想: 「過去勝率が悪い→フィルター」ではなく「なぜそのシグナルが効いた/効かなかった局面か」を構造から分析する。そのため、フィルター先回りせず、局面情報（D1 ADX/DI、波形BU/PD、ATR Zone等）を全件記録する。

---

## 1. 基本方針

```
ベース    : signals/ATR_WidthSignal_v3bywavelog.mq5（現用インジ）
記録方式  : 5パターン (PatA〜E) × BUY/SELL 両方向、全件記録
multi-fire: 同一バーで複数パターン同時発火OK、それぞれを別レコードとして記録
NGフィルター: インジ本体のNG（h1adx>40 / atr_ratio>2.0）は継承（=シグナル非発火）
仮想Entry : 発火バー終値（構造分析優先、再現性は犠牲）
Exit追跡  : H1足ベース（バー高安使う、軽量）
出力先    : MT5/MQL5/Files/ATR_WidthSignal_BT_NEW.csv
取込先    : /Users/aro/Desktop/ADXSCORE/data/bt/ATR_WidthSignal_BT_NEW.csv
エンコ    : UTF-16 LE BOM付き（D1系と統一）
期間      : 2024-01-01 〜 最新
スプレッド/スリッページ: 設定なし（理論値ベース）
Lot       : 0.01 固定
```

## 2. SL/TP 仕様（B1確定）

```
ATR_Avg32 = AVERAGE( ATR_Short(16)[i], ATR_Short(16)[i+1], ..., ATR_Short(16)[i+31] )
            ※ 現用 H1 ATR_Short(16) の直近32本平均

SL_dist  = ATR_Avg32 × 2.0
TP_dist  = SL_dist × 1.6        （RR 1:1.6）

SL_price = EntryPrice − SL_dist (BUY) / + SL_dist (SELL)
TP_price = EntryPrice + TP_dist (BUY) / − TP_dist (SELL)
```

- `ATR_Avg32` は別列として記録する（SL計算の透明性確保）
- 出典思想: `data/bt/SLTP_design.html`（旧周期版を現用周期に翻訳）
- Pips換算: SL_dist (USD) → SL_Pips = SL_dist × 100（XAUUSDの小数点位置に注意）

## 3. 記録列（フラット仕様・構造分析を強める設計）

### 識別
- TradeNo / OpenTime / CloseTime / Pattern (PatA/B/C/D/E) / Direction (BUY/SELL)

### エントリー情報
- EntryPrice / SL / TP / SL_Pips / TP_Pips / Lot (= 0.01)
- **ATR_Avg32**（SL計算の根拠、透明性のため）

### H1環境（執行層）
- ATR_Short(16) / ATR_Long(32)
- **ATR_Ratio_Median** = ATR_Short / ATR_Median（zone判定根拠）
- **ATR_Pair** = ATR_Short / ATR_Long（pair phase判定根拠）
- ATR_Zone (LOW / NORMAL / HIGH)
- vel3 / ATR_Accel
- **Pair_Phase** (EXPAND / CONTRACT / NEUTRAL)
- **ATR_Pattern** (RISING_DECEL / RISING_ACCEL / EXPANDING / CONTRACTING / CONTRACTING_SLOW / FLAT)
- ADX(32) / DI+ / DI- / DI_Spread / DI_Dir
- MA(32) / MA_Dist / MA_Pos (NEAR / BELOW_NEAR / BELOW_FAR / ABOVE_NEAR / ABOVE_FAR)

### H4環境（戦略層）
- ATR_Short(8) / ATR_Long(46)
- **ATR_Ratio_Median**
- **ATR_Pair**
- ATR_Zone
- **Pair_Phase** / **ATR_Pattern**
- ADX(46) / DI+ / DI- / DI_Spread / DI_Dir
- Cross_Bars_H4 / Cross_Bars_H1（H4本数とH1換算、両方記録）
- Cross_Dir (UP / DOWN / NONE)
- **MA(46) / MA_Pos**（C3決定により追加）

### D1環境（俯瞰層 / 新規）
- ATR_Short(22) / ATR_Long(42)
- **ATR_Pair** = ATR_Short / ATR_Long（Median不要、Pairのみ）
- **Pair_Phase** / **ATR_Pattern**
- ADX(22) / DI+ / DI- / DI_Spread / DI_Dir（手厚く記録、戦略分析の中核）
- **D1_ATR_Cross_Dir** (BU / PD / NONE) ← MT5側で ATR22/42 クロス方向を記録
- ※ WaveLog由来の波形BU/PDは、BT後のPythonポスト処理で `D1_Wave_Dir` として付与（A1 Option 3）

### 時間
- Weekday (Mon〜Fri) / Hour (0〜23)

### 結果
- Result (WIN / LOSS)
- Profit_USD / Profit_Pips
- **MFE / MAE / DurationBars**（H1足ベース）

合計: 約55列想定

## 4. NGフィルター（A2確定：継承）

シグナル本体に存在するNG条件は **継承**（シグナルが発火しない＝記録対象外）:
- `h1adx > NG_H1_ADX_Max (40.0)` → 発火しない
- `atr_ratio > NG_ATR_Ratio_Max (2.00)` → 発火しない

これらは「シグナル本体の挙動をそのまま反映」する設計。フィルター削除版BTは別途必要なら後で作成。

## 5. Entry / Exit 仕様

### Entry（A3確定：発火バー終値）
- 発火バーの終値で仮想エントリー
- 現実の取引と一致しない（発火を確認するには次バー始値が必要）が、構造分析優先
- 記録: OpenTime = 発火バーの開始時刻、EntryPrice = 発火バー終値

### Exit（A4確定：H1足ベース）
- H1足を1本ずつ前進、各バーの高安で SL/TP 到達判定
  - BUY: High[i] >= TP_price → TP HIT、Low[i] <= SL_price → SL HIT
  - SELL: Low[i] <= TP_price → TP HIT、High[i] >= SL_price → SL HIT
- 同一バー内で SL/TP 両方該当時の優先順位: **SL優先**（保守的）
- 記録: CloseTime = 決済バー時刻、DurationBars = OpenからCloseまでのH1本数

### MFE / MAE（H1足ベース）
- ポジション保有中、各H1バーの高安から最大含み益(MFE)/最大含み損(MAE)を追跡
- BUY: MFE_pips = (max(High[i]) - EntryPrice) × 100、MAE_pips = (EntryPrice - min(Low[i])) × 100
- SELL: 反転

## 6. パターン定義（シグナル本体から移植 / 5パターン × BUY/SELL）

シグナル本体 `signals/ATR_WidthSignal_v3bywavelog.mq5` のロジックをそのまま継承:

| Pattern | 条件（要約） |
|---------|------|
| **PatA** 大値幅期待 | atr_zone=NORMAL × atr_pat=RISING_DECEL × vel3∈[8,15] × H1/H4 DI整合 |
| **PatB** 押し目高勝率 | atr_zone=NORMAL × atr_pat=RISING_DECEL × vel3≥5 × H1がH4と逆 |
| **PatC** 初動 | atr_zone=NORMAL × atr_pat=EXPANDING × atr_ratio>1 × H4=LOW × H1=MID/HIGH |
| **PatD** H4 ATRクロス節目 ★新規 | H4 ATRクロス3本以内 × H1_pat∈{RISING_ACCEL, RISING_DECEL, EXPANDING} × H1_zone∈{LOW, NORMAL} × H1_ADX>18 × H4 DI_strength≥5 × DI整合 |
| **PatE** ボトムアウト ★新規 | H1_pair∈[0.85, 0.95] × 直前PatE_LookBack内でCONTRACTING_SLOWあり × 現在 RISING_ACCEL or EXPANDING × MA NEAR(|ma_dist|<0.5) × H1_ADX_Zone∈{LOW, MID} × H4 DI_strength≥5 × DI整合 |

詳細パラメータはシグナル本体の input 値と同一にする（PatA_Vel3_Min=8.0等）。

## 7. 実装フロー

| # | アクション | 担当 | 状態 |
|---|---------|------|------|
| 1 | SPEC擦り合わせ（B/C確定） | あろさん | ✅ 2026-06-02 完了 |
| 2 | BT mq5 コード生成 | おぱ | 🚧 進行中 |
| 3 | MT5動作確認・期間設定 | あろさん | ⏳ |
| 4 | BT実行 → CSV出力 | あろさん | ⏳ |
| 5 | CSV取込 + Pythonポスト処理（D1_Wave_Dir付与） | おぱ | ⏳ |
| 6 | 構造分析セッション開始（分析ロジック・パターン枠組み構築） | 共同 | ⏳ |

## 8. 分析の方針（BT後セッション）

> ⚠️ BT実行前に分析設計を空想で固めない。生データを見てから「何を切れるか/切るべきか」を決める。

例として想定される切り口（**確定ではない、データを見て決める**）:
- パターン別 × Direction別の素の勝率・PF・MFE/MAE分布
- D1 ADX_DI_Dir 別の挙動差（直近1年以上ぶりにDI-優勢局面 → 過去BTサンプルとの構造的違いを検証）
- ATR_Pair が低い時に各パターンの挙動がどう変わるか
- DI- 優勢局面で BUY シグナル発火時の構造的意味（"逆張り当たり"なのか"踏まれ続け"なのか）
- MFE/MAE 比から「エッジが効いた区間」と「エッジが薄かった区間」を分解
- 波形BU/PD期 × Pattern の組み合わせで PD期に強いパターン特定（[[feedback_bt-analysis-principles]]）

これらは BT結果が出てから「何が見たいか」を決める素材であり、先に固めない。

## 9. 関連ファイル

- ベースインジ: `/Users/aro/Desktop/ADXSCORE/signals/ATR_WidthSignal_v3bywavelog.mq5`
- SLTP設計書: `data/bt/SLTP_design.html`（旧周期版、思想のみ継承）
- BTソース: `data/bt/ATR_WidthSignal_BT_v3bywavelog.mq5`（このSPECに基づき新規生成）
- BT結果CSV: `data/bt/ATR_WidthSignal_BT_NEW.csv`（MT5からの取り込み先）
- 分析原則: [[memory: feedback_bt-analysis-principles]]
- 局面バイアス注意: [[memory: feedback_bt-regime-bias]]
- 評価軸: [[memory: feedback_mani-evaluation-criteria]]
