# H4 Phase Auto 実装指示書

> 作成: 2026-06-04 / 作成者: メインおぱ
> 実装担当: コー
> 対象ファイル: 3点
>   1. **新規 mq5**: MT5/MQL5/Scripts/Examples/`ARO_H4PhaseAuto_v1.mq5`
>   2. **改造 py**: `scripts/process_wavelog.py`
>   3. **改造 html**: `scripts/generate_heatmap_v14.py` + `docs/heatmap_v14.html`
> 目的: H4 Wave 手動依存（[[memory: fwd-data-pipeline-weakness]]）からの脱却。ATR_RATIO + ATR Cross 方向で **H4 Phase（BU/PD/凪）を自動判定**

---

## 1. 背景と狙い

### 1.1 現状
- **H4 Wave** = ARO_FractalWaveLog_H4_XAU_v3_1.mq5（**手動トレンドライン依存**）
- **H4 ATR Zone**（今日追加）= 自動だが凪/中/拡張の方向中立ラベル
- **両者ヒートマップで内容被り** → あろさん気づき

### 1.2 あろさん設計
- **BU**: 収束底からスロープアップ → 波形頂点
- **PD**: スロープダウン → 収束、凪状態
- 「凪エリア定義」: PD凪/BU凪を別物として扱える設計余地

### 1.3 採用ロジックの根拠
- BTスクリプト (gen2) の `H4_Cross_Dir` = H4 ATR8/46 クロス方向 = 既にBU/PD/NONE 判定実装済み
- D1 ATR22/42 クロスで 88% 整合（CLAUDE.md「ATR22/42クロス88%整合」）の H4版
- ATR_Ratio ≤ 0.97 を「凪」とする閾値はカイ分析で H4 統計値裏付けあり

### 1.4 最終ヒートマップ構成（あろさん希望）
```
D1 FibTZ予測       手動
D1 Phase           手動
H4 Phase Auto ★新  自動 (BU/PD/凪)
H4 ADX×DI         自動
ADX Score          自動
適正スコア          自動
```

→ **H4 Wave 行（旧手動）と H4 ATR Zone 行（今日追加）の2行を、H4 Phase Auto 1行に統合**

---

## 2. 判定ロジック（改訂版 v2 / 5段階）

> ⚠️ **v1（3段階）から v2（5段階）へ変更**
> カイ ATR差分分析（2026-06-04）の発見「凪を3層に分解すると PF 0.49〜2.50 で真逆の構造が現れる」を反映。
> あろさん感覚「凪離脱が一番フェイク」と統計が完全一致。

### 2.1 入力（H4 完了バー単位）
- `atr_short_h4` = ATR(8) on H4
- `atr_long_h4` = ATR(46) on H4
- `atr_ratio_h4` = atr_short_h4 / atr_long_h4
- **`atr_diff_h4` = atr_short_h4 - atr_long_h4** ★v2新規
- `cross_dir_h4` = ATR8/46 クロス方向検出（直近30バー以内、`FindATRCross()` 関数で）
  - **値: `"BU"` / `"PD"` / `"NONE"`** に統一（BTでは "UP"/"DOWN" だが、mq5新規実装で BU/PD に変換出力）

### 2.2 判定関数（mq5/Python 共通仕様 v2）

```python
def h4_phase_auto(atr_ratio, cross_dir, atr_diff):
    """H4 Phase 自動判定 v2 (5段階)
    
    BU     : ATR拡張中（上抜けクロス）= スロープアップ波
    PD     : ATR拡張中（下抜けクロス）= スロープダウン波
    収束底  : 凪帯 + ATR8 < ATR46 (diff<-1.0) = ボトムアウト前（BUY/SELL方向中立で強い）
    凪      : 中立凪
    凪離脱  : 凪帯 + ATR8反発開始 (diff>+1.0) = 偽信号フェイクゾーン ★警告
    """
    if atr_ratio is None or atr_ratio <= 0:
        return "—"
    
    # 凪帯（ratio ≤ 0.97）を diff で3層に細分
    if atr_ratio <= 0.97:
        if atr_diff < -1.0:
            return "収束底"   # PF 2.50 (N=82) BUYボトムアウト最強帯
        if atr_diff > 1.0:
            return "凪離脱"   # PF 0.49 (N=40) ★フェイク警告
        return "凪"            # PF 1.20 (N=87) 中立
    
    # 拡張帯（ratio > 0.97）
    if cross_dir == "BU":
        return "BU"
    if cross_dir == "PD":
        return "PD"
    return "—"  # NONE は判定不能（クロスがしばらく無い特殊状態）
```

