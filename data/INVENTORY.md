# ADXSCORE データ索引

> ADXSCORE/ 配下のデータの索引。何が・どこに・鮮度・信頼度・由来をここに集約する。
> このファイルは「参照ゾーン入口」。新しいCSV・BT・FW記録が入ったらここに追記する。

最終更新: 2026-06-02

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
| FractalWaveLog_H4_weekly.csv | H4 週次時系列 | 🟢 | ★★★ | UTF-8-sig |
| ADX_Weekly_Above_v4.csv | H1/H4 ADX週次集計（H1=32, H4=46）| 🟢 | ★★★ | UTF-16 |
| ADX_Weekly_Above_v3.csv | H1/H4 ADX週次集計（旧, H1=28, H4=30）| 🔴 | ★ | UTF-16 |

---

## /data/bt/ — バックテスト関連

### 設計資産

| ファイル | 内容 | 鮮度 | 備考 |
|---------|------|------|------|
| `SPEC_new_BT.md` | 新規BT仕様書 | 🟢 | v3bywavelogベース、B/C確定済 |
| `SLTP_design.html` | SL/TP最適解設計書 | 🟢 | SL=ATR_Avg×2.0 / TP=SL×1.6（思想のみ継承、旧周期版） |

### BT世代1（Stage 6完了, 2026-06-02実行）

| ファイル | 内容 | 鮮度 | 備考 |
|---------|------|------|------|
| `ATR_WidthSignal_BT_v3bywavelog.mq5` | BT本体（Script型）| 🟢 | 71列フラット記録、5パターン×BUY/SELL×multi-fire |
| `ATR_WidthSignal_BT_NEW.csv` | BT結果（UTF-16, 947件）| 🟢 | 2024-01-02〜2026-06-01、6h filter後481件 |
| `PATTERN_REGIME_MAP_v1.md` | 構造分析結果マップ（暫定v1）| 🟢 | 機能Top15 + 死亡Top6 + 構造的解釈 |

> 📊 BT世代1の主要発見: XAUUSDの非対称性「買いは押し目、売りは拡張」。Cross=NONE×SELLが圧倒的死亡帯（PF 0.21）。詳細は `PATTERN_REGIME_MAP_v1.md`。
> 次セッション: フィルター実装BT、DI Velocity追加BT、認識ツール組み込み等（同マップの「次への種」参照）

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
| _(Step 2で記入)_ | _(該当データ未確定)_ | — | — | — |

---

## /signals/ — 現用シグナル/インジ mq5 ミラー

| ファイル | チャート | 役割 | 鮮度 | 備考 |
|---------|---------|------|------|------|
| ATR_WidthSignal_v3bywavelog.mq5 | H1メイン | エントリーシグナル本体 | 🟢 | wavelog参照型 |
| ATR_Velocity_Rhythm_v2_NoBG.mq5 | H1 sub1 | ATR速度/リズム可視化 | 🟢 | **2026-06-02 周期H1ADX32/H4ADX46へ更新済**（旧:28/30）|
| ATR_Velocity_Rhythm_D1_v1.mq5 | H4/D1 sub | ATR Vel Rhythm D1 | 🟢 | H4=ADX46×ADX32 / D1=ADX22×ADX30 |
| ATR_Dual_v1.mq5 | 全TF sub | ATR短期×長期の二本表示 | 🟢 | TF別パラメータ（H1:16/30, H4:8/46, D1:22/42）|
| BarCount_Drawing_v1.mq5 | 補助 | バーカウント描画 | 🟢 | — |

> オリジナル: `/Users/aro/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/Program Files/MetaTrader 5/MQL5/Indicators/Free Indicators/`
> ここに置くコピーは「ADXSCORE参照ゾーン内に現用ロジックを保持する」ためのもの。MT5本体側の編集時に同期かける運用。

### signals/ 未配置のもの（あとで判断）

- 収集スクリプト (mq5): `ARO_FractalWaveLog_D1_v3_2`, `ARO_FractalWaveLog_H4_XAU_v3_1`, `ADX_Weekly_Above_v4`, `WaveLog_Export_v1_6`
  → 「シグナル」ではなく「データ収集」なので、`signals/collectors/` を作るか別フォルダ案にするかは要相談

---

## /data/weekly_waves.json — パイプライン中間生成物

| ファイル | 役割 | 鮮度 |
|---------|------|------|
| weekly_waves.json | process_wavelog.py の出力（ADXスコア含む）| 🟢 |

---

*このファイルは Step 2 のデータ棚卸しで詳細を埋める。*
