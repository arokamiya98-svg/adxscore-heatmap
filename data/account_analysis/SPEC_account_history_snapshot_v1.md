# SPEC — Account_History_Snapshot_v1.mq5

> 過去口座の取引履歴を「今の物差し」で測り直すための一括エクスポートScript。
> 作成: 2026-07-13 / ベース: `signals/Trade_Snapshot_Builder.mq5` v1.32（環境スナップショットは列名・ロジックとも完全互換）

---

## 1. 研究目的（絶対固定）

2025年「1万→300万」期の過去分析。

1. **ロット配分**: balance推移に対してロットをどう張っていたか（複利カーブとの関係）
2. **ATR基準へのアプローチ**: 当時のSL/TP設計・エントリーがATR環境のどこで行われていたか
3. **現行戦略との重ね合わせ**: 現行確定周期（H1 ADX32/ATR16-32、H4 ADX46/ATR8-46、D1 ADX22/ATR22-42）の環境ラベルを当時のトレードに後付けし、今のBT/FW資産と同じ土俵で比較する

※勝率向上ツールではない。当時と今のボラティリティ環境の違いを含めた構造理解が目的。

---

## 2. 使い方

1. **対象口座にMT5でログイン**（investorパスワードでも履歴閲覧・エクスポート可）
2. **履歴データの事前ダウンロード**: 対象期間をカバーするように、対象シンボルの H1 / H4 / D1（できれば M5）チャートを開いて過去へスクロールし、ローソクが表示されるところまで読み込んでおく
   - D1のATR median等のため、**対象期間の開始よりさらに2ヶ月前**まで読めていると安全
3. 本Scriptを **MetaEditorでコンパイル**して任意のチャートで実行（チャートのシンボルは何でもOK。指標はdealのシンボルごとに内部生成する）
4. inputs:
   - `Period_From_JST` / `Period_To_JST`: 対象期間を**JST**で指定（デフォルト 2025年まるごと）
   - `Output_Tag`: ファイル名サフィックス（デフォルト "2025"）
5. 出力回収: `MQL5/Files/` から2ファイルを `data/account_analysis/` へコピー
   - `AccountHistory_Enriched_2025.csv` … 1行=1ポジション（メイン）
   - `AccountFlow_2025.csv` … 入出金・クレジット履歴

**実行後チェック**: エキスパートログの `balance 再構成 最終値` が口座の現balanceと一致するか確認。ズレていたら履歴切れ（§5-2）。

---

## 3. 出力列定義 — AccountHistory_Enriched（69列）

### 基本（履歴由来）
| 列 | 内容 |
|----|------|
| position_id | MT5ポジションID |
| symbol / direction / volume | 銘柄 / BUY,SELL / 合計ロット |
| entries / exits | IN/OUT deal数。**entries>1 = 積み増し・ナンピン**、exits>1 = 分割決済 |
| entry_jst / exit_jst / duration_h | 建値・決済時刻（JST）と保有時間 |
| entry_price / exit_price | 加重平均（積み増し・分割決済は平均化） |
| sl_price / tp_price | **エントリーdeal記録時点の初期SL/TP**。空欄 = 未設定（それ自体が当時のアプローチ情報） |
| sl_dist / tp_dist / rr_planned | SL/TP距離（価格差）と設計RR |
| **sl_dist_atr / tp_dist_atr** | ★SL/TP距離をエントリー時点H1 ATR16で割った値。「当時SLをATRの何倍に置いていたか」の核 |
| profit / swap / commission / net_profit | 損益内訳（netが実効） |

### 資金・リスク（★ロット配分分析の核）
| 列 | 内容 |
|----|------|
| balance_at_entry | エントリー直前の再構成balance |
| balance_after | 決済反映後の再構成balance |
| risk_usd | sl_dist × volume × contract_size。空欄 = SLなしで計算不能 |
| risk_pct | risk_usd / balance_at_entry × 100（%） |
| **lot_per_1k** | volume ÷ (balance/1000)。資金1000ドルあたりロット = 配分の正規化指標 |
| result_r | net_profit / risk_usd（R倍数） |
| magic / entry_comment | 0=手動。EA/コピー取引の判別用 |

