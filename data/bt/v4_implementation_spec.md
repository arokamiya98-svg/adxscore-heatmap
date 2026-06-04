# ATR_WidthSignal_v4 実装指示書

> 作成: 2026-06-03 / 作成者: メインおぱ（マネージャー）
> 実装担当: コー
> ベース: `signals/ATR_WidthSignal_v3bywavelog.mq5`
> 出力先: `signals/ATR_WidthSignal_v4.mq5`（新規作成）
> 目的: BT世代2分析で発見した **9本のボツフィルター** を搭載し、シグナル発火を抑制する

---

## 1. 概要

### 1.1 ベース
- ベースファイル: `signals/ATR_WidthSignal_v3bywavelog.mq5`（H1チャート用インジ、5パターン × BUY/SELL multi-fire）
- v3bywavelog はそのまま残す（フォワードで v3 vs v4 比較可能にするため）
- v4 は **新規ファイル** として作成

### 1.2 主要変更点
1. **9本のボツフィルター追加**（シグナル発火を抑制）
2. **各フィルター個別のON/OFF切替**（input bool パラメータ）
3. **フィルター発火カウンタ**（デバッグ出力）
4. **DI_Spread_Tight 閾値** を input double で可変化（デフォルト 1.0）

### 1.3 引き継ぐもの（変更不要）
- 5パターン（PatA〜PatE）の発火ロジック
- 描画ロジック（DRAW_ARROW × 10）
- ハンドル管理
- v3bywavelog の H1=32, H4=46, D1=22 周期設定

---

## 2. 9本フィルター仕様

### 共通前提
- 各フィルターは「該当 = シグナル発火抑制（fires[p] = false）」の挙動
- 複数フィルターが該当しても OK（最初に block 判定されたら抑制）
- input bool でフィルター個別 ON/OFF 切替可能

### 派生ラベルの定義（重要）
```
MID-L: zone_h1 == "NORMAL" && atr_ratio_median_h1 <= 1.0
MID-H: zone_h1 == "NORMAL" && atr_ratio_median_h1 >  1.0
```

### フィルター一覧

#### F1: NONE × SELL（全パターン）
- **条件**: `env.d1_atr_cross_dir == "NONE" && direction == "SELL"`
- **抑制対象**: 全パターン（PatA〜PatE）の SELL
- **物語**: D1 ATR22/42 のクロスが無い「方向不定期」での売りは構造的に死亡
- **根拠**: 両周期で再現 PF 0.24 (46版 N=19) ★★★周期非依存

#### F2: PatB × MID-H × SELL
- **条件**: `pattern == "PatB" && env.atr_zone_h1 == "NORMAL" && env.atr_ratio_median_h1 > 1.0 && direction == "SELL"`
- **抑制対象**: PatB_SELL
- **物語**: 押し目売りロジック（PatB）が拡張中（MID-H）で空振り
- **根拠**: 両周期で再現 PF 0.38 (46版 N=16) ★★★周期非依存

#### F3: PatD × PD × BUY（全Zone）
- **条件**: `pattern == "PatD" && env.d1_atr_cross_dir == "PD" && direction == "BUY"`
- **抑制対象**: PatD_BUY
- **物語**: H4 ATRクロス節目順張りが、D1 PD（収束方向）と逆走
- **根拠**: 46版 N=50 PF 0.68 Net -$163（v2 PatternByPhase 発見の最大穴）

#### F4: UP × NONE × MID-H × PatC × BUY
- **条件**: `env.di_dir_d1 == "UP" && env.d1_atr_cross_dir == "NONE" && env.atr_zone_h1 == "NORMAL" && env.atr_ratio_median_h1 > 1.0 && pattern == "PatC" && direction == "BUY"`
- **抑制対象**: PatC_BUY
- **物語**: 拡張ピーク後の初動買い = 高値掴み
- **根拠**: 46版 N=8 PF 0.09 (v2マップ完全局面ボツ)

