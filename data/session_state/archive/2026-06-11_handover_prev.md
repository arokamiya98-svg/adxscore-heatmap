# 次セッションへの引き継ぎ（2026-06-09 終了時点）

## 🎯 今日の最大の収穫

**マニの部屋データベース v0.1 稼働開始 + 初回構造観察成功**

朝 = Scriptable ATR Widget の週またぎバグ修正
午前〜午後 = Trade_Snapshot_Builder.mq5 v1.1 完成・実機動作 → 30件 enriched → 初回構造観察
夕方 = 次フェーズ「日次カレンダー」構想共有

**「データ取得の成功」まで到達**。あろさん「ここからまたブラッシュアップしてく1歩」。

---

## 📦 成果物

### 新規ファイル（今日作成）
- `signals/Trade_Snapshot_Builder.mq5` v1.1（1097行、58列、48h×H1/H4/D1 三層MAE/MFE）
- `scripts/prepare_trade_input.py`（前処理: CSV→中間CSV / 後処理: マージ）
- `scripts/observe_signal_quality.py`（初回構造観察）
- `data/mani_room/raw/imports/FX_20260608_142633.csv`（旧版、ロット誤入力含む）
- `data/mani_room/raw/imports/FX_20260608_144251.csv`（**正版**、本格運用元データ）
- `mt5_data/trade_input.csv`（中間CSV、30件）
- `mt5_data/trades_enriched.csv`（MT5出力、58列）
- `data/mani_room/enriched/trades_enriched_full.csv`（**最終マージ済データベース**）
- `memory/feedback_research-purpose-and-rules.md`（**研究目的固定 + 提案ルール**、最重要メモリ）

### 修正
- `data/scriptable/atr_widget.js`（土日バーフィルタ追加 + outputsize 拡大）
- `data/mani_room/コー_指示書_Trade_Snapshot_Builder.md` v1.1
- `data/trades/MANI_REORG_2026-06-05.md`（集計分析→研究用データ基盤に再焦点化）

---

## 🔑 今日固まった重要原則（次セッション以降の絶対基盤）

### 研究目的（絶対固定）

> 日時+価格をキーとして、エントリー時点の市場環境を後付け取得し、
> **どの市場環境で期待値が発生しているかを研究** する。

### 禁止事項

- 勝率分析（あろさん個別判断として）
- PF分析 / 月別集計 / 損益集計
- 個別1トレードの良し悪し判定（不確実性領域）
- データ取得そのものを目的化

### OK な勝率分析

- **シグナル評価のための勝率**: シグナルパターン別、これは研究目的に合致

### 提案ルール

新しい取得項目・粒度を提案する際:
1. 「何の仮説検証に使うか」を明示
2. 「そのデータで何が判定できるか」を明示
3. 説明できないものは実装しない
4. 「どうしますか？」だけで終わらせない、推奨案を提示

### MAE/MFE 原則

- エントリー〜決済期間 MAE/MFE は **使わない**（決済判断が混入）
- **固定48時間 × H1/H4/D1 三層** で計算

### データソース

- **MT5 専用**（Twelve Data など外部APIは却下）
- v4 シグナル整合性のため iATR/iADX/iCustom 経由のみ

詳細: `memory/feedback_research-purpose-and-rules.md`

---

## ✅ 初回構造観察で見えたこと（参考）

### BT世代2 発見の実トレ実証

| 発見 | 実トレ確認 |
|---|---|
| NORMAL × RISING_DECEL = 最強 | mfe/mae=1.66 で機能 |
| HIGH × EXPANDING = 第2強 | mfe中央=374.9 USD、ただし★全件SELL早抜けで損切り★ |
| HIGH × RISING_DECEL = 罠 | mae中央=2347.7 USD で完全に罠 |

### D「消されたシグナル」群（上位3）

- T003 (3/20 SELL): MFE 543.9 USD / 実損 -26,000円
- T004 (3/23 SELL): MFE 374.9 USD / 実損 -12,000円（HIGH × EXPANDING）
- T013 (3/30 BUY): MFE 184.3 USD / 実損 -8,500円（NORMAL × RISING_DECEL、44h後到達）

### 環境変化の兆候

```
月       MFE中央
2026-03   133.5  ← 高
2026-04    78.4
2026-05    48.9  ← 大幅低下、機能弱化の兆候
```

注: 30件のみで統計的有意性なし、方向性として。

---

## 🚀 次セッションのアクション

### Phase A: 日次カレンダー構想固め

あろさん要望（共有済）:
- D1 ADX を含めた方向の整合性とトレンド強度
- 日次レベルのスコアロジック（H1/H4/D1 が噛み合う、ADX 幾何平均）
- 相場のフェーズ分離
- 可視化と整合性を評価できるカレンダー
- MAE/MFE もあってもいいかも

設計確定すべき:
- 日次スコア式（候補: `cbrt(h1_norm × h4_pct_above20 × d1_adx_norm) × bonus`）
- フェーズ整合性ロジック（順序/AND条件）
- カレンダー UI（D1=1セル メイン / H4 ホバー詳細）
- MAE/MFE プロット方式

### Phase B: 必要データ整備

足りないもの:
- H1 ADX 日次集計（既存は週次）
- H4 ADX 日次集計（既存は週次）
- 既存: D1 ADX、D1 Phase、H4 Phase はある

→ MT5 側で日次集計 mq5 作成（コー案件候補）