mq5側は同じロジックを `string H4PhaseAuto(double ratio, string cross_dir, double atr_diff)` で実装。

### 2.3 v2の効果検証（カイ計算ベース）

| Phase | N | WR% | PF | Net$ |
|---|---|---|---|---|
| BU | 213 | 46.0% | 1.19 | +$408 |
| PD | 13 | 46.2% | 1.57 | +$48 |
| 凪 | 87 | 46.0% | 1.20 | +$149 |
| **収束底** | 82 | **53.7%** | **2.50** | **+$951** |
| **凪離脱** | 40 | **17.5%** | **0.49** | **-$277** |

→ Net$ の構造が明瞭化。「収束底」が全体Netの主柱、「凪離脱」が単独損失源。

### 2.4 閾値の根拠
- **Ratio 0.97**: カイ AxisDeep 分析、H4_ATR_Ratio_Median 中央値 ≈ 1.0
- **Diff ±1.0**: カイ ATR差分分析、|diff|<1.0 を「凪安定」として中立帯化
- 将来 input パラメータで可変化:
  - `input double H4_NagiRatio_Thresh = 0.97`
  - `input double H4_NagiDiff_Thresh = 1.0`

### 2.5 BU/PD 命名統一（重要）

- BTスクリプト出力: `H4_Cross_Dir = "UP" / "DOWN" / "NONE"`
- v4新規 mq5出力: **`H4_Cross_Dir = "BU" / "PD" / "NONE"`** に統一
- 変換ロジック: `cross_dir > 0 → "BU"`, `< 0 → "PD"`, `== 0 → "NONE"`
- これにより認識ツール思想（あろさん用語）と一致

### 2.6 補足：「収束底」の特殊性
- BUY PF 2.67 / SELL PF 2.30 = **方向中立で強い**
- これは「買いは押し目、売りは拡張」非対称性を**超える発見**
- 認識ツールで強調表示候補（BU/PD とは別の特別ラベル扱い）

### 2.7 補足：「凪離脱」のフェイク警告
- あろさん感覚「凪の今ATRが低ければ低いほどいい」と完全一致
- HTML側は色警告（赤系）で識別できればOK
- フィルター化やリアルタイム警告は **Scriptable リアルタイム側で実装予定**（別案件）

---

## 3. 実装ステップ

### Step 1: mq5 新規作成

**ファイル**: `ARO_H4PhaseAuto_v1.mq5`

#### 仕様
- スクリプト型（OnStart で実行）
- H4 XAUUSD チャートで実行
- 過去期間（input datetime BT_StartTime, BT_EndTime）の全H4バーで Phase判定
- 出力: `MT5/MQL5/Files/H4PhaseAuto_weekly.csv`（週次サンプリング、金曜終値時点のH4最終バー）

#### 入力パラメータ
```cpp
input datetime Start_Time = D'2020.01.01 00:00';
input datetime End_Time   = D'2027.12.31 23:59';
input int      H4_ATR_Short = 8;
input int      H4_ATR_Long  = 46;
input int      Cross_LookBack = 30;
input double   Nagi_Thresh = 0.97;
input string   OutputFile = "H4PhaseAuto_weekly.csv";
```

#### CSV出力列（UTF-16, FILE_UNICODE）v2
```
Week,WeekEndTime,H4_BarTime,H4_ATR_Short,H4_ATR_Long,H4_ATR_Ratio,H4_ATR_Diff,H4_Cross_Bars,H4_Cross_Dir,H4_Phase_Auto
```

★v2: `H4_ATR_Diff` 列追加（= H4_ATR_Short - H4_ATR_Long）

`Week` = ISO週番号 "YYYY-Www"
`WeekEndTime` = 金曜の最終 H4 バー（最終データ）
`H4_BarTime` = 評価したH4バー時刻
`H4_Cross_Dir` = **"BU" / "PD" / "NONE"** (BTの "UP/DOWN" でなく、こちらに統一)
`H4_Phase_Auto` = **"BU" / "PD" / "凪" / "収束底" / "凪離脱" / "—"**

