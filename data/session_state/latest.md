# 次セッションへの引き継ぎ（2026-06-20 朝 — A: auto_sync_daily.sh 同根地雷 解消＆Mac有効化 完了）

## 🚀 おぱ起動作法（VPS↔Mac 連携・毎回これを最初に）
1. **まず `git pull --rebase origin main`**（dirtyなら `git stash → pull --rebase → stash pop`）。VPSとMacは同じmainを書き合うパラレル運用。
2. この latest.md の「**今ここ**」で把握。詳細は CLAUDE.md §15 / 設計書 `data/vps/日次動脈_DESIGN_v1.md`。
3. **push前も必ず `git pull --rebase`**。RDPは「切断」で抜ける（ログオフ厳禁）。

## ⚠️ おぱ動作の地雷: temp バースト（継続中）
- Bash出力が無言で切れ `temp filesystem ... full (0MB free)` (ENOSPC)。**物理でなく Claude Code サンドボックス層の断続バグ**。6-20朝も発生。
- 回避＝重要コマンドは `{ cmd; } > _diag.txt 2>&1` → Read で読む／出力を小さく保つ。続くなら **Claude Code 再起動**。

## 🎯 今ここ — A 完了。動脈は VPS↔Mac 双方向で自走化
**パラレル運用の実例が起きた**: 昨日「実装これから」だった A を、**VPS側おぱが先に実装**してmainに乗せてた（`d5c7a06` 今朝08:20）。中身は昨日の合意方針とピッタリ一致。Mac側おぱ（今セッション）は **pull→レビュー→watcher再起動で有効化→検証** を担当。役割分担がそのまま回った。

### A の中身（`d5c7a06` で実装済・本セッションで有効化）
1. **日次TARGETS再編**: VPS由来3つ（signal_fires / daily_aggregate / daily_mfe_mae_48h）を Mac MT5監視から除外 → `trades_enriched.csv`(系統A)だけに。空振りの正体を解消。
2. **`check_git_pull()` 新設**: 60秒毎に origin/main 進行を検知 → `pull --rebase --autostash` → `mt5_data/daily/` に差分あれば `run_daily_calendar.sh --no-open`。`daily_changed` は pull 前に判定（順序正しい）。`set -e` 下でも `|| return 0` ガードで watcher が死なない。
3. **検証済（Mac実機）**: `bash -n` OK / 旧watcher(4ターゲット・git検知なし)を停止 → 新コードで再起動（PID 3019, 08:27:44）→ 新バナー確認（`ターゲット(Mac MT5): trades_enriched.csv` ＋ `VPS push取込: git pull検知 60s毎`）。

## ✅ 本日の到達（コミット）
- `d5c7a06` fix(auto_sync): watcher 同根地雷を解消 — 日次TARGETS再編＋git pull検知新設 ← **A本体（VPS側実装）**
- （Mac側は watcher 再起動のみ＝コミット不要。コード変更なし）

## ⚠️ watcher 運用メモ（今日の知見）
- **watcher はメモリ常駐＝ファイルを pull で更新しても自動では反映されない**。`auto_sync_daily.sh` を変更したら **watcher を kill→再起動**しないと旧コードのまま走り続ける。今回それが「旧版が動いてた」正体。
- ログイン項目ランチャー（`pgrep || nohup ...`）は**一度きり**。kill しても自動復活しないので手動で `nohup ./auto_sync_daily.sh >> auto_sync.log 2>&1 &`。
- 再起動手順: `pkill -f "bash ./auto_sync_daily.sh"` → `nohup ./auto_sync_daily.sh >> auto_sync.log 2>&1 &` → `grep -c "VPS push取込" auto_sync.log` で新バナー確認。

## ▶ 次の起点（A の後・残課題）
- **A の通しテスト（自然発生待ち）**: 次の VPS push（schtasks PM23:10）で「VPS push → Mac watcher が60秒以内に pull → daily/差分検知 → カレンダー再生成」が自動で起きるはず。次セッションで `auto_sync.log` の `▶ origin/main 更新検知` 行を確認すれば通し確認完了。
- **②のVPS化**（ADX_Weekly / H4PhaseAuto も EA化＝データプール拡大・次の大トラック候補）
- `_EA` suffix掃除 / 系統A設計ズレ（`mt5_data/{trade_input,trades_enriched}.csv` を data/trades/寄せ or §1修正）
- `sync_mt5_data.sh` のMac既存M（中身要確認・フェーズと無関係）
- `archive/*.md`(9個) / `FX_*`(2個) 未commit溜まり（整理候補）
- Win2(3.5GB)判断 / VPS再起動時：schtasks「ログオン中のみ実行」＝RDPログオンまで発火しない

## 🔧 別荘 運用フロー（継続）
- push前は必ず `git pull --rebase` / RDPは「切断」で抜ける / コー実装EAは MetaEditor **F7再コンパイル必須**（.ex5不可）/ `signals/`が正本

---
*A（watcher 同根地雷）完了：VPS側が実装（`d5c7a06`）→ Mac側が pull・レビュー・再起動・検証で有効化。パラレル運用が綺麗に回った好例。次＝次回VPS pushで A の通しテスト自動確認 → その後 ②のVPS化。*