#### F5: UP × BU × MID-H × PatB × BUY
- **条件**: `env.di_dir_d1 == "UP" && env.d1_atr_cross_dir == "BU" && env.atr_zone_h1 == "NORMAL" && env.atr_ratio_median_h1 > 1.0 && pattern == "PatB" && direction == "BUY"`
- **抑制対象**: PatB_BUY
- **物語**: 拡張BU中の押し目買い = 押し目過ぎ
- **根拠**: 46版 N=12 PF 0.16 (v2マップ完全局面ボツ)

#### F6: UP × PD × MID-H × PatC × BUY
- **条件**: `env.di_dir_d1 == "UP" && env.d1_atr_cross_dir == "PD" && env.atr_zone_h1 == "NORMAL" && env.atr_ratio_median_h1 > 1.0 && pattern == "PatC" && direction == "BUY"`
- **抑制対象**: PatC_BUY
- **物語**: PD中の初動買い = 逆張り
- **根拠**: 46版 N=11 PF 0.61 (v2マップ完全局面ボツ)

#### F7: DI_Spread_Tight × SELL
- **条件**: `MathAbs(env.di_spread_h4) < Filter_F7_SpreadThresh && direction == "SELL"`
- **抑制対象**: 全パターンのSELL
- **デフォルト閾値**: 1.0（BT埋め込み値と同一）
- **物語**: H4 DI拮抗時の売り = 方向確信ない場面の逆張り売りで死亡
- **根拠**: 46版 Tight×SELL PF 0.67、特に SELL限定で両周期共通ボツ

#### F8: PatC × NONE × SELL（新規・AxisDeep由来 A限定版）
- **条件**: `pattern == "PatC" && env.d1_atr_cross_dir == "NONE" && direction == "SELL"`
- **抑制対象**: PatC_SELL
- **物語**: PatC の SELL は PD専用機能。NONE では売り空振り
- **根拠**: AxisDeep N=7 PF 0.19
- **注意**: F1 (NoneSell全パターン) が ON だと F8 はカバーされる。F1=OFF で F8=ON の構成も可能なように両方残す

#### F9: PatA × 弱ADX × UP × SELL（新規・AxisDeep由来 D）
- **条件**: `pattern == "PatA" && env.adx_d1 < Filter_F9_WeakAdxThresh && env.di_dir_d1 == "UP" && direction == "SELL"`
- **抑制対象**: PatA_SELL
- **デフォルト閾値**: 20.0（CLAUDE.md D1ラベラー「弱」の境界）
- **物語**: 弱ADX（トレンド未形成）× UP優勢市場 × 売り = 三重逆風
- **根拠**: AxisDeep N=9 PF 0.20 WR 22.2%

---

## 3. 入力パラメータ仕様

`signals/ATR_WidthSignal_v3bywavelog.mq5` の既存パラメータの**直後**に以下を追加:

```mq5
input group "=== ★v4新規: ボツフィルター ==="
input bool   Filter_F1_NoneSell        = true;   // F1: NONE × SELL全パターン抑制
input bool   Filter_F2_PatBMidHSell    = true;   // F2: PatB × MID-H × SELL抑制
input bool   Filter_F3_PatDPdBuy       = true;   // F3: PatD × PD × BUY全Zone抑制
input bool   Filter_F4_PatC_UpNoneMidH = true;   // F4: UP×NONE×MID-H×PatC×BUY抑制
input bool   Filter_F5_PatB_UpBuMidH   = true;   // F5: UP×BU×MID-H×PatB×BUY抑制
input bool   Filter_F6_PatC_UpPdMidH   = true;   // F6: UP×PD×MID-H×PatC×BUY抑制
input bool   Filter_F7_TightSell       = true;   // F7: H4 DI拮抗 × SELL抑制
input double Filter_F7_SpreadThresh    = 1.0;    // F7閾値: |H4 DI_Spread| < これ
input bool   Filter_F8_PatC_NoneSell   = true;   // F8: PatC × NONE × SELL抑制（F1がON時は冗長）
input bool   Filter_F9_PatA_WeakUpSell = true;   // F9: PatA × 弱ADX × UP × SELL抑制
input double Filter_F9_WeakAdxThresh   = 20.0;   // F9閾値: D1_ADX < これ
input bool   Filter_DebugPrint         = false;  // 抑制時にPrint出力
```

