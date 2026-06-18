# VPS実働セットアップ進捗表（別荘の作業台帳）

> 別荘（VPS）は **落ちる前提**（2GB OOM）。落ちても「どこまでできてるか」をこの1枚で即把握する。
> 運用：**節目ごとに更新＆push**（GitHubが本当のバックアップ。VPSローカルが飛んでも残る）。
> 最終更新: 2026-06-18

## 凡例
✅完了 ／ ⏳作業中 ／ 🔲未着手 ／ ⚠️要確認・引っかかり中

## セットアップ手順（上から順に積む）

| # | ステップ | 状態 | テスト（疎通確認） |
|---|---------|------|-------------------|
| 1 | MT5本体インストール | ✅ | `terminal64.exe` 存在＋データインスタンスあり（確認済 6/18） |
| 2 | 通知系（MetaQuotes ID／通知ON／疎通） | ✅ | あろさん「通知クリア」済 |
| 3 | インジ・スクリプト配置（signals/ → MQL5/Indicators・Scripts） | ✅ | ARO配下に現用インジ7＋スクリプト5 配置済（6/17, v4等コンパイル済）※週次収集3本のみ未配置 |
| 4 | インジ稼働＆CSV出力 | 🔲 ← **今ここ** | `MQL5\Files\` に対象CSVが出る（タイムスタンプが更新される） |
| 5 | 日次watcher Windows移植（auto_sync_daily.sh） | 🔲 | パス／`stat -f %m`／python起動 を書換 → 手動1回実行でpipeline通る |
| 6 | watcher永続化（タスクスケジューラ or スタートアップ） | 🔲 | VPS再起動後も自動で立つ |
| 7 | 24h稼働テスト | 🔲 | 1日放置で CSV→pipeline→push が無人で回る／落ちない |

## 落ちたときの復帰3手順
1. このファイルを開く → 最後の ✅／⏳ の **次** から再開
2. `git log --oneline -5` で最終pushを確認（どこまで保存済みか）
3. ⚠️ があればそこが引っかかり中。下の「ステップ別メモ」を読む

## 別荘 安定化メモ
- 2GB OOM。重ければ Win2(3.5GB) へ（縛り無し）。まずは様子見
- RDPは「**切断**」で抜ける（**ログオフ厳禁**＝MT5/Claudeアプリが落ちる）
- 作業の節目で push 癖をつける（落ちる前提の保険）

## ステップ別メモ（引っかかり・決定事項をここに追記）
- 2026-06-18: 進捗表 新設。MT5本体✅・通知✅ 確認済み。
- 2026-06-18: ステップ3 **配置済みだった**（あろさん想定通り）。signals/(repo)12本 = MT5\…\ARO配下12本が完全一致＝**git clone→配置が昨日完了**（VPS本拠地化の狙い「インジ配置=clone一発」が実証）。
  - Indicators\ARO: ATR_WidthSignal_v4(主役ex5✅)/v3bywavelog(比較用,未コンパ)/ATR_Velocity_Rhythm_v2_NoBG/_D1_v1/ATR_Dual_v1/ATR_Ratio_Dual_v1/BarCount_Drawing_v1(補助,未コンパ)
  - Scripts\ARO: ARO_H4PhaseAuto_v1/Signal_Fire_Logger_v1/Trade_Snapshot_Builder/XAUUSD_Daily_Aggregate_v1/XAUUSD_Daily_MFE_MAE_v1（全ex5✅）
  - **週次収集3本(FractalWaveLog D1/H4・ADX_Weekly_Above_v4)はsignals/ミラー対象外**＝VPSに無い。Mac本拠なので日次watcherには不要。VPS週次化する時に別途調達。
  - Files\=空。次=ステップ4（CSV出力）。※CSV出力はMT5 GUI操作＝あろさんの手作業（おぱはMT5を直接操作できない）。
- 別荘運用trap: Mac watcherと同じmainに書き合う。**別荘からpush前は必ず `git pull --rebase`**（6/18に2回reject→rebaseで解消）。
- 2026-06-18: 🎉 **軸A（通知24h化）達成** — VPSで v4シグナルの24h発火を**フォワード確認**。6/16「PCスリープで通知死」問題が根治。VPS導入の第一動機クリア。
- 2026-06-18: 次=**軸B CSV動脈**（あろさん設計: iPhone→iCloud→Mac→Git→VPS→python自動化）。土台は既存（mt5_data/CSV13本＋FX_*.csvが全てgit追跡下／.gitignore除外なし）。設計前提「CSV排出先＆Mac watcherのpush挙動」をMacおぱに調査依頼（コマンド集発行・出力待ち）。
  - 設計論点: ①誰がpushするか ②VPS処理結果の戻し方 ③Mac/VPS境界線。回答が来たらGit合流ロジックを具体設計。
