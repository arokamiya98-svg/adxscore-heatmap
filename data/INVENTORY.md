# ADXSCORE データ索引

> ADXSCORE/ 配下のデータの索引。何が・どこに・鮮度・信頼度・由来をここに集約する。
> このファイルは「参照ゾーン入口」。新しいCSV・BT・FW記録が入ったらここに追記する。

最終更新: 2026-06-04

---

## 🚫 参照禁止ゾーン

```
/Users/aro/Desktop/ADX２８検証ファイル/   ← 凍結アーカイブ（参照しない）
```

理由: ADX28周期での旧検証（H1=28, H4=30）。現行はH1=32, H4=46。
混入を避けるため、ここを開かない・読み込まない・引用しない。

---

## 凡例

**鮮度**

| 記号 | 意味 |
|------|------|
| 🟢 | 最新・現行 |
| 🟡 | 一部古い・局面バイアスあり |
| 🔴 | 旧版・参考のみ |
| ⚫ | 未実行（これから作成） |
| ⚪ | 未設計（仕様段階） |

**信頼度**

| 記号 | 意味 |
|------|------|
| ★★★ | あろさん確定情報・実測 |
| ★★  | 計算予測・統計的中央値 |
| ★   | 暫定・要検証 |

---

## /mt5_data/ — 週次パイプライン正規データ

| ファイル | 役割 | 鮮度 | 信頼度 | エンコード |
|---------|------|------|--------|------------|
| FractalWaveLog_D1_v3_1.csv | D1 波形レベル（v3_2スクリプトが出力）| 🟢 | ★★★ | UTF-16 |
| FractalWaveLog_D1_weekly.csv | D1 週次時系列（v3_2スクリプトが出力）| 🟢 | ★★★ | UTF-16 |
| FractalWaveLog_H4_XAU.csv | H4 波形レベル | 🟢 | ★★★ | UTF-8-sig |
| FractalWaveLog_H4_XAU_Vlines.csv | H4 縦線データ（H4_XAU_v3_1の補助出力）| 🟢 | ★★★ | UTF-8-sig |
| FractalWaveLog_H4_weekly.csv | H4 週次時系列 | 🟢 | ★★★ | UTF-8-sig |
| ADX_Weekly_Above_v4.csv | H1/H4 ADX週次集計（H1=32, H4=46）| 🟢 | ★★★ | UTF-16 |
| ADX_Weekly_Above_v3.csv | H1/H4 ADX週次集計（旧, H1=28, H4=30）| 🔴 | ★ | UTF-16 |
| H4PhaseAuto_weekly.csv | H4 Phase Auto v2 出力（5段階自動判定）| 🟢 | ★★★ | UTF-8-sig |

> 📊 H4PhaseAuto_weekly.csv は 2026-06-04 から週次パイプラインに合流。BU/PD/凪/収束底/凪離脱 の5段階判定を週次で記録。

---

## /data/bt/ — バックテスト関連

### 設計資産

| ファイル | 内容 | 鮮度 | 備考 |
|---------|------|------|------|
| `SPEC_new_BT.md` | 新規BT仕様書 | 🟢 | v3bywavelogベース、B/C確定済 |
| `SLTP_design.html` | SL/TP最適解設計書 | 🟢 | SL=ATR_Avg×2.0 / TP=SL×1.6（思想のみ継承、旧周期版） |
| `v4_implementation_spec.md` | v4 mq5 実装仕様（9本フィルター搭載）| 🟢 | F1〜F9 のフィルター定義書 |
| `h4_phase_auto_spec.md` | H4 Phase Auto v2 仕様書（5段階判定）| 🟢 | v1→v2 更新済（凪離脱追加）|
| `h4_phase_auto_resume_note.md` | H4 Phase Auto 設計の経過メモ | 🟢 | コー実装時の判断履歴 |
| `heatmap_v14_atr_zone_spec.md` | heatmap_v14 ATR Zone行追加仕様 | 🟢 | D1/H4 ATR_RATIO 3区分（凪/中/拡張）|

### BT世代1（Stage 6完了, 2026-06-02実行）

| ファイル | 内容 | 鮮度 | 備考 |
|---------|------|------|------|
| `ATR_WidthSignal_BT_v3bywavelog.mq5` | BT本体（Script型）| 🟢 | 71列フラット記録、5パターン×BUY/SELL×multi-fire |
| `ATR_WidthSignal_BT_NEW.csv` | BT結果（UTF-16, 947件）| 🟢 | 2024-01-02〜2026-06-01、6h filter後481件 |
| `PATTERN_REGIME_MAP_v1.md` | 構造分析結果マップ（暫定v1）| 🟡 | v2登場により参考のみ |

