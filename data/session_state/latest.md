# 次セッションへの引き継ぎ（2026-06-20 CLAUDE.md v14整備＋②M解消＋エンコード正確化 完了 → 次は A: auto_sync_daily.sh 同根地雷【方針合意済・実装これから】）

## 🚀 おぱ起動作法（VPS↔Mac 連携・毎回これを最初に）
1. **まず `git pull --rebase origin main`**（dirtyなら `git stash → pull --rebase → stash pop`）。VPSとMacは同じmainを書き合うパラレル運用。
2. この latest.md の「**今ここ**」「**次の起点**」で把握。詳細は CLAUDE.md §15 / 設計書 `data/vps/日次動脈_DESIGN_v1.md`。
3. **push前も必ず `git pull --rebase`**。RDPは「切断」で抜ける（ログオフ厳禁）。

## ⚠️ おぱ動作の地雷: temp バースト（2026-06-19〜20 Mac で継続確認）
- Bashツール出力が無言で切れ `temp filesystem ... full (0MB free)` が出る。**物理でなく Claude Code サンドボックス層の断続バグ**（ディスク空き十分・temp実体0Bで確認済）。**6-20も複数回発生**（git/grep出力・echoごと消失）。
- 影響＝出力が見えてないのに見たつもりで**誤判断**する（「おぱの様子が変」の正体）。
- 回避＝重要コマンドは `{ cmd; } > _diag.txt 2>&1` でファイル化→Readで読む／出力を小さく保つ（全文系を避ける）。続くなら **Claude Code 再起動**でサンドボックスをリセット。←★この引き継ぎ直後に再起動予定

## 🎯 今ここ — CLAUDE.md整備が一段落、再起動して A 実装へ
前回「日次動脈 完全クローズ」に続き、**ドキュメント/データ side を3点クローズ**：
1. CLAUDE.md **v14**（§15「日次動脈/VPS無人化運用」新設・系統A/B/C整備・`mt5_data/daily/`構造反映・起動作法/地雷を恒久化）
2. **②週次データM放置 解消**（恒久対応＝run_pipeline.sh Step5に②add は既実装済を確認。今回は溜まったMを手動commit）
3. **エンコード正確化**（`H4PhaseAuto_weekly`=**UTF-16** を実測発見・CLAUDE.md §6/§10修正）

→ **次の作業 = A（方針合意済・実装これから）**。temp バースト継続のため**再起動してクリーンな状態で実装に入る**。

## ✅ 本日の到達（コミット 2026-06-20）
- `41ed3c2` docs(CLAUDE): v14 — 日次動脈フル稼働を反映（§15新設・系統A/B/C整備）
- `445f2da` data: ② 週次集計 同期分（ADX_Weekly W24 / H4PhaseAuto W24-W25・VPS pool分も rebase取込）
- `e326823` docs(CLAUDE): エンコード正確化（H4PhaseAuto=UTF-16・§10に日次daily系追記）

## 🩸 動脈フル稼働（完成形・維持）
```
VPS MT5 EA →(毎時) →[schtasks AM8:10/PM23:10] vps_data_pool_push.sh
  → mt5_data/daily/ → git push          ★VPS全自動
       │ git
       ▼
Mac git pull → ./run_daily_calendar.sh → 成績合流 → docs公開   ★素で安全(--no-sync不要)
       │ git push → GitHub Pages
       ▼
   iPhone/iPad で日次カレンダー
```

## 📌 運用メモ（今日の知見 2026-06-20）
- **`H4PhaseAuto_weekly.csv` は UTF-16**（`FractalWaveLog_H4系`=UTF-8-sig とは別系統。`ARO_H4PhaseAuto_v1.mq5` が ADX_Weekly系と同じ `FILE_UNICODE` 出力）。`process_wavelog.py` は全CSVを `(utf-16, utf-8-sig, utf-8)` フォールバックで読む堅牢実装＝**実害なし**、ドキュメントだけ古かった。
- **②のM放置は構造的**：run_pipeline.sh Step5 が②をadd（既実装）→ 週次 run_pipeline 実行で自動commit。MT5から手動同期だけだとcommitされずM放置になる。
- 「追跡欠損」表示＝48h未経過の追跡途中＝正常（動脈が最新を運ぶ証拠）。

## ▶ 次の起点（A から・方針合意済 2026-06-20）

### 【次これ】A: `auto_sync_daily.sh` 同根地雷の解消
**地雷**: 日次TARGETS（`auto_sync_daily.sh` 33行）に VPS由来3つ（`signal_fires` / `daily_aggregate` / `daily_mfe_mae_48h`）が居る → Mac MT5 Files監視で**永遠に空振り**。VPSが daily/ を git push しても watcher は気づかず、日次カレンダー自動更新が効かない（手動 `run_daily_calendar.sh` 頼み）。Step1（run_daily_calendar.sh本体）は恒久対応済なのに、起動する watcher が旧前提＝同根。

**改修① 日次TARGETS再編**:
- VPS由来3つ（`signal_fires` / `daily_aggregate` / `daily_mfe_mae_48h`）を Mac MT5監視から**外す**
- `trades_enriched`（系統A・Mac専管）は**維持**
- FX入口（132-152行）・週次 WEEKLY_TARGETS（37-45行）は**無改修**（どちらも Mac 手動MT5前提で正しい）

**改修② git pull検知 新設**:
- watcherループに `git fetch` →（origin/main が進んでたら）`git pull --rebase --autostash` を **60秒に1回**（2秒毎ループは重いので別カウンタ管理）
- `mt5_data/daily/` が更新されたら `run_daily_calendar.sh --no-open`
- dirty競合は `--autostash` で吸収（②commit `445f2da` で実証済の方式）

**実装後の検証**: watcher 実テスト要（VPS push → Mac watcher が60秒以内に pull → daily/更新検知 → カレンダー再生成、の通し確認）。対象コードは `auto_sync_daily.sh`（読込済・全231行）。

### その後（A の後）
- ②のVPS化（ADX_Weekly / H4PhaseAuto も EA化＝データプール拡大・次の大トラック候補）
- `_EA` suffix掃除 / 系統A設計ズレ（trade_input/enriched の data/trades/寄せ）

## 📋 据え置き
- 系統A設計ズレ（`mt5_data/{trade_input,trades_enriched}.csv` tracked・個人情報シロ・将来 data/trades/寄せ or §1修正）
- `sync_mt5_data.sh` のMac既存M（中身要確認・フェーズと無関係）
- `archive/*.md`(7個) / `FX_*`(2個) 未commit溜まり（整理候補・今回スコープ外）
- Win2(3.5GB)判断 / VPS再起動時：schtasks「ログオン中のみ実行」＝RDPログオンまで発火しない

## 🔧 別荘 運用フロー（継続）
- push前は必ず `git pull --rebase` / RDPは「切断」で抜ける / コー実装EAは MetaEditor **F7再コンパイル必須**（.ex5は556） / `signals/`が正本

---
*CLAUDE.md整備（v14＋②解消＋エンコード）完了。**次＝A: `auto_sync_daily.sh` の同根地雷を解消**（方針合意済＝①TARGETS再編②60秒git pull検知）。この引き継ぎ commit 後に Claude Code 再起動 → クリーンな状態で A 実装へ。詳細 CLAUDE.md §15 / `data/vps/日次動脈_DESIGN_v1.md`。*
