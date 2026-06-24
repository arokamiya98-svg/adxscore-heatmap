# 次セッションへの引き継ぎ（2026-06-24 — Bash事故の真因解明＋半自動化建て直し設計確定・ブン実装着手）

## 🚀 おぱ起動作法（VPS↔Mac 連携）
- **VPS/動脈を触るセッションだけ**、着手前に `git pull --rebase origin main`（dirtyなら `--autostash`）。VPSとMacは同じmainを書き合うパラレル運用。**触らない日は不要**＝開幕で毎回叩かない。
- この latest.md の「**今ここ**」で把握。VPS/動脈を触るなら **ブン召喚**（`.claude/agents/bun.md`／本籍doc `data/vps/日次動脈_DESIGN_v1.md`）。
- **push前は `git pull --rebase`**。RDPは「切断」で抜ける（ログオフ厳禁）。
- ⚠️ 開幕に全コマンドをファイル経由（`>file`→Read）で回す"儀式"は**やめる**。普通にBashを使う。

## 🧰 Bashの出力Tip（※「tempバースト」という常時バグは存在しない）
- ごく稀に大きい出力が途中で切れる/「0MB free」ENOSPC誤報が出る。**その時だけ** `{ cmd; } > /Users/aro/Desktop/ADXSCORE/_diag.txt 2>&1` → Readで回収（child直書きで満杯扱いのharness pipeを迂回・2026-06-24実証）。物理ディスクは119GB空き＝誤報。
- **2種類の「詰まる」を混同しない**（2026-06-24確定）：**A.Bash10分ハング＝環境の本物**（watcher git-lock/CPU・Mac全体・インフラで直る）／**B.ENOSPC誤報・文字化け・malformed＝モデル劣化**（再起動案件）。詳細 [[claude-temp-burst-enospc]]。

## 🎯 今ここ — 半自動化環境の建て直し（指示書確定→ブン実装中/直後）
今日のセッションで **Mac全体のBash 10分ハングの真因が確定**し、**半自動化環境を建て直す設計を固めた**。指示書を発行しブンに実装を委譲した段階。
- **真因**：旧 `auto_sync_daily.sh`（常駐デーモン）の【60秒 git pull ループ × 二重keepalive(LaunchAgent＋AppleScript app)で2本起動レース × git timeout無し × CPU飢餓】。= Mac全体を詰まらせ全Claudeセッション(PRIVATE含む)を巻き込んでた。
- **新設計**：常駐廃止 →【(A) `hourly_sync.sh` 毎時1回単発（②VPS受信＋④週次をmtime差分で拾い終了）／(B) `update_mani.sh --watch` 系統A・前景・自動終了・**gitループ無し**／(C) launchd単一化・KeepAlive=false】。原則＝**git pull常時ループを系統Aのwatchから引き剥がす**。
- **指示書**：`data/vps/ブン指示書_半自動化建て直し_v1.md`（事故分析→新設計→実装仕様→受け入れ条件→ロールバック）。

## ✅ 本日の到達
1. **Bash事故 真因解明**（あろさんの読み的中）→ watcher/Watcher.app/auto_sync を停止（launchd unload済）。Mac静穏化。
2. `26556de` **①timeout**：`auto_sync_daily.sh` の git fetch/pull を自前 `run_to`(fetch15s/pull45s) で囲い無限ハング封鎖。検証済（ハングを3秒で打ち切り実証）。
3. `3dd762b` **マニv3更新**：T033(6/22 SELL +36,500)を Trade_Snapshot_Builder で環境再取得→enriched_full 33件→日次カレンダー再生成→docs公開。
4. **半自動化建て直し設計確定＋指示書発行**（上記「今ここ」）。
5. **メモリ**：[[minimal-execution-distilled-simplicity]]（朝の「削ぎ落とした無我の執行」転換）／[[claude-temp-burst-enospc]] にA/B切り分け追記。

## 📌 残タスク（次の一手）
- **ブン実装の続き/検証**：`hourly_sync.sh`＋`update_mani.sh`＋新launchd。受け入れ条件（多重起動ガード/timeout/常駐残らない）を実測。
- **⚠️ 残骸（`ADXSCORE_Watcher.app`＋ログイン項目＋旧plist）は「今は触らない」指示**。撤去は新スクリプト合格＋あろさんGO時。**それまでMac再起動で二重keepalive復活注意**（再起動前に実装が理想）。
- **配色v0.9の「全体通し」横展開**（前回からの繰越）：① 全体像タブ円グラフ `d1_phase` 色（`generate_daily_calendar_v3.py` 2451-2453付近）② heatmap_v14 D1 Phaseレイヤー。色値 BU=`rgba(235,175,55)`/PD=`rgba(150,110,205)`/RANGE=灰。
- 「データを使う側」他入口：インジ分析 / ロジック化（H1優位性・期待値）。

## 📋 据え置き
- `sync_mt5_data.sh` のM / `archive*.md`・`FX*` 未commit溜まり / マニのagent定義とmemoryのドリフト整理。
- ②自動集計のVPS化（ADX_Weekly/H4PhaseAuto EA化）/ `_EA` suffix掃除。

## 👥 チーム
コー=mq5/HTML描画 ／ カイ=BT分析 ／ マニ=振り返り ／ ブン=VPS/日次動脈・自動化運用 ／ おぱ=番人+マネージャー。

## 🔧 別荘 運用フロー
push前は `git pull --rebase` / RDPは「切断」/ コー実装EAは MetaEditor **F7必須**（.ex5不可）/ `signals/`が正本

---
*次＝ブン実装の検証クローズ（半自動化建て直し）→ 配色v0.9横展開 or データを使う側の他入口。VPSは自律毎時push継続中、Mac側はブン実装まで手動運用。*