### BT世代2（2026-06-03〜04 実行、46周期確定の根拠）

| ファイル | 内容 | 鮮度 | 備考 |
|---------|------|------|------|
| `ATR_WidthSignal_BT_v3bywavelog_gen2.mq5` | BT本体 世代2（パラメータ可変対応）| 🟢 | H4_ADX周期を引数化、30 vs 46比較用 |
| `ATR_WidthSignal_BT_h4adx30.csv` | BT結果 (H4_ADX=30) | 🟢 | フィルター無し PF 1.30 / フィルター後 PF 1.98 |
| `ATR_WidthSignal_BT_h4adx46.csv` | BT結果 (H4_ADX=46) | 🟢 | フィルター無し PF 1.36 / フィルター後 PF 2.12 → **採用** |
| `PATTERN_REGIME_MAP_v2.md` | 構造分析マップ コア（世代2版）| 🟢 | 機能/死亡パターン更新版 |
| `PATTERN_REGIME_MAP_v2_PatternByPhase.md` | パターン×局面（BU/PD/NONE）| 🟢 | PatC局面選好「BU=聖地/PD=普通/NONE=罠」等 |
| `PATTERN_REGIME_MAP_v2_AxisDeep.md` | 軸別深掘り（PatC×ATR_Ratio / PatA×ADX）| 🟢 | PatA万能性 / PatD仮説検証など |
| `PATTERN_REGIME_MAP_v2_AtrRatioDist.md` | H1/H4/D1 ATR_RATIO分布 | 🟢 | ATR Zone 3区分しきい値の根拠 |

> 📊 BT世代2の主要発見:
> - **H4_ADX=46周期 確定採用**（フィルター後優位、特にSELL/DN期）
> - 「凪離脱が一番フェイク」が統計裏付け（PF 0.49 / N=40）
> - PatD仮説1（BU期+H1拡張）完全的中、PatBは「凪専門」ではなくオールラウンダー
> - 詳細: [[memory: bt-v1-findings-2026-06]] / `PATTERN_REGIME_MAP_v2*.md`

### 旧BT資産（参照禁止ゾーンへ隔離済み）

2026-06-02、新規BT着手にあたり類似名コードによる汚染を防ぐため、`data/bt/legacy/` を物理的に隔離した。

```
移動先: /Users/aro/Desktop/ADX２８検証ファイル/legacy_ATR_WidthSignal_BT/
  ├ ATR_WidthSignal_BT_v3.mq5 / .csv
  ├ ATR_WidthSignal_BT_v3wavelog.mq5 / .ex5
  └ _README.md
```

> どうにもならなかった時の参考にのみ開く。戦略判断の根拠として使わない。

---

## /data/forward/ — 手動フォワードテスト記録

| ファイル | 内容 | 鮮度 | 信頼度 | 備考 |
|---------|------|------|--------|------|
| v4_forward_log.md | v4 mq5 フォワード記録テンプレ | 🟢 | ★ | **2026-06-04 開始**。初回メンテ 2026-08-15 前後 |

---

## /data/maintenance/ — 再評価・メンテ運用

| ファイル | 内容 | 鮮度 | 備考 |
|---------|------|------|------|
| REVIEW_CYCLE.md | 再評価サイクル設計書 | 🟢 | 8月集中メンテ → 9月新サイクル開始 |

---

## /signals/ — 現用シグナル/インジ mq5 ミラー

| ファイル | チャート | 役割 | 鮮度 | 備考 |
|---------|---------|------|------|------|
| ATR_WidthSignal_v4.mq5 | H1メイン | エントリーシグナル本体（**9本フィルター搭載**）| 🟢 | **フォワード稼働中 2026-06-04〜**、F1〜F9 個別ON/OFF |
| ATR_WidthSignal_v3bywavelog.mq5 | H1メイン | シグナル前世代（フィルター無し）| 🟡 | v4の比較用に保存。実運用はv4 |
| ARO_H4PhaseAuto_v1.mq5 | H4 | H4 Phase Auto v2（5段階自動判定）| 🟢 | BU/PD/凪/収束底/凪離脱、週次同期 |
| ATR_Velocity_Rhythm_v2_NoBG.mq5 | H1 sub1 | ATR速度/リズム可視化 | 🟢 | 周期H1ADX32/H4ADX46 |
| ATR_Velocity_Rhythm_D1_v1.mq5 | H4/D1 sub | ATR Vel Rhythm D1 | 🟢 | H4=ADX46×ADX32 / D1=ADX22×ADX30 |
| ATR_Dual_v1.mq5 | 全TF sub | ATR短期×長期の二本表示 | 🟢 | TF別パラメータ（H1:16/30, H4:8/46, D1:22/42）|
| ATR_Ratio_Dual_v1.mq5 | 全TF sub | ATR Ratio 二本表示 | 🟢 | 2026-06-02 追加 |
| BarCount_Drawing_v1.mq5 | 補助 | バーカウント描画 | 🟢 | — |