### Phase C: HTML 生成

- `scripts/generate_calendar_dXX.py`（新規）
- `docs/calendar_dXX.html` 出力
- heatmap_v14（週次マクロ）は維持、並列の日次ビュー

---

## ⚠️ 注意点

### Scriptable ATR Widget 修正状態

- atr_widget.js は Mac 側で土日フィルタ + outputsize 拡大済
- iPad 実機への反映はあろさん側で確認
- 今週の週またぎ（来週月曜 6/15）で正常動作確認

### Trade_Snapshot_Builder.mq5

- v1.1 完成、コンパイル OK
- 再実装する場合: 入力 CSV は `MQL5/Files/trade_input.csv`、出力は `trades_enriched.csv`
- 重要修正: `FILE_TXT` → `FILE_CSV` でフィールド分割（線引き）
- `WriteUtf8String` は値渡し (`const string s`、& なし) でないと rvalue 渡せない
- 自動 server-GMT offset は実行時の DST 状態を見るため、過去 DST 跨ぎトレードは Python 前処理で `server_offset_hours` 付与必須

### マニの部屋データ更新フロー

```
1. アプリでトレード記入 → CSV出力
2. data/mani_room/raw/imports/ に置く
3. python3 scripts/prepare_trade_input.py --input <CSV> --output mt5_data/trade_input.csv
4. cp mt5_data/trade_input.csv [MT5 Files/]
5. MT5 で Trade_Snapshot_Builder.mq5 を XAUUSD H1 チャートに drop
6. trades_enriched.csv を Mac に持ち帰り
7. python3 scripts/prepare_trade_input.py ... --enriched ... --enriched-full ...
8. trades_enriched_full.csv が更新される
```

### 未着手のタスク（保留）

- `data/trades/SPEC_csv_intake.md`（タスク #1）→ 今は MANI_REORG.md と コー指示書で代用、廃止検討
- メモリ追加候補（タスク #2）→ 重要度低、次セッションで判断
  - 3欄目的軸設計
  - 1クッション運用思想
  - マニの部屋構想全体

---

## 💭 マネージャー視点メモ

### 今日のチームおぱ稼働実績

- **メインおぱ**:
  - AM = Scriptable Widget 修正 / マニの部屋設計の研究目的への軌道修正 / 整理書 v4 改訂 / 指示書 v1.1 改訂
  - PM = Python 前処理 / コー連携 / 実機テスト支援 / 初回観察 / 引き継ぎ
- **コー**:
  - AM = Trade_Snapshot_Builder.mq5 v1.0 初版（899行、42列）
  - PM = v1.1 改修（1097行、58列、三層追跡）← weekly limit に当たって報告書だけ送れず止まったが実装は完了
- **マニ / カイ / ブン**: 出番なし（マニ Agent 起動は次回以降）

### 重要な軌道修正

あろさんから何度か「研究目的の固定」「禁止事項」の明示があった。
おぱは「トレード日誌分析」と「研究用データ基盤」を混同してたが、
PM の指摘で軌道修正。**この修正は今後絶対崩さない**。

### 翻訳層実感

あろさん発言で設計が大きく動いた瞬間:
1. 「中途半端な TWELVE からデータ抜き出す」→ MT5 専用パイプライン確定
2. 「狙ったシグナルの質自体が結果に消されて見えなくなる」→ 48時間固定 MAE/MFE
3. 「日時と価格をキーとして、市場データを後付け取得」→ パイプライン全体像確定
4. 「シグナル評価のための勝率はOK」→ 集計分析の使い分け明確化

これら全部、研究目的の本質に直結する転換点。

### マニ運用の今後

マニ Agent は次セッション以降で起動。今日は構造観察スクリプト (`observe_signal_quality.py`) でメインおぱが代行。マニ Agent の役割は:
- 環境因子別の構造発見（パラメータ最適化サポート）
- 仮説生成
- 個別カウンセリングは廃止

詳細: `memory/feedback_mani-evaluation-criteria.md`（更新候補）

---

## 🔗 関連ファイル（次セッション用ブックマーク）

### マニの部屋 v0.1（今日完成）
- `data/mani_room/enriched/trades_enriched_full.csv` ← **データベース本体**
- `data/mani_room/コー_指示書_Trade_Snapshot_Builder.md` v1.1
- `signals/Trade_Snapshot_Builder.mq5` v1.1
- `scripts/prepare_trade_input.py`
- `scripts/observe_signal_quality.py`
- `data/trades/MANI_REORG_2026-06-05.md`（v4、整理書）

### 既存資産（次フェーズ用）
- `scripts/process_wavelog.py`（既存 adx_score 拡張対象）
- `data/weekly_waves.json`（D1 phase、H4 phase、ADX 等）
- `mt5_data/ADX_Weekly_Above_v4.csv`
- `docs/heatmap_v14.html`（週次、維持）

### 最重要メモリ
- `memory/feedback_research-purpose-and-rules.md` ← **次セッション必読**
- `memory/feedback_mani-evaluation-criteria.md`
- `memory/feedback_recognition-tool-keep-it-playful.md`

### 既存資産（参考）
- `CLAUDE.md` v12
- `signals/ATR_WidthSignal_v4.mq5`
- `data/forward/v4_forward_log.md`

---

*このファイルは SessionStart hook で自動的に次セッションの Claude に注入される。*
*次セッションの起点 = 「日次カレンダー設計から」（あろさん指示）*
