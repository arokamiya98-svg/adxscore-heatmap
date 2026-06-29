# 次セッションへの引き継ぎ（2026-06-29 — ②EA化の稼働確認＋週枠の真因確定・手動WAVELOGスイッチ実証／次＝(C) D1週次サンプリングEA化）

## 🚀 おぱ起動作法（VPS↔Mac 連携）
- **VPS/動脈・EA化を触るセッションだけ**、着手前に `git pull --rebase origin main`（dirtyなら `--autostash`）。VPSとMacは同じmainを書き合うパラレル運用。**触らない日は不要**。
- (C)はVPS配置を伴う＝**ブン召喚**（`.claude/agents/bun.md`／本籍doc `data/vps/日次動脈_DESIGN_v1.md`）。mq5実装は**コー**。
- **push前は `git pull --rebase`**。RDPは「切断」で抜ける（ログオフ厳禁）。普通にBashを使う（"ファイル経由儀式"はやめる）。

## 🧰 Bash出力Tip ＆ Read劣化（2種類混同しない）
- **A.Bash10分ハング＝環境の本物**（git-lock/CPU）／**B.ENOSPC誤報・文字化け・malformed・Read捏造＝モデル劣化**（再起動案件）。詳細 [[claude-temp-burst-enospc]]。
- ⚠️ **pandasはシステムpython3に無い**（`ModuleNotFoundError`）。CSV/JSON確認は標準ライブラリ（csv/codecs/json）で。UTF-16フォールバック `["utf-16","utf-8-sig","utf-8"]`。

## ✅ 今日の決着（6/29）— 「週次が更新されない」完全解明＆実証
- **②自動集計（ADX_Weekly_v4 / H4PhaseAuto）のVPS EA化は完了・稼働中**。両CSVともW27(進行中週)まで毎時VPSから来てる（16:18 push確認）。前回(6/26)スコープ確定 → あろさんがVPS側でEA化を完遂済みだった。
- **真因＝週枠ボトルネック**：週の「枠」を立てるのは `FractalWaveLog_D1_weekly.csv` **一本だけ**。`process_wavelog.py`(610-705) は `weekly=merge_weekly_with_waves(weekly_d1,...)` で週枠=D1週次CSVのキーのみ → ②(ADX/H4Phase)は `for wk in weekly.items(): if wk in adx_data` で**週枠に後マージするだけ**。枠が無い週の②データは捨てられる。
- ②はW27まで来てたのに heatmapがW26止まりだった理由＝D1週次(週枠源)が**手動WAVELOG(`ARO_FractalWaveLog_D1_v3_2`)のまま6/27止まり**。前回②をEA化したのは正解で、残ってたのは「週枠を作るD1週次の1本」だけだった。
- **手動WAVELOG=スイッチ 完全実証**：あろさんWAVELOG実行(17:36) → MT5 FilesにW27枠（D1: BU/ADX22=39.47/DI-/ATR=1.037 進行中週指標入り） → 18:10 hourly_sync → mt5_data同期 → W27に②合流(ADXスコア39.6/H4Phase収束底) → heatmap更新＆push公開（git `0b34bd8`）。weekly_waves 332→333週。

## 🎯 次の一手＝(C) D1週次サンプリングEA化（あろさん選択・推奨案）
**狙い**：手動WAVELOGを毎時VPSが肩代わり → 進行中週のD1局面(BU/PD・ADX22・ATR)まで毎時自動。手描きBU/PD波形(Mac聖域)は温存。②と同じ無人サンプリングEAの追加＝設計一貫。これで①手描き=Mac聖域／②自動集計=VPS EA(ADX/H4Phase/**D1週次サンプリング**)の住み分け完成。
- **最初の一歩**：`signals/ARO_FractalWaveLog_D1_v3_2.mq5` を精読 → **weekly出力(ADX/DI/ATRサンプリング)が手描きトレンドライン非依存か**確認（(C)成立の前提・非依存なら②同様の無人EAにできる）。
- 非依存確認後 → weekly出力だけの軽量EA設計（v3_1波形レベル出力は捨てる/進行中週空でOK）→ コー実装指示書 → ブンVPS配置（**F7必須**）→ 検証（手動WAVELOGなしで翌週W28枠が自動で立つか）。
- ⚠️ `FractalWaveLog_D1_weekly.csv` は現状 `.gitignore`(①手描き扱い)。(C)でVPSが焼くなら **git追跡 or VPS push経路** の設計が要る（②と同じ `mt5_data/` 追跡扱いにするか要判断）。
- ✅ 検証手順は今日確立：MT5 Files側CSVの最新週(iso_week列)＋mtime → hourly_sync(:10)で mt5_data同期＆合流 → weekly_waves.json週数増＆git `weekly update` commit を確認。

## 📌 据え置き
- 系統A watch 本物Snapshotテスト（あろさんGO pending）／legacy `auto_sync_daily.sh` アーカイブ（数日安定後）
- 配色v0.9 全体通し横展開（`d1_phase`円グラフ＋heatmap D1 Phase。BU=`rgba(235,175,55)`/PD=`rgba(150,110,205)`/RANGE=灰）
- `archive*.md`・`FX*` 未commit溜まり / `sync_mt5_data.sh` のM / `_EA` suffix掃除
- `sync_mt5_data.sh` の「⚠️未生成: ADX_Weekly_Above_v3.csv」警告（v4があれば無害だがログがうるさい→v3参照を消すか要検討）
- ✅ hourly launchd 自走順調（:10毎時 ExitStatus=0）。`hourly_sync.log` 時々確認でOK。

## 👥 チーム
コー=mq5/HTML ／ カイ=BT ／ マニ=振り返り ／ ブン=VPS/動脈/自動化 ／ おぱ=番人+マネージャー

## 🔧 別荘 運用フロー
push前 `git pull --rebase` / RDPは「切断」/ コー実装EAは MetaEditor **F7必須**（.ex5不可）/ `signals/`が正本

---
*次＝(C) D1週次サンプリングEA化。`ARO_FractalWaveLog_D1_v3_2.mq5` 精読(weekly出力の手描き依存有無)→軽量EA設計→コー実装＋ブンVPS配置→検証。これで「進行中週のD1局面まで毎時自動」＝週次の完全無人更新が完成。本籍memory: [[vps-daily-automation-ea-design]]。*