> オリジナル: `/Users/aro/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/Program Files/MetaTrader 5/MQL5/Indicators/Free Indicators/`
> ここに置くコピーは「ADXSCORE参照ゾーン内に現用ロジックを保持する」ためのもの。MT5本体側の編集時に同期かける運用。

### signals/ 未配置のもの（あとで判断）

- 収集スクリプト (mq5): `ARO_FractalWaveLog_D1_v3_2`, `ARO_FractalWaveLog_H4_XAU_v3_1`, `ADX_Weekly_Above_v4`, `WaveLog_Export_v1_6`
  → 「シグナル」ではなく「データ収集」なので、`signals/collectors/` を作るか別フォルダ案にするかは要相談

---

## /scripts/ — Python 分析・パイプラインスクリプト

### パイプライン本体（週次実行）

| ファイル | 役割 | 鮮度 | 備考 |
|---------|------|------|------|
| sync_mt5_data.sh | MT5 → mt5_data/ 同期 | 🟢 | run_pipeline.sh から呼ばれる |
| process_wavelog.py | CSV → weekly_waves.json 変換（ADXスコア計算込み）| 🟢 | 2026-06-04 H4 Phase Auto / ATR Zone 反映済 |
| generate_heatmap_v14.py | weekly_waves.json → heatmap_v14.html 生成 | 🟢 | 2026-06-04 ATR Zone行追加版 |

### BT分析スクリプト（不定期）

| ファイル | 役割 | 鮮度 | 備考 |
|---------|------|------|------|
| analyze_bt.py | BT世代1 構造分析 → PATTERN_REGIME_MAP_v1 | 🟡 | v2登場により参考のみ |
| analyze_bt_gen2.py | BT世代2 構造分析 → PATTERN_REGIME_MAP_v2 | 🟢 | コア分析 |
| analyze_pattern_by_phase.py | パターン×局面分析 → v2_PatternByPhase | 🟢 | — |
| analyze_axis_deep.py / _v2.py | 軸別深掘り分析 → v2_AxisDeep | 🟢 | v2が現行 |
| analyze_atr_ratio_dist.py | H1/H4/D1 ATR_RATIO 分布 → v2_AtrRatioDist | 🟢 | ATR Zone しきい値の根拠 |
| analyze_pattern_atr_ratio.py | パターン×ATR_Ratio 分析 | 🟢 | PatC×ATR_Ratio などに使用 |
| compare_30_46_filtered.py | H4_ADX 30 vs 46 比較（フィルター適用後）| 🟢 | 46周期採用の根拠 |

### 旧版（参考のみ）

| ファイル | 状態 | 備考 |
|---------|------|------|
| generate_heatmap_v12.py / generate_html.py | 🔴 | v14登場により非推奨 |
| fetch_and_calc_v2.py | 🟡 | Twelve Data API取得スクリプト旧版。Stage 9 Scriptableリアルタイム化で再利用検討対象 |
| send_line_v2.py / send_line_weekly.py | 🔴 | 日次配信廃案、Stage 9 Scriptableリアルタイム化へ統合 |
| initialize_history.py | 🔴 | 初期化用、現行不要 |

---

## /data/weekly_waves.json — パイプライン中間生成物

| ファイル | 役割 | 鮮度 | 備考 |
|---------|------|------|------|
| weekly_waves.json | process_wavelog.py の出力（ADXスコア + H4 Phase Auto + ATR Zone 含む）| 🟢 | generate_heatmap_v14.py の入力 |

---

## /docs/ — 公開HTML

| ファイル | 内容 | 鮮度 | 備考 |
|---------|------|------|------|
| heatmap_v14.html | ★週次ヒートマップ（現行最新）| 🟢 | GitHub Pages公開、Widget Web表示先 |
| heatmap_v12.html | 旧版 | 🔴 | 参考のみ |
| index.html | リダイレクトページ | 🟢 | heatmap_v14.html へ |

---

*更新ルール: 新しいCSV・BT・FW記録・スクリプト・仕様書が増えたらここに追記。*
*削除/凍結したファイルも「参照禁止ゾーン」「旧版」セクションに残し、混入を防ぐ。*
