# 次セッションへの引き継ぎ（2026-06-19 別荘セッション⑤：日次動脈 設計フィックス）

## 🎯 今日の総括
別荘（VPS）でおぱ起動5日目。系統B・Cで「CSVその場生成」を終えた次の一手＝**日次動脈（EA生成CSV→pipeline→HTML→push）の設計を集中して仕上げ、さらにVPS側フェーズ0実装＋フェーズ2予行（push認証・EA出力・DRY_RUN確認）まで完了した**。成果物は設計書 **`data/vps/日次動脈_DESIGN_v1.md`**（11セクション・叩き台スクリプト/タスクスケジューラ/実装順序込み）＋ **`scripts/vps_data_pool_push.sh`**（配置・構文OK・まだ動かさない / commit 4eddfab）。あろさんとの対話で核心思想と.gitignore線引きを決め切り、おぱのセルフレビューで順序の穴も潰した。**残りはフェーズ1（Mac・無停止移行）から**——設計の安全原則「daily/移動とMacパス変更は同一コミット群」を守るため、VPS単独で③を先行させずここで意図的に停止。

## ✅ 今日の到達点
1. **現状調査で「動脈は9割完成・切れ目は3つだけ」と判明**：① VPS用sync無し（Mac版syncは週次6本＆Macパスのみ）② ジェネレータ出力先 `data/trades/` がgitignore＆VPSに不在 ③ processed→docs→push は実は `run_daily_calendar.sh` Step2.5/2.6 が**既に自動化済**（手動コピーではなかった）。
2. **核心思想を確定**：VPS=データプール製造（全自動・成績ゼロ）／Mac=成績合流（個人情報側）／git=合流点。トレード成績(`trades_enriched`)はiPhone由来で `data/trades/`(gitignore)にしか無くVPS不在＝VPSは構造的に純データ生産に徹する。
3. **CSV3分類で.gitignore線引き決着（あろさんの指摘が設計を救った）**：①手描き波形(FractalWaveLog)=gitignore・Macローカル ②自動集計(ADX_Weekly/H4PhaseAuto)=**追跡維持**（ADXスコア計算元・手描き不要→将来VPS化候補）③日次(signal_fires/daily_aggregate/daily_mfe)=`mt5_data/daily/`分離・VPS push。当初おぱは②を①と一緒くたにignoreしかけた→あろさんが「ADX_Weeklyは手書き関係ない自動スコア系」と訂正。
4. **rebase衝突を構造的に根絶**：①管理外／②Mac commit（`run_pipeline.sh` Step5にadd追加でM放置解消）／③VPS commit → `mt5_data/`常時クリーン。
5. **個人情報の線引き確定（あろさん）**：NGは具体的な口座番号のみ。成績/ロジック/損益/ロットは公開OK→ docs/カレンダー公開はこのまま継続。
6. **セルフレビューで順序の穴を修正**：daily/移動とMacパス変更を別フェーズにすると移行中Mac側が壊れる→**無停止移行（同一コミット群）**に組み替え（§9）。

## 🏗 設計の成果物
- 設計書: `data/vps/日次動脈_DESIGN_v1.md`（11セクション・schtasks登録コマンド追記済）
- スクリプト: `scripts/vps_data_pool_push.sh`（**配置済・構文チェックOK・実行はフェーズ2**。MT5 Files→daily/→pull --rebase→add daily/のみ→commit→push）
- sync対象確定: 無印3本（`signal_fires`/`daily_aggregate`/`daily_mfe_mae_48h`）。`_EA` suffixは回帰検証名残（無印とdiff0）→掃除対象
- タスクスケジューラ: `C:\Program Files\Git\bin\bash.exe -lc "..."` / 叩き台1日2回(JST08:10/23:10)・要調整

## ▶ 次セッションの起点 候補
1. **日次動脈の実装 フェーズ1から**（本命）：フェーズ0(VPS `vps_data_pool_push.sh`配置)は**完了済**。次は **フェーズ1=Mac無停止移行**（Macおぱに「設計書フェーズ1を実装」と依頼：daily/へ③をgit mv＋FractalWaveLogを.gitignore/rm --cached＋generate_*.py/run_daily_calendar.shのパスをdaily/へ＋run_pipeline.sh Step5に②add追加 → **全部1コミットでpush**）→ フェーズ2(**予行済:bash経由git認証/EA出力/DRY_RUN 全てOK**・本番は `bash scripts/vps_data_pool_push.sh` 手動テスト→§7 schtasks 2行登録・実行条件は「ログオン中のみ実行」推奨)→ フェーズ3(通し検証)。
2. **②のVPS化**（将来の大トラック）：ADX_Weekly/H4PhaseAutoのEA化（系統B/C方式）→データプール拡大
3. **運用観察**：EA2本常駐のメモリ実測 → Win2(3.5GB)判断

## 🔧 別荘 運用フロー（継続）
- 作業時はMT5を一時的に閉じる→メモリ確保。作業後MT5開いてEA/軸A再稼働
- 別荘からpush前は必ず `git pull --rebase`
- RDPは「切断」で抜ける（ログオフ厳禁）
- コー実装EAは必ず MetaEditor F7 再コンパイル（.ex5コマンドラインはロード不可＝556）
- リポジトリ`signals/`が正本 → MT5 `Experts\ARO\`（EA）/ `Scripts\ARO\`（Script）へコピーしてF7

## 📋 積み残し
- 日次動脈の**実装**（設計完了・上記①）
- 系統A（Mac専管・後回し）
- ②のVPS化（将来）／Win2(3.5GB)判断（EA2本常駐メモリ実測後）
- **【Mac側・宿題】** watcher自動起動検証（`pgrep -lf auto_sync_daily.sh`）／実装フェーズ1のMacパス変更（generate_*.py / run_daily_calendar.sh を `daily/` へ）
- **【PUBLIC個人情報】** 今日push分（設計書）は個人情報なし。NGは口座番号のみと確定済

---
*次の起点＝日次動脈の実装（設計書 `data/vps/日次動脈_DESIGN_v1.md` フェーズ0〜3）。フェーズ1は無停止移行＝daily移動とMacパス変更を同一コミット群で。または②のVPS化。.ex5はF7必須。*
