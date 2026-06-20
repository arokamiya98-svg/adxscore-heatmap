# 次セッションへの引き継ぎ（2026-06-20 — 日次カレンダー再生成漏れ 恒久対策完了 / 次＝データを使う側）

## 🚀 おぱ起動作法（VPS↔Mac 連携・毎回これを最初に）
1. **まず `git pull --rebase origin main`**（dirtyなら `--autostash`）。VPSとMacは同じmainを書き合うパラレル運用。
2. この latest.md の「**今ここ**」で把握。VPS/動脈を触るなら **ブン召喚**（`.claude/agents/bun.md`／本籍doc `data/vps/日次動脈_DESIGN_v1.md`）。
3. **push前も必ず `git pull --rebase`**。RDPは「切断」で抜ける（ログオフ厳禁）。

## ⚠️ tempバースト（継続）＋ サブエージェント伝送障害（新）
- Bash出力が無言で切れ `temp ... full (0MB free)`＝harnessサンドボックス層のバグ。重要コマンドは `{ cmd; } > /tmp/_x.txt 2>&1` → Read。
- **新**: サブエージェント（ブン等）召喚で Bash/Read のパラメータが harness層で消失する「入力版tempバースト」が出た（2026-06-20）。メインのツールは正常→**おぱが巻き取れる**。詳細 [[subagent-tool-transmission-failure]]。

## 🎯 今ここ — 日次カレンダー案件クローズ → 次フェーズ
**「カレンダーが変わらない」案件は 調査〜応急復旧〜恒久対策〜実機検証 まで完了。** 次は据え置き消化 or「データを使う側」へ。

- 残・軽微: **watcher を次に再起動すると** ログの `trigger=` 表示がASCII化（`freshness`等）。実害ゼロ・急がない（reason ASCII化はコミット済、現watcher PID97259 は旧reasonで稼働中だが機能は完動）。

## ✅ 本日の到達（コミット 2026-06-20）
- **D1始値化 VPSデプロイ＆実機検証 完了**（`a696758`・前セッション）。19日下落日で売り優位が素直に出る＝14:00局所谷拾い問題が解消。
- **日次カレンダー再生成漏れ 三層対応**（本セッション）:
  - 原因①一時障害（16:00 VPS連続push `60603e7→1b749fc→a696758` 交錯で run_daily_calendar がコケた）／②サイレント失敗（`check_git_pull` が `run_daily_calendar | grep | head` で exit code 握りつぶし「✅完了」誤表示）／③HEAD依存トリガー（HEAD追いつくと再生成しない取りこぼし）
  - `df9f548` 応急復旧（手動 run_daily_calendar でカレンダー新値化→push、19日 8.28/89.45 売り優位）
  - `bef3346` 恒久対策（`run_daily_safe`=exit code検知で⚠️可視化 / `check_freshness`=daily/CSV mtime>生成HTML mtime で再生成・HEAD非依存）
  - **実機検証**: watcher再起動(PID97259)→人工漏れ→**67秒後に鮮度照合が自動回復**（再生成+push）確認 ✅ ＝毎時エラーカバー完成
- **ブン伝送障害**でおぱ巻き取り（[[subagent-tool-transmission-failure]]）。

## 👥 チーム（2026-06-20）
コー=mq5/HTML描画 ／ カイ=BT分析 ／ マニ=振り返り ／ **ブン=VPS/日次動脈・自動化運用** ／ おぱ=番人+マネージャー。
※ ブンは伝送障害で動けない時はおぱが巻き取る（目的達成優先）。

## 📌 次フェーズの入口（構築完了後・データを使う側）
① マニv3カレンダーの iPhone UIデザイン ② インジ分析 ③ ロジック化の中身（H1優位性・期待値）。VPS運用はブンに任せて身軽に。

## 📋 据え置き
- **watcher再起動で reason ASCII表示反映**（実害ゼロ）
- FXベースラインskip対策（watcher停止中のFX取りこぼし・本籍doc§12.1）= ブン案件候補
- ②のVPS化（ADX_Weekly/H4PhaseAuto もEA化）/ `_EA` suffix掃除 / 系統A設計ズレ（trade_input/enriched の data/trades/寄せ）
- `sync_mt5_data.sh` のM / archive*.md・FX* 未commit溜まり / マニのagent定義とmemoryのドリフト整理

## 🔧 別荘 運用フロー
push前は `git pull --rebase` / RDPは「切断」/ コー実装EAは MetaEditor **F7必須**（.ex5不可）/ `signals/`が正本

---
*次＝据え置き消化 or データを使う側（UI/インジ/ロジック化）。日次動脈は鮮度照合トリガーで自己修復するようになった＝再生成漏れは次サイクルで自動回復。*