#### 流用元
- BTスクリプト `data/bt/ATR_WidthSignal_BT_v3bywavelog_gen2.mq5` の：
  - `FindATRCross()` 関数（428行目あたり）
  - H4 ATR計算ロジック（566-616行目あたり）
- `ARO_FractalWaveLog_H4_XAU_v3_1.mq5` の：
  - 金曜サンプリングロジック（週次出力部分）
  - CSV書き出し（UTF-16 / FILE_UNICODE）

### Step 2: process_wavelog.py 改造

#### 追加内容（v2）
1. 関数 `h4_phase_auto(ratio, cross_dir, atr_diff)` を追加（上記の Python v2版）
2. 新CSV `H4PhaseAuto_weekly.csv` を読み込み
3. weekly_waves.json に新フィールド追加:
   - `h4_phase_auto`: "BU" / "PD" / "凪" / **"収束底"** / **"凪離脱"** / "—"
   - `h4_cross_dir`: "BU" / "PD" / "NONE" / "—" （tooltip用、生データ補助）
   - `h4_atr_diff`: 差分の生値（tooltip用、float）

#### 既存フィールドの扱い
- `h4_atr_class` / `h4_atr_zone3` / `h4_atr_ratio` は**当面残す**（並列）
- 移行検証期間後に整理

### Step 3: heatmap_v14 修正

#### `scripts/generate_heatmap_v14.py` を改造（コー前回判断踏襲、パイプライン整合）

#### 追加内容（v2 - 5段階対応）
1. CSS新規クラス:
   ```css
   .hp-BU       {background:#001a38;color:#5ab8ff;border-color:#1a5090;font-weight:700;letter-spacing:.04em;}
   .hp-PD       {background:#200008;color:#ef6060;border-color:#5a0a0a;font-weight:700;letter-spacing:.04em;}
   .hp-nagi     {background:#1a1a28;color:#9aaabc;border-color:#2a3a50;letter-spacing:.04em;}
   /* ★v2新規ラベル */
   .hp-syusoku  {background:#001a14;color:#5affc0;border-color:#1a6048;font-weight:700;letter-spacing:.04em;} /* 収束底: 緑系（BU/SELL方向中立で強い、ボトムアウト前） */
   .hp-fake     {background:#280014;color:#ffaa00;border-color:#601830;font-weight:700;letter-spacing:.04em;animation:fake-blink 2s ease-in-out infinite;} /* 凪離脱: 警告オレンジ + 軽い点滅 */
   .hp-X        {background:#050a14;color:#1e3a5f;}
   
   @keyframes fake-blink {
     0%,100% { opacity:1; }
     50%     { opacity:0.65; }
   }
   ```
   ※ コー前回判断踏襲（ASCII クラス名、表示テキストは日本語維持）
   ※ 表示テキスト: BU / PD / 凪 / **収束底** / **凪離脱**
   ※ 凪離脱の点滅は控えめ（あろさん「シンプルに認識できればOK」希望）

2. ROWS配列に「H4 Phase Auto」行を追加（D1 Phase直後、H4 Wave 旧 の前）

3. **H4 Wave (旧手動) と H4 ATR Zone (今日追加) は当面行として残す**:
   - 並列表示で検証期間（フォワード）3ヶ月運用
   - 8月メンテ時に「H4 Wave 旧」「H4 ATR Zone」を引退決済

4. **行ラベル明示**:
   - 新: `🌊 H4 Phase (Auto)`
   - 旧: `📈 H4 Wave (手動)` ← 注記
   - 中間: `🌊 H4 ATR Zone` ← 凪/中/拡張、現状維持

5. 凡例に H4 Phase Auto セクション追加（5ラベル）
   - **BU** = 青（拡張上昇）
   - **PD** = 赤（拡張下降）
   - **凪** = グレー（中立収束）
   - **収束底** = 緑（ボトムアウト前・両方向で強い）
   - **凪離脱** = オレンジ警告（フェイクゾーン）

### Step 4: 動作確認（コー実装範囲）

- `python3 scripts/process_wavelog.py` 成功
- `weekly_waves.json` に `h4_phase_auto` 出力
- `python3 scripts/generate_heatmap_v14.py` 成功
- ブラウザで `docs/heatmap_v14.html` 開いて新行表示
- 最新週（2026-W22 等）で Phase が論理的に正しい（過去のあろさん引いた線と一致するか目視）

