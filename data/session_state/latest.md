# 次セッションへの引き継ぎ（2026-06-18 別荘セッション②：VPS無人化 設計確定）

## 🎯 今日の総括
別荘（VPS）でおぱ起動2日目。**軸A（通知24h化）の達成確認**から始まり、**Macおぱ会議**を経て**VPS無人化の設計を確定**。あろさん判断で「情報の鮮度で設計実装に突っ込む」のはあえて避け、**引き継ぎ＋今後フローの整備に注力**。次セッションが系統B EA化からスムーズに走れる状態を作って店じまい。

## ✅ 今日の到達点
1. **別荘 健康診断**: MT5本体✅／インジ配置✅（**git clone→配置が完璧**を実証＝本拠地化の狙い達成）／通知✅
2. **落ちる別荘対策**: 進捗台帳 `data/session_state/vps_setup_progress.md` ＋設計書 `data/vps/VPS_UNMANNED_DESIGN.md` をGit退避。運用＝**節目ごとpush**（落ちてもGitHubに残る）
3. 🎉 **軸A 通知24h化 達成**: v4の24h発火をフォワード確認 → 6/16「スリープで通知死」**根治**
4. **VPS無人化 設計確定**（↓）
5. **メモリ実態判明**: 圧迫主犯は**Claude Code自身**(claude5プロセス/Commit約2.5GB)。MT5は軽い(Commit162MB)。→ **EA無人化は2GBで着手可**。Win2はおぱ常駐用

## 🏗 VPS無人化 設計（確定）→ 詳細 `data/vps/VPS_UNMANNED_DESIGN.md`
- **核心**: CSVは「運ぶ」でなく「**VPSのMT5でEA化してその場生成**」（旧CSV-via-Git案を上書き）
- **日次3系統**: A=トレード後付け(**Mac専管**)／B=日次集計(**VPS EA化**)／C=signal_fires(**VPS EA化★最重要**)
- **順番**: B(練習・入力不要)→C(本命・軸Aシナジー・フォワード完全化)→A(後回し)
- **Git合流**: push対象が VPS=日次HTML / Mac=週次HTML で**分離→衝突ほぼ無**。`weekly_waves.json`だけ要片寄せ。`mt5_data`はMac専管

## ▶ 次セッションの起点 ＝ 系統B（Daily_Aggregate）EA化
1. GUI前提クリア済み（**AutoTradingは緑にできる**／XAUUSD気配更新OK）
2. おぱが `signals/XAUUSD_Daily_Aggregate_v1.mq5` を読む → **Script→EA化**(OnStart→OnInit+OnTimer)の青写真
3. 実装はコーへ指示書
4. signal_fires実装2案（Signal_Fire_Logger EA化 vs **v4に発火時CSV追記**）→ コード突き合わせで決定

## 🔧 別荘 運用フロー（今日確立）
- **作業時（おぱと作業）はMT5を一時的に閉じる** → メモリ確保（おぱが約2.5GB食う）。**作業後にMT5を開いて軸A再稼働**。※閉じてる間は24h通知が止まる
- **別荘からpush前は必ず `git pull --rebase`**（Mac watcherと同mainに書き合う＝競合調停。今日2回reject→rebaseで解消）
- **パラレルおぱ運用**: VPS⇔Mac⇔GitHub で交信。Mac側は半自動watcher稼働中。情報が要る時は `git pull` で最新取得（pushされた物だけ見える）
- RDPは「**切断**」で抜ける（**ログオフ厳禁**）

## ⚠️ 注意点
- VPS 2GB: MT5は軽い。EA無人化は2Gで可。Win2(3.5GB)はおぱ常駐の快適性用（**今すぐ不要**、EA実測後に判断）
- 週次HM（WaveLog手描き起点）は**Mac本拠維持**

## 📋 積み残し
- **系統B/C EA化**（次の本命）
- weekly_waves.json 片寄せ方針 ／ mt5_data・.DS_Store の .gitignore（設計確定後・慎重に）
- Win2判断（EA実測後）
- **【Mac側・前回宿題】** watcher再起動後の自動起動検証（`pgrep -lf auto_sync_daily.sh` → 無ければログイン項目 `ADXSCORE_Watcher.app`）

---
*次の起点＝系統B（Daily_Aggregate）のEA化設計。おぱが mq5 を読んで Script→EA 青写真→コー実装。作業時はMT5閉じる運用。*
