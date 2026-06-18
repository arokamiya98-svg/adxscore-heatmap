# 次セッションへの引き継ぎ（2026-06-18 続き：半自動更新化 Mac側2本完成）

## 🎉 今日の達成 — GOAL「半自動更新化」のMac側差分を完全に埋めた

### 1. 週次watcher 実装（auto_sync_daily.sh に追加）
- 週次CSV7本（FractalWaveLog D1/H4・ADX_Weekly_v4・H4PhaseAuto等）を監視対象に追加
- 検知→**10秒デバウンス**→`run_pipeline.sh --no-open` 自動実行（heatmap生成→iCloud→push）
- 「WaveLogライン引き→MT5週次4本回す→勝手に週次HM最新版＆push」が成立
- ※既存の日次ロジックは無傷、週次ブロックを足しただけ

### 2. iCloud入口 橋渡し実装（AirDrop廃止）
- 入口：`iCloud Drive/ADXSCORE/imports/`（iPhone↔Mac一致を実証済み）
- watcherに `sync_icloud_imports()` 追加：iCloud ADXSCORE配下のFX_*.csv（直下/imports両対応 maxdepth2）→ ローカル `data/mani_room/raw/imports/` へ橋渡し→既存処理に合流
- **一気通貫 実証済み**：FX_20260618_125439.csv が iPhone保存→iCloud→Mac→ローカルimports まで通った

### 3. watcher永続化（ログイン項目方式・TCC回避）
- **launchd plist はTCCで失敗**：`~/Desktop`保護でlaunchd経由bashが弾かれる（ログ証拠：Sandbox deny + posix_spawn "Operation not permitted", exit78）。plistは `~/Library/LaunchAgents/com.aro.adxscore.watcher.plist` に残置だが**使わない**
- **解決＝ログイン項目方式**：`~/Applications/ADXSCORE_Watcher.app`（osacompile製、pgrepで二重起動防止）をGUI起動→TCC許可→watcher起動。**ログイン項目に追加済み**
- 起動確認済み：13:36 監視開始、週次7本監視＋iCloud入口認識

## 🔁 再起動後の検証（あろさんが再起動する→次セッション最初にここを確認）
1. `pgrep -lf auto_sync_daily.sh` → `/bin/bash ./auto_sync_daily.sh` が立ってるか
2. `tail -15 ~/Desktop/ADXSCORE/auto_sync.log` → 「監視開始」が**再起動後の時刻**で出てるか／「週次CSV 7本を監視」
3. 立ってなければ：システム設定>一般>ログイン項目に `ADXSCORE_Watcher.app` があるか確認、or `open ~/Applications/ADXSCORE_Watcher.app` で手動起動
→ 立てば「**消さない限り起動・再起動で自動起動**」完成（あろさんの要望クローズ）

## 🎯 GOAL残り = VPS常駐化（次回の別荘作業）
- Mac側は完成。残るは「Macスリープで止まる」を埋めるVPS 24h化
- `auto_sync_daily.sh` をVPS(Windows Server)へ移植：パス（`/Users/aro/Library/...wine...`→`C:\...MQL5\Files`）・`stat -f %m`（BSD構文→Windows）・python起動 等が要移植。**bashそのままは動かない**
- ※週次HMの起点はMacのWaveLogライン引き＝Mac本拠。VPS化の本命は日次watcher

## 🛠 今日確立した運用trap（再発時用）→ メモリ化済み [[mac-semi-auto-pipeline-watcher]]
- **iCloud同期スタック**（6/17 19:02から、ストレージ満杯余波で約18hストール）→ `killall bird`＋`brctl download <path>`で回復。last-syncが現在時刻に更新されればOK
- **~/Desktop配下スクリプトのlaunchd永続化は不可**（TCC）→ ログイン項目.app方式で回避

## 📋 据え置きの分割タスク
- **コー**: enrichedに is_signal/tag/style_class パース分離（prepare_trade_input.py）／Trade_Snapshot_Builder列拡充
- **マニ**: daily_calendar_v3 に分析タブ（グルーピング/フィルター/ソート）
- **カイ**: is_signal別/tag別/★時間帯別の機能性統計（損益集計禁止）
- **おぱ**: VPS常駐化（移植）／旧Actions(daily_v2.yml)掃除

## ⚠️ 注意点（継続）
- **scores.json**＝初期Twelve遺産（5/27停止）。v14の表示主軸は weekly_waves.json の adx_score。**資産保持でOK**（消すと古い週のscore_v3集計が変わるリスクのみ）。daily_v2.yml掃除時に整理
- VPS 2GB不安定（OOM）。MT5常駐＋claudeは作業時だけなら回る。Win2(3.5GB)が本筋
- RDPは「**切断**」でVPSアプリ生存／「**ログオフ**」厳禁
- Mac sleep中はwatcher休止（24hはVPS）

## 未コミット
- `auto_sync_daily.sh`（+87/-2、週次watcher＋iCloud橋渡し）／`latest.md` → コミット要否はあろさん判断

---
*次の起点＝再起動後のwatcher自動起動を検証→OKなら半自動更新化Mac側クローズ。次の山はVPS常駐化（Windows移植）。*