---

## 4. 実装方針

### 4.1 関数追加
- `bool ApplyFilters(const EnvSnapshot &env, const string &pattern, const string &direction)` を新設
  - 戻り値 `true` = 抑制（fires[p] = false）
  - 戻り値 `false` = 通過（既存の発火維持）
- `DetectFires()` の各パターン発火判定の **直後** に呼び出す

### 4.2 実装位置
v3bywavelog の `DetectFires()` 内の各 `fires[i] = true` の前後で：

```mq5
// 例: PatA BUY
if(patA_base && h1_up) {
   string dir = "BUY";
   if(!ApplyFilters(env, "PatA", dir)) {
      fires[0] = true;  // BUY
   } else if(Filter_DebugPrint) {
      Print("F-blocked: PatA BUY at ", TimeToString(env.open_time));
   }
}
```

### 4.3 ApplyFilters実装テンプレ

```mq5
bool ApplyFilters(const EnvSnapshot &env, const string &pattern, const string &direction)
{
   bool is_mid_h = (env.atr_zone_h1 == "NORMAL" && env.atr_ratio_median_h1 > 1.0);
   
   // F1: NONE × SELL全パターン
   if(Filter_F1_NoneSell && env.d1_atr_cross_dir == "NONE" && direction == "SELL") return true;
   
   // F2: PatB × MID-H × SELL
   if(Filter_F2_PatBMidHSell && pattern == "PatB" && is_mid_h && direction == "SELL") return true;
   
   // F3: PatD × PD × BUY全Zone
   if(Filter_F3_PatDPdBuy && pattern == "PatD" && env.d1_atr_cross_dir == "PD" && direction == "BUY") return true;
   
   // F4: UP × NONE × MID-H × PatC × BUY
   if(Filter_F4_PatC_UpNoneMidH && env.di_dir_d1 == "UP" && env.d1_atr_cross_dir == "NONE" 
      && is_mid_h && pattern == "PatC" && direction == "BUY") return true;
   
   // F5: UP × BU × MID-H × PatB × BUY
   if(Filter_F5_PatB_UpBuMidH && env.di_dir_d1 == "UP" && env.d1_atr_cross_dir == "BU" 
      && is_mid_h && pattern == "PatB" && direction == "BUY") return true;
   
   // F6: UP × PD × MID-H × PatC × BUY
   if(Filter_F6_PatC_UpPdMidH && env.di_dir_d1 == "UP" && env.d1_atr_cross_dir == "PD" 
      && is_mid_h && pattern == "PatC" && direction == "BUY") return true;
   
   // F7: H4 DI_Spread拮抗 × SELL
   if(Filter_F7_TightSell && MathAbs(env.di_spread_h4) < Filter_F7_SpreadThresh && direction == "SELL") return true;
   
   // F8: PatC × NONE × SELL
   if(Filter_F8_PatC_NoneSell && pattern == "PatC" && env.d1_atr_cross_dir == "NONE" && direction == "SELL") return true;
   
   // F9: PatA × 弱ADX × UP × SELL
   if(Filter_F9_PatA_WeakUpSell && pattern == "PatA" && env.adx_d1 < Filter_F9_WeakAdxThresh 
      && env.di_dir_d1 == "UP" && direction == "SELL") return true;
   
   return false;
}
```

### 4.4 OnInit() での起動Print
v4 起動時に有効フィルター一覧をPrint:
```
==== ATR_WidthSignal_v4 Init ====
F1 NoneSell: ON
F2 PatBMidHSell: ON
...
```

