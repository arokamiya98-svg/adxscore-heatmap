# VPSオパ向け 指示書 — 経済指標フォワード線を VPS の MT5 に常駐表示 v1

> Mac側おぱが用意（2026-08-12）。VPSオパはこれを読んで向こうで設定する。
> 目的: これから来る米指標(Tier別)を VPS の XAUUSD チャート右(未来側)に先出し表示し、
>       24h前線で「来るボラ地形」を常に見える状態にする。指標≠エントリー・環境認知用。

## 前提
- Mac側で実装・push済み（commit `8624c2d`）。VPSは `git pull` で受け取れる。
- 対象インジ本体: **`data/bt/Econ_Event_Lines_Forward_v1.mq5`**（フォワード＝現場用）
  - 参考: `data/bt/Econ_Event_Lines_History_v1.mq5`（過去分析用・任意）
- データ源 = MT5内蔵カレンダー(`CalendarValueHistory`, USD)。**サーバー時間＝価格と同一系**。
- Tier根拠 = `data/bt/EVENT_VOLATILITY_RANKING_v1.md`（実測ボラ順 S/A/B）。

## セットアップ手順（VPS上で）
1. **pull**: `git pull --rebase --autostash origin main`（着手前作法。UUチェックも）
2. **配置**: `data/bt/Econ_Event_Lines_Forward_v1.mq5` を VPSのMT5データフォルダ
   `.../MQL5/Indicators/` にコピー（実パスは VPS環境で確認。TERMINAL_DATA_PATH配下）。
3. **コンパイル**: MetaEditorで開く → **F7**（.ex5生成。※.ex5直置き不可、必ずF7）。
4. **適用**: XAUUSD **H1** チャートにドラッグ。
5. **input推奨値**:
   - `InpDaysAhead=3`（直近3日先出し）
   - `InpShowTierS/A/B = 全部 true`（全Tier盛り）
   - `InpForceChartShift=true`（右に未来空間を自動確保＝フォワード表示に必須）
   - `InpRefreshMin=30`（30分ごと自動再描画・過ぎた線は自動除去）
   - `InpShowValue`（任意ON＝予想値/前回値ラベル）

## 動作確認
- 右のシフト空間に縦線が立てばOK: 🟧濃オレンジ太=Tier S(NFP/CPI/FOMC) / 🟡金細=Tier A / ⚫灰点線=Tier B(ISM)
- エキスパートログに `[FWDEVT] 先出し縦線 N本…` が出る。

## カレンダー未提供だった場合（最重要チェック）
- ログに `[FWDEVT] 未来カレンダー取得0 / err=…` ＝ **VPSのブローカーが経済カレンダー未提供**。
  - Mac側ブローカーは提供あり（10,738件取得実績）。VPSが別口座/ブローカーなら空になり得る。
  - その場合の代替（Mac側おぱへ差し戻し）: ①Macが吐いた履歴CSVを読む版に改修 / ②外部フィード。
  - まず「縦線が出るか」で提供有無を判定 → 結果をあろさんへ報告。

## 地雷（VPS運用の作法・CLAUDE.md §15）
- RDPは必ず**「切断」**で抜ける（ログオフ厳禁＝schtasks/常駐が止まる）。
- チャートシフトはインジが自動ON（既にONなら無害）。
- このインジは**表示専用**（ファイル出力なし・pushしない）。VPSの日次動脈CSV(②③)には一切触れない。