### 環境スナップショット（28列・trades_enriched.csv と同列名）
`h1_atr16, h1_atr32, h1_atr_ratio, h1_atr_median, h1_atr_ratio_median, h1_atr_zone, h1_adx32, h1_di_plus, h1_di_minus, h1_pattern` / `h4_*`（10列: atr8, atr46, ratio, diff, adx46, di±, cross_bars, cross_dir, phase_auto） / `d1_*`（8列: atr22, atr42, ratio, adx22, di±, cross_bars, phase）

- 取得は**直前確定バー**（Trade_Snapshot_Builder v1.32の未来情報混入対策と同一）
- h1_atr_median = 8週960本中央値（**当時時点のrolling**なので、当時の認識環境を再現）
- ATR Zone: LOW <0.70 / NORMAL / HIGH >1.40
- 全シンボルに現行XAUUSD確定周期を適用（物差し統一の意図）

### MFE/MAE
| 列 | 内容 |
|----|------|
| h1_mfe/mae_usd_48h ほか6列 | 48h固定（エントリーバーの次からH1 48本）。現行マニの部屋と同じ物差し |
| intrade_mfe/mae_usd ほか5列 | **保有期間中**のMFE/MAE。intrade_tf = M5（優先）/ H1（M5履歴なし時のフォールバック） |

### AccountFlow CSV（5列）
`time_jst, type, amount, balance_after, comment`
- type: DEPOSIT / WITHDRAWAL / CREDIT / BONUS / OTHER_n
- **1万→300万が「複利」か「追加入金」かの分解に必須**。CREDIT/BONUSはbalance非算入（equity側のため）

---

## 4. 分析の観点メモ（Mac側でやること）

- balance_at_entry × lot_per_1k の散布図 → 配分ルールの形（固定ロット期/複利期/跳ね期）
- sl_dist_atr の分布 → 当時のSL設計 vs 現行バンド幾何（memory: execution-band-geometry-2026-07）
- h1_atr_ratio_median の当時分布 vs 現在 → ボラ環境の違いの定量化
- entries>1 の頻度と局面 → ナンピン抑制構造（資金管理理論）以前の実態
- h1_pattern / h4_phase_auto 別の成績 → 当時の感覚が現行ラベルのどこを踏んでいたか

---

## 5. 地雷・制約

1. **DST跨ぎ**: JST⇔server変換は実行時オフセット固定。過去の夏冬時間切替を跨ぐと最大1時間ズレる。バー単位の環境取得にはほぼ無害だが、H1バー境界すれすれのエントリーは1本ズレの可能性
2. **履歴切れ**: balance再構成は「MT5から見える全履歴」前提。最初のdealが入金でない場合はWARNを出す。ブローカーが古い履歴をアーカイブしているとbalanceが全体オフセットする（その場合もロット比・リスク%の**相対分析**には使える。絶対額だけ注意）
3. **sl_price/tp_priceは初期値**: エントリーdeal記録時点の値。トレーリングや手動変更の履歴は追わない（初期設計の分析が目的なので仕様）
4. **intrade MFE/MAEのエントリーバー汚染**: エントリーバー自身を含むため、バー内のエントリー前の値動きが混入し得る（M5なら最大5分ぶんで軽微）
5. **1年前のM5履歴**: ブローカー依存。無ければ自動でH1にフォールバック（intrade_tf列で判別可能）。duration が短いトレードのH1追跡は解像度不足なので intrade_tf=H1 かつ duration_h<2 の行は intrade値を割り引いて読む
6. **INOUT（ドテン）**: ネッティング口座特有。ヘッジング口座（HFM系)ではほぼ発生しない。発生していた場合は近似処理
7. **口座番号**: ファイル名にもCSV内にも出力しない（個人情報の線引き 2026-06-19 準拠）
8. **エンコード**: 出力はUTF-8 BOM付き。Python読みは `encoding="utf-8-sig"`

---

## 6. ファイル配置

```
data/account_analysis/
├── Account_History_Snapshot_v1.mq5      ← 正本（MT5のScripts/へコピーして使用）
├── SPEC_account_history_snapshot_v1.md  ← このファイル
├── AccountHistory_Enriched_2025.csv     ← 回収後ここへ
└── AccountFlow_2025.csv                 ← 回収後ここへ
```
