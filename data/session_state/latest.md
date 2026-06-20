# 次セッションへの引き継ぎ（2026-06-20 — ブン誕生＋棚卸し＋仮想エントリーD1始値化 / 次回＝VPSデプロイ後にブン検証）

## 🚀 おぱ起動作法（VPS↔Mac 連携・毎回これを最初に）
1. **まず `git pull --rebase origin main`**（dirtyなら `git stash → pull --rebase → stash pop` か `--autostash`）。VPSとMacは同じmainを書き合うパラレル運用。
2. この latest.md の「**今ここ**」で把握。VPS/動脈を触るなら **ブン召喚**（`.claude/agents/bun.md`／本籍doc `data/vps/日次動脈_DESIGN_v1.md`）。
3. **push前も必ず `git pull --rebase`**。RDPは「切断」で抜ける（ログオフ厳禁）。

## ⚠️ tempバースト（継続）
Bash出力が無言で切れ `temp ... full (0MB free)`＝harnessサンドボックス層のバグ。重要コマンドは `{ cmd; } > /tmp/_x.txt 2>&1` → Read。続くなら再起動。

## 🎯 今ここ — 次の一手＝VPSデプロイ → ブン検証
**仮想MFE/MAEの起点を JST14:00固定 → D1足始値（市場オープン）に変更（コミット済 `signals/`正本）。まだVPS未デプロイ。**

### ▶ あろさんの番：VPSデプロイ（本命=DailyBatch EA）
```
① VPS で git pull --rebase origin main
② signals/XAUUSD_DailyBatch_EA_v1.mq5 を MT5 の MQL5/Experts/ へコピー
③ MetaEditor で開いて F7 再コンパイル（.ex5不可）
④ XAUUSD H1 チャートの EA を付け直し（or 再コンパイルで自動リロード）
```
※ Script温存版 `XAUUSD_Daily_MFE_MAE_v1.mq5` も同変更済（分析時のみF7）。

### ▶ デプロイ後：ブンに検証を投げる（「ブン、D1始値化の検証して」）
- `daily/daily_mfe_mae_48h.csv` の `virtual_entry_price` = その日のD1始値と一致するか
- `virtual_entry_jst` がD1足の時刻に追従（**DST週でズレず足境界に乗るか**）
- **下落日に buy_mfe < buy_mae（売り優位）が素直に出るか**（=14:00局所谷拾い問題が解消したか／6/19が分かりやすい）
- `bars_traced` フル日=48 / 最新1〜2日=partial(<48)＝正常
- CSV列・ヘッダ完全一致でPython生成器がエラーなく読めるか

## ✅ 本日の到達（コミット 2026-06-20）
- `d5c7a06` watcher同根地雷解消（Mac側有効化・検証は本セッション、PID再起動で新コード稼働）
- `0e43419` 系統A 6/16・6/18エンリッチ反映（追跡欠損=0・①②③カレンダー解決）
- 棚卸し: **ブン誕生**（`.claude/agents/bun.md`）＋ CLAUDE.md §15→ポインタ化（703→655行）＋ §8.0「構築フェーズ完了→次フェーズ」
- 分担md 3層明記（`generate_*.py`: データフロー=ブン/描画=コー/思想=おぱ+あろさん）— ko.md/bun.md/役割メモリ
- `feat(daily)` 仮想エントリーD1始値化（コー実装・両mq5・スキーマ不変）

## 👥 チーム（2026-06-20更新）
コー=mq5/HTML描画 ／ カイ=BT分析 ／ マニ=振り返り(本籍) ／ **ブン=VPS/日次動脈・自動化運用(新設)** ／ おぱ=番人+マネージャー。
`generate_*.py` の境界事案は3層分担で戻し先一意（ブン初仕事=6/19バー調査で炙り出した）。

## 📌 次フェーズの入口（構築完了後・データを使う側）
① マニv3カレンダーの iPhone UIデザイン ② インジ分析 ③ ロジック化の中身（H1優位性・期待値）。VPS運用はブンに任せて身軽に行ける。

## 📋 据え置き
- FXベースラインskip対策（watcher停止中に置かれたFXを取りこぼす・本籍doc§12.1）= ブン案件候補
- ②のVPS化（ADX_Weekly/H4PhaseAuto もEA化）/ `_EA` suffix掃除 / 系統A設計ズレ（trade_input/enriched の data/trades/寄せ）
- `sync_mt5_data.sh` のM / archive*.md・FX* 未commit溜まり / マニのagent定義(振り返り)とmemory(実装相棒)のドリフト整理

## 🔧 別荘 運用フロー
push前は `git pull --rebase` / RDPは「切断」/ コー実装EAは MetaEditor **F7必須**（.ex5不可）/ `signals/`が正本

---
*次＝VPSで DailyBatch EA を F7デプロイ → ブンに D1始値化の実機検証を投げる（下落日に売り優位が出るか・DST追従が主眼）。詳細は CLAUDE.md §15→ブン本籍doc。*
