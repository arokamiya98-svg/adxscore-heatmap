# 次セッションへの引き継ぎ（2026-06-22 — マニv3カレンダー iPhone/iPad UI 一新 完了・クローズ）

## 🚀 おぱ起動作法（VPS↔Mac 連携・毎回これを最初に）
1. **まず `git pull --rebase origin main`**（dirtyなら `--autostash`）。VPSとMacは同じmainを書き合うパラレル運用。
2. この latest.md の「**今ここ**」で把握。VPS/動脈を触るなら **ブン召喚**（`.claude/agents/bun.md`／本籍doc `data/vps/日次動脈_DESIGN_v1.md`）。
3. **push前も必ず `git pull --rebase`**。RDPは「切断」で抜ける（ログオフ厳禁）。

## ⚠️ tempバースト（継続中・今日も終始発生）
- Bash出力が無言で切れる＝harnessサンドボックス層のバグ。**対処が確立**: 重要コマンドは `{ cmd; } > /tmp/_x.txt 2>&1` で書き出し → **Readツールで回収**（catは標準出力経由で死ぬ）。今日の作業は全てこれで完遂した。[[claude-temp-burst-enospc]]

## 🎯 今ここ — マニv3カレンダー iPhone UI クローズ → 残は配色「全体通し」横展開
**「データを使う側」フェーズ①（マニv3カレンダーの iPhone UIデザイン）完了。** あろさん実機FBループで5コミット、iPhone/iPad で実用ラインに。実機「めちゃ気に入った・一気に分かりやすくなった」でクローズ。

## ✅ 本日の到達（5コミット・全て `generate_daily_calendar_v3.py` → `docs/daily_calendar_v3.html`）
1. `d6bf2e3` viewport追加 / セルタップ`#drill`をモバイル全画面化 / **月を降順**（最新月が先頭）
2. `1a8a434` 見切れ解消（5列を画面幅フィット・横スクロール撤去）/ **凡例をカレンダー下へ**（CSS order）
3. `feaf16a` **D1帯 配色革命 v0.9**（🟡BU琥珀 / 🟣PD紫 / 🩶RANGE灰・赤青は方向(DI/ADX)専用に解放）/ セル文字9px
4. `d4f8b96` MAE/MFEバー・シグナル/結果行のはみ出し解消（`overflow:hidden;nowrap`）
5. `8a22a15` 期間フィルタを `<input type=date>` の **from〜to 任意区間**に（iOS日付ピッカー・空欄=無制限）
- モバイル調整は全て `@media (max-width:640px)` 中心＝**PCの見た目は不変**。`#tab-calendar.active`付きセレクタでタブ切替を壊さないのがミソ。
- 設計思想の深化を記録済 → [[atr-is-band-not-direction]] が v0.8(色相=DI方向)→**v0.9(色相=ATR Phase)** に反転。詳細 [[daily-research-calendar-v3-design]]。

## 📌 残タスク（次の一手・優先）
- **配色v0.9の「全体通し」横展開**（あろさん明言「全体通してやって」の続き）:
  - ① 全体像タブの**円グラフ** `d1_phase` 色（`generate_daily_calendar_v3.py` 2451-2453 付近）を 琥珀/紫/灰 に
  - ② **heatmap_v14**（`generate_heatmap_v14.py`）の D1 Phaseレイヤーを 同色に
  - 色値: BU=`rgba(235,175,55)` / PD=`rgba(150,110,205)` / RANGE=灰。赤青は方向専用。
- 「データを使う側」の他の入口: ② インジ分析 ③ ロジック化の中身（H1優位性・期待値）

## 📋 据え置き（前回から継続・未着手）
- `sync_mt5_data.sh` のM / `archive*.md`・`FX*` 未commit溜まり / マニのagent定義とmemoryのドリフト整理
- watcher再起動で reason ASCII表示反映（実害ゼロ）
- FXベースラインskip対策（本籍doc§12.1）= ブン案件候補
- ②自動集計のVPS化（ADX_Weekly/H4PhaseAuto EA化）/ `_EA` suffix掃除 / 系統A設計ズレ

## 👥 チーム
コー=mq5/HTML描画 ／ カイ=BT分析 ／ マニ=振り返り ／ ブン=VPS/日次動脈・自動化運用 ／ おぱ=番人+マネージャー。

## 🔧 別荘 運用フロー
push前は `git pull --rebase` / RDPは「切断」/ コー実装EAは MetaEditor **F7必須**（.ex5不可）/ `signals/`が正本

---
*次＝配色v0.9の横展開（円グラフ＋heatmap_v14）で「全体通し」を完遂、or データを使う側の他入口（インジ分析/ロジック化）。日次動脈は鮮度照合トリガーで自己修復・自走中。*