> ⚠️ mq5 のコンパイル・実行は MT5 環境必要。コーはコードレベル完結。あろさんが MT5 で BT スクリプト走らせて CSV 出力 → Mac同期 → process_wavelog.py 実行の順。

---

## 4. 注意事項

### 4.1 命名規則
- `h4_phase_auto` フィールド名で統一（既存 `h4_atr_class` / `h4_atr_zone3` と混同しないように）
- mq5側関数名: `H4PhaseAuto()`
- 行ラベル: 「H4 Phase Auto」or「H4 Phase (自動)」

### 4.2 既存資産との並列維持
- 検証期間（〜2026-08）は **3行並列表示**:
  1. 🌊 H4 Phase (Auto) ← 新
  2. 🌊 H4 ATR Zone ← 今日追加
  3. 📈 H4 Wave (手動) ← 旧
- 8月メンテで引退決済

### 4.3 ATR_Ratio が ≤0 や None の安全処理
- mq5: 0除算回避（atr_long > 0 チェック）
- py: None / 0 / NaN を "—" として扱う

### 4.4 既存スクリプト ARO_FractalWaveLog_H4_XAU_v3_1.mq5 は触らない
- 並列稼働、引退まで残す
- データソース（FractalWaveLog_H4_XAU.csv）も維持

### 4.5 Cross_LookBack=30 の理由
- BTスクリプト gen2 と同値
- H4 で 30バー = 5日分（XAUUSD H4 6本/日 × 5日 = 30）
- 直近1週間以内のクロスを拾う

---

## 5. 完成チェックリスト（コー自己確認用）

- [ ] `ARO_H4PhaseAuto_v1.mq5` 新規作成（MT5 配置先 + signals/ ミラー）
- [ ] mq5 で `H4PhaseAuto()` 関数実装
- [ ] CSV出力 (UTF-16, ヘッダー9列)
- [ ] `scripts/process_wavelog.py` に Python版 `h4_phase_auto()` 追加
- [ ] weekly_waves.json に `h4_phase_auto` / `h4_cross_dir` 追加
- [ ] `scripts/generate_heatmap_v14.py` 改造
- [ ] `docs/heatmap_v14.html` 直接改造（コー前回判断踏襲）
- [ ] CSS新規クラス追加
- [ ] 凡例更新
- [ ] 並列3行表示（Phase Auto / ATR Zone / Wave 手動）
- [ ] パイプライン実行（process → generate）成功
- [ ] メインおぱへ報告

---

## 6. 完成後の納品

- 新mq5: `MT5/MQL5/Scripts/Examples/ARO_H4PhaseAuto_v1.mq5` + `signals/ARO_H4PhaseAuto_v1.mq5`（ミラー）
- 改造py: `scripts/process_wavelog.py`（diff含むコミット可能形）
- 改造py: `scripts/generate_heatmap_v14.py`（同上）
- 改造html: `docs/heatmap_v14.html`
- 報告: 実装上の判断事項、指示書への質問

---

## 7. あろさんへのテスト依頼

1. MT5 で `ARO_H4PhaseAuto_v1.mq5` コンパイル
2. H4 XAUUSDチャートにドラッグ実行（過去期間で1回）
3. `MQL5/Files/H4PhaseAuto_weekly.csv` 出力確認
4. `./run_pipeline.sh` で Mac側統合
5. ブラウザで heatmap_v14.html 確認
6. **手動引いてた線と H4 Phase Auto の一致率を目視**（過去数ヶ月分）

---

## 8. 関連ファイル

- 既存BTソース: `data/bt/ATR_WidthSignal_BT_v3bywavelog_gen2.mq5`（流用元）
- 既存H4スクリプト: `MT5/.../ARO_FractalWaveLog_H4_XAU_v3_1.mq5`（参照、改造せず）
- ATR_RATIO分析: `data/bt/PATTERN_REGIME_MAP_v2_AtrRatioDist.md`（カイ）
- ATR_Zone追加実装: `data/bt/heatmap_v14_atr_zone_spec.md`（コー前回担当）
- 思想: CLAUDE.md「ラベル層と点数層の分離」「ATR22/42クロス88%整合」
- 制約: [[memory: fwd-data-pipeline-weakness]]（このスクリプトでフォワード弱性を一部解消）
