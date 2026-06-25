# 次セッションへの引き継ぎ（2026-06-25 — 半自動化建て直し カットオーバー完了・ライブ稼働）

## 🚀 おぱ起動作法（VPS↔Mac 連携）
- **VPS/動脈を触るセッションだけ**、着手前に `git pull --rebase origin main`（dirtyなら `--autostash`）。VPSとMacは同じmainを書き合うパラレル運用。**触らない日は不要**＝開幕で毎回叩かない。
- この latest.md の「**今ここ**」で把握。VPS/動脈を触るなら **ブン召喚**（`.claude/agents/bun.md`／本籍doc `data/vps/日次動脈_DESIGN_v1.md`）。
- **push前は `git pull --rebase`**。RDPは「切断」で抜ける（ログオフ厳禁）。
- ⚠️ 開幕に全コマンドをファイル経由（`>file`→Read）で回す"儀式"は**やめる**。普通にBashを使う。

## 🧰 Bashの出力Tip（※「tempバースト」という常時バグは存在しない）
- ごく稀に大きい出力が途中で切れる/「0MB free」ENOSPC誤報が出る。**その時だけ** `{ cmd; } > /Users/aro/Desktop/ADXSCORE/_diag.txt 2>&1` → Readで回収（child直書きで満杯扱いのharness pipeを迂回・2026-06-24実証）。物理ディスクは119GB空き＝誤報。
- **2種類の「詰まる」を混同しない**（2026-06-24確定）：**A.Bash10分ハング＝環境の本物**（watcher git-lock/CPU・Mac全体・インフラで直る）／**B.ENOSPC誤報・文字化け・malformed＝モデル劣化**（再起動案件）。詳細 [[claude-temp-burst-enospc]]。

## 🎯 今ここ — 半自動化建て直し ✅カットオーバー完了・ライブ稼働
旧「常駐 `auto_sync_daily.sh`（60秒git常時ループ×二重keepalive×timeout無し×CPU飢餓）」がMac全体のBash 10分ハングを誘発（全Claude/PRIVATE巻き込み）していた真因を解明→**常駐廃止の新アーキテクチャに建て直し、本日カットオーバー完了**。
- **稼働中の新構成**：
  - **(A) `hourly_sync.sh`** … launchd `com.aro.adxscore.hourly`（毎時:10・`KeepAlive=false`・RunAtLoad）が起こす→**走って即終了（常駐ゼロ）**。②VPS受信＋④週次(mtime差分)＋日次再生成＋publish。多重起動ガード/`run_to` timeout付き。
  - **(B) `update_mani.sh --watch`** … 系統A・前景・**gitループ無し**・トレード時だけ手動・自動exit。
- **TCC解決**：launchd→~/Desktop読込は `/bin/bash` にFDA付与で通った（`open -R /bin/bash`→設定へドラッグ／実証ExitStatus=0）。旧「launchd不可」は誤り。詳細 [[mac-semi-auto-pipeline-watcher]]。
- **撤去済**：旧residue（旧plist削除／旧app→ゴミ箱／ログイン項目削除）。launchd登録は hourly のみ。
- **手動運用**：見たい時は `./hourly_sync.sh`、トレード反映は `./update_mani.sh --watch`。指示書: `data/vps/ブン指示書_半自動化建て直し_v1.md`（§8実施記録）。

## ✅ 本日の到達
1. **Bash事故 真因解明**（あろさんの読み的中）→ watcher/Watcher.app/auto_sync を停止（launchd unload済）。Mac静穏化。
2. `26556de` **①timeout**：`auto_sync_daily.sh` の git fetch/pull を自前 `run_to`(fetch15s/pull45s) で囲い無限ハング封鎖。検証済（ハングを3秒で打ち切り実証）。
3. `3dd762b` **マニv3更新**：T033(6/22 SELL +36,500)を Trade_Snapshot_Builder で環境再取得→enriched_full 33件→日次カレンダー再生成→docs公開。
4. **半自動化建て直し設計確定＋指示書発行**（上記「今ここ」）。
5. **メモリ**：[[minimal-execution-distilled-simplicity]]（朝の「削ぎ落とした無我の執行」転換）／[[claude-temp-burst-enospc]] にA/B切り分け追記。

## 📌 残タスク（次の一手）
- **系統A watch の本物Snapshotテスト（あろさんGO判断・pending）**：`./update_mani.sh --watch` 起動→実MT5 Snapshot→`merge→generate→publish→自動exit` 完遂を実機確認（おぱテストは `touch` 擬似発火までは✅）。完遂したら系統A watch 日常採用GO。
- **legacy `auto_sync_daily.sh` のアーカイブ**：新launchd運用が数日安定したら退避（ロールバック用に即削除しない）。
- ✅ **初の自動発火 確認済（2026-06-25 09:10:05→09:11:39・ExitStatus=0・常駐残らず）** — launchd自走を実証。以後は `hourly_sync.log` を時々見て ExitStatus=0継続なら順調。
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