---

## 5. 注意事項

### 5.1 周期パラメータ
- **H1=32 / H4=46 / D1=22** 確定（CLAUDE.md準拠）
- v3bywavelog の既存値を変更しない

### 5.2 EnvSnapshot 構造体
- v3bywavelog の既存メンバー（atr_zone_h1, atr_ratio_median_h1, d1_atr_cross_dir, di_dir_d1, adx_d1, di_spread_h4, etc.）をそのまま使用
- 新規メンバー追加は不要

### 5.3 描画への影響
- フィルター抑制時は `fires[p] = false` で済む
- 描画バッファ・色定義は変更しない

### 5.4 重複フィルター
- F1 ON時、F8 は冗長（F1 が全パターンの NONE×SELL を抑制するため）
- 両方残す理由：将来 F1=OFF / F8=ON の構成テストを可能にするため

### 5.5 ファイル冒頭コメント
```mq5
//+------------------------------------------------------------------+
//|  ATR_WidthSignal_v4.mq5                                          |
//|  v3bywavelog + 9本ボツフィルター搭載版                            |
//|                                                                  |
//|  v4思想:                                                          |
//|  - v3bywavelogの5パターン発火ロジックを完全継承                   |
//|  - BT世代2分析（PATTERN_REGIME_MAP_v2 / v2_PatternByPhase /      |
//|    v2_AxisDeep）で発見した9本のボツフィルターでシグナル抑制       |
//|  - 各フィルター個別ON/OFF切替可能（input bool）                  |
//|                                                                  |
//|  H4_ADX周期: 46（BT世代2比較で確定）                              |
//|  BU/PD判定: D1 ATR22/42 クロス方向（自動）                       |
//|                                                                  |
//|  作成日: 2026-06-03                                              |
//|  参照: data/bt/v4_implementation_spec.md                         |
//+------------------------------------------------------------------+
```

---

## 6. テスト想定（あろさんが MT5 で確認）

1. **コンパイル**（F7）でエラー無しを確認
2. XAUUSD H1 チャートにドラッグ
3. 全フィルター ON のとき、過去のシグナル発火数が v3bywavelog より減ることを目視確認
4. `Filter_DebugPrint = true` でエキスパートログに「F-blocked: ...」が出力されることを確認
5. 各フィルター個別 OFF にして、該当シグナルが復活することを確認

---

## 7. 完成チェックリスト（コー自己確認用）

- [ ] ファイル名 `signals/ATR_WidthSignal_v4.mq5` で新規作成
- [ ] v3bywavelog 5パターン発火ロジックを完全継承
- [ ] 9本のフィルター実装（F1〜F9）
- [ ] input bool/double で個別ON/OFF + 閾値可変
- [ ] `ApplyFilters()` 関数を `DetectFires()` 内で各パターン発火直後に呼ぶ
- [ ] `Filter_DebugPrint` 時の Print出力
- [ ] `OnInit()` でフィルター状態のPrint
- [ ] ファイル冒頭コメントを更新
- [ ] コンパイル試行（メインおぱには報告）

---

## 8. 完成後の納品

- 完成MQL5ファイル: `signals/ATR_WidthSignal_v4.mq5`
- 報告: メインおぱへ「実装完了・コンパイル結果・実装上の判断事項」を返す

## 9. 関連ファイル

- 元シグナル: `signals/ATR_WidthSignal_v3bywavelog.mq5`
- BTソース: `data/bt/ATR_WidthSignal_BT_v3bywavelog_gen2.mq5`
- 分析v2: `data/bt/PATTERN_REGIME_MAP_v2.md`
- 分析v2+: `data/bt/PATTERN_REGIME_MAP_v2_PatternByPhase.md`
- 分析v2++: `data/bt/PATTERN_REGIME_MAP_v2_AxisDeep.md`
- 原則: CLAUDE.md（ラベル層と点数層の分離、認識ツール思想）
