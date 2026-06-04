# heatmap_v14 ATR_RATIO ラベル昇格 実装指示書

> 作成: 2026-06-04 / 作成者: メインおぱ
> 実装担当: コー
> 対象: `docs/heatmap_v14.html` + `scripts/process_wavelog.py`
> 目的: BT世代2分析（PATTERN_REGIME_MAP_v2_AtrRatioDist）で「ATR_RATIO は BU/PD の代理変数として強い」と判明。**heatmap_v14 にATR_RATIO 3区分ラベルを新規行として追加**、Widget Web 経由で即時可視化

---

## 1. 背景・データ状況

### 1.1 既存データ（weekly_waves.json）
- **D1**: `d1_atr_ratio` に数値あり（例: 最新週 2026-W22 = 0.973）。`d1_atr_zone` は "—" 未計算
- **H4**: `h4_atr_ratio` フィールドが**最新週で欠落気味**、`h4_atr_class` も "—" になる週多い
- 旧 `atr_class` フィールド（"NEUTRAL"等）はあるが、カイ閾値とは別ロジック

### 1.2 カイ分析の閾値（採用）
| TF | 凪 | 中 | 拡張 |
|----|----|----|----|
| D1 | ≤ 0.95 | 0.95 〜 1.10 | > 1.10 |
| H4 | ≤ 0.97 | 0.97 〜 1.10 | > 1.10 |

H1 はリアルタイム指標で週次データに無いので heatmap_v14 では扱わない（v4 mq5側で既に評価済み）。

---

## 2. 実装ステップ

### Step 1: `scripts/process_wavelog.py` 修正
**追加内容:**
1. 新規関数 `atr_zone3(ratio, tf)` を追加:
   ```python
   def atr_zone3(ratio, tf="D1"):
       if ratio is None:
           return "—"
       threshold_low = 0.95 if tf == "D1" else 0.97
       threshold_high = 1.10
       if ratio <= threshold_low: return "凪"
       if ratio > threshold_high: return "拡張"
       return "中"
   ```

2. `weekly_waves.json` 出力時に新フィールド追加:
   - `d1_atr_zone3`: atr_zone3(d1_atr_ratio, "D1")
   - `h4_atr_zone3`: atr_zone3(h4_atr_ratio, "H4")

3. **`d1_atr_zone` の "—" は触らない**（既存の意味温存、新フィールド `d1_atr_zone3` として並列追加）

4. **h4_atr_ratio が欠落している週への対応**:
   - 既存 process_wavelog.py の H4 取得経路を確認
   - 欠落理由（fwd-pipeline-weakness: 手動線引き依存）を踏まえ、無理な補完はしない
   - 欠落週は `h4_atr_zone3 = "—"` のままでOK

### Step 2: `docs/heatmap_v14.html` 修正
**追加内容:**
1. 既存レイヤー（FibTZ / D1 Phase / H4 Wave / H4 ADX×DI / ADX Score / 適正スコア）の下に**2行追加**:
   - 行A: `D1 ATR Zone`（凪/中/拡張）
   - 行B: `H4 ATR Zone`（凪/中/拡張）
   
   表示位置は「D1 Phase の直後」が望ましい（局面ラベルと隣接）

2. **CSS新規クラス追加**（既存 d-BU-on などのスタイル踏襲）:
   ```css
   .az-凪  {background:#001a38;color:#5ab8ff;border-color:#1a5090;font-weight:600;}
   .az-中  {background:#1a1a28;color:#7a8aa0;border-color:#2a3a50;}
   .az-拡張{background:#280008;color:#ef8080;border-color:#601020;font-weight:600;}
   .az-X   {background:#050a14;color:#1e3a5f;}
   ```

3. **セルレンダリング**:
   - JavaScript の renderRow() / セル生成箇所で `d1_atr_zone3` / `h4_atr_zone3` を読む
   - クラス名: `c az-{zone}` （例: `c az-凪`）
   - セル中身: 「凪」「中」「拡張」のテキスト表示
   - データが "—" の場合は `c az-X` で空表示

4. **凡例・タイトル追加**（既存スタイルに合わせて簡潔に）

### Step 3: 動作確認（コー実装範囲）
- `python3 scripts/process_wavelog.py` 実行でエラー無し
- `weekly_waves.json` に `d1_atr_zone3` / `h4_atr_zone3` 列追加されることを確認
- `docs/heatmap_v14.html` をブラウザで開き、新規2行が表示されることを確認
- 最新数週（2026-W22 等）で `d1_atr_zone3` が正しく分類されること

---

## 3. 想定UI

```
| 行                  | W18 | W19 | W20 | W21 | W22 (今) |
|---------------------|-----|-----|-----|-----|----------|
| FibTZ予測           | BU  | BU  | PD  | PD  | PD       |
| D1 Phase            | BU↑ | BU↑ | PD  | PD↓ | PD↓     |
| D1 ATR Zone   ★新  | 拡張| 拡張| 中  | 中  | 凪       |
| H4 ATR Zone   ★新  | 中  | 拡張| 中  | 凪  | 凪       |
| H4 Wave             | BU  | BU  | -   | -   | -        |
| H4 ADX×DI          | ... | ... | ... | ... | ...      |
| ADX Score           | 65  | 72  | 55  | 48  | 37       |
| 適正スコア          | A   | A   | B   | C   | D        |
```

「凪」が並んだら**フェーズ転換シグナル予兆**、「拡張」が並んだら**トレンド成熟期**として認識可能。

---

## 4. 注意事項

### 4.1 認識ツール思想との整合
- 凪/中/拡張 は**状態ラベル**であり、数値ではない（CLAUDE.mdの「ラベル層と点数層を絶対に混ぜない」原則準拠）
- 数値（d1_atr_ratio = 0.973）はホバーtooltipで補助表示してもOK

### 4.2 既存フィールドとの混同回避
- `d1_atr_zone`（既存・"—"のまま）は触らない
- `atr_class`（"NEUTRAL"等）は別ロジックなので新フィールドは別名 `*_zone3` で並列追加

### 4.3 h4_atr_ratio 欠落への対応
- 欠落原因の深追いは不要（fwd-data-pipeline-weakness で構造的に既知）
- 欠落週は "—" のままで heatmap に空表示

### 4.4 Widget Web 反映
- 修正後 GitHub Pages を更新（git push）すれば Widget Web 側で自動反映
- コー側ではローカルの修正完了まで、git操作は不要（あろさんが最後に push）

---

## 5. 完成チェックリスト

- [ ] `scripts/process_wavelog.py` に `atr_zone3()` 追加
- [ ] `weekly_waves.json` に `d1_atr_zone3` / `h4_atr_zone3` 出力
- [ ] `docs/heatmap_v14.html` に新規2行追加
- [ ] CSS新規クラス（az-凪 / az-中 / az-拡張 / az-X）追加
- [ ] セルレンダリング追加
- [ ] ブラウザ表示確認（最新数週で分類が想定通り）
- [ ] メインおぱへ報告

---

## 6. 関連ファイル

- 入力: `scripts/process_wavelog.py`, `docs/heatmap_v14.html`
- 出力: 同上を編集
- 分析根拠: `data/bt/PATTERN_REGIME_MAP_v2_AtrRatioDist.md`（カイ分析、本セッションで作成）
- 思想: CLAUDE.md「ラベル層と点数層の分離」
- 関連: `data/maintenance/REVIEW_CYCLE.md`（8月メンテで再評価対象）
