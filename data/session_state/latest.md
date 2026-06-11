# 次セッションへの引き継ぎ（2026-06-12 終了時点）

## 🎯 今日（6/11〜12）の最大の収穫

**シグナル検証シート誕生 → 日次認識カレンダー v3 完成。3枚体制 + 全自動パイプライン確立。**

そして最重要の言語化2つ：
1. **「解析より認知負荷を下げて戦略実行精度を上げる」が今の主軸**（メモリ化済み）
2. **結果 vs 因果の切り分け**：日次レベルの評価（結果）と戦略で見る D1 ADX（因果）は別物。日次カレンダーは「相場の結果×トレードの結果×シグナルの結果」の見比べ

---

## 📦 主要成果物

### mq5（コー案件）
- `signals/Signal_Fire_Logger_v1.mq5` **新規** — v4の発火を2025-03〜全件再現（Script型、64列×389発火）
  - フィルターF1〜F9はラベルのみ（除外しない）、pass_all=265
  - v4実機矢印と3点照合済み（時間=server表記、価格=バーclose、完全一致）
  - MT5 Scripts/Examples 配置済み・実行確認済み
- C4-B 完了: `XAUUSD_Daily_MFE_MAE_v1.10` 実行 → 24列CSV確認（C4データ完全に揃った）
- C6 判定済み・修正は保留: Daily_MFE_MAEの「14:00」表記は実態15:00エントリー（計算は自己整合、ラベルのズレのみ）。修正案: ①iOpen化 ②ラベル15:00化

### Python/HTML（マニ案件）
- `scripts/generate_signals_calendar.py` **新規** → `signals_calendar.html`
  - v1: シグナル検証カレンダー → v2: **統合評価シート**（実トレードカード統合）
  - 役割確定: **シグナル×トレードだけの見比べページ**（保存版）
- `scripts/generate_daily_calendar_v3.py` **新規** → `daily_calendar_v3.html` ★本丸
  - 経緯: スクラッチ版（H1色・情報削減）→ あろさん実見「v2よりだいぶ弱い」→ **v2ベースに移植転換**
  - 最終形: v2の強み（H4戦略背景×MFE/MAE結果バー×具体数字）完全保持 + シグナルドット行 + セルクリック→ドロワー（シグナル+実トレードカード、MFE/MAE 12/24/36/48h同一フォーマット）+ SC表記削除
  - Step2: fireCard閉じdiv漏れ修正（opacity入れ子事件）/ フィルターデフォルトON（pass265のみ、トグルで389）/ 期間=トレードログ基準2026-03〜直近6ヶ月+過去折りたたみ

### パイプライン（おぱ案件）
- `PIPELINE.md` **新規** — 全体図一枚まとめ（ページ4枚の役割・トリガー別フロー・watcher運用・mq5在庫）
- `run_daily_calendar.sh` 拡張: Step 2b(signals) + 2c(v3) + docs3枚ミラー + **自動publish**（commit+push）
- `auto_sync_daily.sh` 拡張: FX_*.csv新着検知→trade_input自動配置 / signal_fires.csv監視追加
- **トレード後の手数は2アクションに**: ①アプリCSVを置く ②MT5でSnapshot_Builder実行 → あとは iPhone反映まで全自動
- GitHub Pages 公開3枚: trades_calendar / signals_calendar / daily_calendar_v3（公開URL: arokamiya98-svg.github.io/adxscore-heatmap/）

---

## 🔑 確定した設計判断（変更しないこと）

- **v3の構造**: 背景色=戦略文脈(H4) × バー=結果(MFE/MAE)の対比。H1色化は失敗済み（両方結果系になり対比消失）
- **トレード帯（++59k形式）は現状維持確定**（バー化中止。「大きく拾えたか直感で分かる」）
- **土曜発火は金曜セル併載**（点線下線+土マーク）承認済み
- **ルーティン（週次・必ず）と検証（不定期・Fire Logger）の切り分け**
- 旧版保存義務: generate_daily_calendar.py / trades_calendar.html / generate_signals_calendar.py / signals_calendar.html の4ファイルは将来用途のため変更禁止
- mani_room データの public 公開はあろさん承認済み（個人情報なし確認済み）

## 🛡️ 番人の学び（再発防止）

- **マニの検証出力義務化が機能してる**（「確認した」だけ不可、コマンド+出力貼付）。今回も番人レビューで全件独立裏取りした
- fireCard閉じdiv事件: innerHTML入れ子でopacity継承 → HTML断片を返す関数は閉じタグまで検証
- mq5更新時は MT5 Scripts/Examples へのコピー+再コンパイル必須（v1.10配置漏れで旧版実行事故があった）

---

## 🚀 次セッションのアクション候補

### A. v3 実見継続調整（一歩ずつ方式・あろさん主導）
- Step2まで反映済み。次の「一歩」はあろさんの実見フィードバック待ち
- 既出の調整候補: 情報精査の対話（削る作業）

### B. 保留中の小物
- **C6修正**（Daily_MFE_MAEの14:00/15:00ラベル問題。軽い、コー or おぱ直）
- スコアのD1整合ボーナスバグ（BULL/BEAR表記不一致で日次採用日は常に0点。v2.0から潜在・温存中）

### C. 次の弾（あろさん言及済み・未着手）
- **H4インジ**: v4の時間軸拡大版（H4で方向期待値）。「次のステップ」枠
- 詳細フィルター専用ページ（PatA×期間、BU期等。signals_calendarベース複製で）
- C3（v4リアルタイム発火ログ）は Fire Logger で実質代替された感あり、要再判断

### D. 定例
- 週次ルーティン（金〜月）: MT5 4本 + ./run_pipeline.sh
- 8月集中メンテ（フィルター調整・PatA可視化等はここ）

---

## ⚠️ 運用メモ

- watcher 起動: `nohup ./auto_sync_daily.sh &> auto_sync.log &` / 停止: `pkill -f auto_sync_daily.sh`（Mac再起動後は手動起動が必要）
- パイプライン全体像は **PIPELINE.md** 参照（一枚で全部わかる）
- enriched/signal_fires 系CSVは必ず `encoding="utf-8-sig"`
- 自動publishが有効: カレンダー再生成のたびに docs/ 3枚が commit+push される（オフライン時はスキップ、次回pushで反映）

## 🧠 今日追加したメモリ

- `feedback_cognitive-load-reduction-is-the-axis` — 認知負荷低減が主軸。足すより絞る、シグナル系と実行系は同一視覚言語
- `project_scriptable-widget-operational` — Scriptable運用確立、Phase 6実質クローズ、MT5厳密整合の改修不要

---

*このファイルは SessionStart hook で自動的に次セッションの Claude に注入される。*
*次セッションの起点 = 「v3実見フィードバックの次の一歩」or「C6/H4インジ等の次の弾」*
