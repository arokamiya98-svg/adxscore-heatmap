# 日次動脈 設計書 v1（EA生成CSV → pipeline → HTML → push の自動化）

> 作成: 2026-06-19 別荘セッション⑤ / 状態: **設計のみ（実装は次フェーズ）**
> 前提: 系統B・C EA化完了（[[project_vps-unmanned-design]]）。「CSVその場生成」の山を越えた次の一手。
> 関連: `VPS_UNMANNED_DESIGN.md` / `project_vps-base-2026-06`

---

## 0. これは何か（一行）

VPSのMT5 EAが毎時焼く日次CSVを、**git経由でMacに渡し、Macがトレード成績を合流させて日次カレンダーを公開する**——その動脈の配管設計。

---

## 1. 核心思想：3つの場所の役割分担

```
【VPS = データプール製造機】（全自動・個人情報ゼロ・24h）
  MT5 EA → signal_fires / daily_aggregate / daily_mfe_mae（毎時フル上書き）
  → mt5_data/daily/ へコピー → git push
  ＝ GitHubに「公開データプール」を更新し続けるのが本分

        ── git（合流点）──

【Mac = 成績合流機】（立ち上げ時・個人情報を持つ側）
  起動 → ウォッチャー → git pull でVPSデータプール受信
  → iPhone→iCloud→FX_*.csv 取込 → trade_input → trades_enriched
  → 日次カレンダー（成績オーバーレイ込み）生成 → docs/ → push
```

**なぜこの分担が必然か**：トレード成績（`trades_enriched`）は iPhone入力由来で `data/trades/`（.gitignore）にしか無く、VPSには存在しない。VPSは構造的に「成績を持てない」＝純データ生産に徹するのが自然。系統A（trades_enriched）がMac専管なのと同じ理由。

**個人情報の線引き（あろさん確定 2026-06-19）**：NGは具体的な口座番号のみ。トレード成績・ロジック・損益・ロットは公開OK。→ docs/ のカレンダー公開はこのまま継続して問題なし。

---

## 2. CSV 3分類と git 方針（設計の土台）

| # | 分類 | ファイル | 生成者 | 手描き依存 | git方針 |
|---|------|---------|--------|-----------|---------|
| ① | 手描き波形 | `FractalWaveLog_D1_v3_1` / `_D1_weekly` / `_H4_XAU` / `_H4_weekly` / `_H4_XAU_Vlines` | Mac手動MT5 | ✅依存（認知ステップ） | **.gitignore**（Macローカル専用・再生成可） |
| ② | 自動集計 | `ADX_Weekly_Above_v4`（+v3） / `H4PhaseAuto_weekly` | MT5自動（ライン不要） | ❌不要 | **git追跡 維持**（ADXスコア計算元・将来VPS化候補） |
| ③ | 日次 | `signal_fires` / `daily_aggregate` / `daily_mfe_mae_48h` | VPS EA（毎時） | ❌不要 | **`mt5_data/daily/` に分離・VPSがpush** |

**設計の肝**：①は手描き＝認知ステップ（[[recognition-route-purity-and-manual-lines]]）でMacに残す資産。②は手描き非依存＝**系統B/Cの次にEA化できる自動化資産**だから、①と一緒くたに沈めない。③が今回の動脈本体。

**rebase衝突が構造的に消える理屈**：
```
① .gitignore（管理外）        → Macで上書きしてもM発生しない
② Macがcommit/push           → クリーン維持（後述の運用追加で）
③ daily/ をVPSがcommit/push  → クリーン維持
→ mt5_data/ が常時クリーン → git pull --rebase が事故らない
```
現状の火種は②が「Mac生成されてもcommitされず古いまま（M放置）」な点。これは `run_pipeline.sh` の add対象に②を足すだけで消える（§6）。

---

## 3. データフロー全体図

```
┌─ VPS（全自動・タスクスケジューラ）───────────────────┐
│  MT5 EA（DailyBatch_EA / SignalFire_EA）               │
│    └→ MT5/Files/{signal_fires,daily_aggregate,         │
│                   daily_mfe_mae_48h}.csv（毎時）        │
│  vps_data_pool_push.sh（新規・本設計の成果物）          │
│    1. MT5/Files → mt5_data/daily/ コピー               │
│    2. git pull --rebase（合流）                         │
│    3. git add mt5_data/daily/ → commit → push          │
└────────────────────────────────────────────────────────┘
                       │ git（GitHub main）
                       ▼
┌─ Mac（立ち上げ時・ウォッチャー）─────────────────────┐
│  git pull → mt5_data/daily/ 受信                        │
│  ＋ iPhone→iCloud→FX_*.csv → prepare_trade_input       │
│       → trade_input → MT5でTrade_Snapshot → enriched    │
│  run_daily_calendar.sh                                  │
│    generate_{daily_calendar_v3,signals,trades}_calendar │
│      入力: mt5_data/daily/*.csv ＋ 成績                 │
│    → data/trades/processed/*.html                       │
│    → docs/*.html ミラー → git push（既存Step2.5/2.6）   │
└────────────────────────────────────────────────────────┘
                       │ git push → GitHub Pages
                       ▼
              iPhone/iPad で日次カレンダー閲覧
```

VPSは「Step1（MT5→mt5_data同期）」をgit越しにMacへ肩代わりするだけ。Mac側の生成・公開ロジック（`run_daily_calendar.sh` の Step2以降）は既に完成しているので**ほぼ無改修**、入力パスを `daily/` に向けるだけ。

---

## 4. mt5_data/ 最終ディレクトリ構造

```
mt5_data/
├── FractalWaveLog_D1_v3_1.csv        ┐
├── FractalWaveLog_D1_weekly.csv      │ ① 手描き波形
├── FractalWaveLog_H4_XAU.csv         │ → .gitignore（Macローカル）
├── FractalWaveLog_H4_weekly.csv      │
├── FractalWaveLog_H4_XAU_Vlines.csv  ┘
├── ADX_Weekly_Above_v4.csv           ┐ ② 自動集計
├── ADX_Weekly_Above_v3.csv           │ → git追跡維持
├── H4PhaseAuto_weekly.csv            ┘   （Macがpush）
└── daily/                            ┐ ③ 日次データプール
    ├── signal_fires.csv              │ → git追跡
    ├── daily_aggregate.csv           │   （VPSがpush）
    └── daily_mfe_mae_48h.csv         ┘
```

### .gitignore 追加
```gitignore
# ① 手描き波形CSV（認知ステップ・再生成可・Macローカル専用）
mt5_data/FractalWaveLog_*.csv
```
> 実装時: 既に追跡済みなので `git rm --cached mt5_data/FractalWaveLog_*.csv` で追跡解除（ファイル実体は残す）。

---

## 5. VPS側スクリプト叩き台：`scripts/vps_data_pool_push.sh`

```bash
#!/usr/bin/env bash
# vps_data_pool_push.sh — VPS日次データプール 製造→push（全自動）
# タスクスケジューラから Git Bash 経由で起動される想定
set -uo pipefail

REPO="/c/Users/Administrator/adxscore-heatmap"
MT5_FILES="/c/Users/Administrator/AppData/Roaming/MetaQuotes/Terminal/D0E8209F77C8CF37AD8BF550E51FF075/MQL5/Files"
POOL="$REPO/mt5_data/daily"
LOG="$REPO/vps_pool.log"
DAILY_FILES=( "signal_fires.csv" "daily_aggregate.csv" "daily_mfe_mae_48h.csv" )

ts(){ date '+%Y-%m-%d %H:%M:%S'; }
log(){ echo "[$(ts)] $*" | tee -a "$LOG"; }

cd "$REPO" || { log "ERROR: repo not found"; exit 1; }
mkdir -p "$POOL"

# 1. MT5 Files → daily/ コピー（_EA suffix は検証名残なので拾わない）
copied=0
for f in "${DAILY_FILES[@]}"; do
  if [ -f "$MT5_FILES/$f" ]; then
    cp "$MT5_FILES/$f" "$POOL/$f" && copied=$((copied+1))
  else
    log "WARN: 未生成 $f（EA未稼働?）"
  fi
done
log "copied=$copied/3"

# 2. 変更が無ければ無駄commitしない
if [ -z "$(git status --porcelain mt5_data/daily/)" ]; then
  log "no change → skip"; exit 0
fi

# 3. 合流（Mac watcherと同main）。--autostash で念のため安全に
if ! git pull --rebase --autostash origin main >>"$LOG" 2>&1; then
  log "ERROR: pull --rebase 失敗 → 手動介入要"; exit 2
fi

# 4. daily/ のみ add（②週次や①手描きには触らない）→ commit → push
git add mt5_data/daily/
git commit -q -m "data: VPS pool update $(ts)" || { log "commit skip"; exit 0; }
if git push -q origin main >>"$LOG" 2>&1; then
  log "✅ push 完了 (copied=$copied)"
else
  log "⚠️ push 失敗（次回再試行で回収）"; exit 3
fi
```

**設計判断**：
- add対象を `mt5_data/daily/` に限定 → ①②に絶対触らない＝Mac側の領域を侵さない。
- `git status --porcelain` で無変更スキップ → EAが同値再生成しても無駄commitを積まない。
- `--autostash` → 万一VPSローカルに未commit変更があってもrebaseが止まらない。
- push失敗は `exit 3` で記録のみ＝次回起動でフル上書き済みCSVごと回収（取りこぼしゼロ思想と整合）。

---

## 6. ②自動集計の push運用追加（Mac側・`run_pipeline.sh`）

現状 Step5 は `git add docs/heatmap_v14.html data/weekly_waves.json` のみ。ここに②を追加し、②のM放置を解消：

```bash
# Step 5（変更後）
git add docs/heatmap_v14.html data/weekly_waves.json \
        mt5_data/ADX_Weekly_Above_v4.csv \
        mt5_data/ADX_Weekly_Above_v3.csv \
        mt5_data/H4PhaseAuto_weekly.csv
```
> ①手描き波形は .gitignore 済みなので add 対象外（自動でクリーン）。

---

## 7. Windowsタスクスケジューラ設定方針

| 項目 | 値（叩き台） |
|------|------|
| プログラム | `C:\Program Files\Git\bin\bash.exe` |
| 引数 | `-lc "/c/Users/Administrator/adxscore-heatmap/scripts/vps_data_pool_push.sh"` |
| トリガー | **1日2回**（JST 08:10 / 23:10）＝東京・NY両クローズ後 ※要調整 |
| 実行条件 | 「ユーザーがログオンしているかに関わらず実行」（RDP切断中も動く） |
| 電源条件 | 「バッテリ/AC問わず実行」（VPSは常時AC） |

**頻度の考え方**：EAは毎時更新、Macは起動時pull。だからVPSは「Macが起動した時にそこそこ新鮮」であれば足りる。毎時pushはcommit履歴を汚すので、まず1日2回で開始 → フォワードで「鮮度が足りない」と感じたら increase。＝**やってみて詰める**枠。

---

## 8. Mac側の組み替え点（実装時チェックリスト）

| 対象 | 変更 |
|------|------|
| `scripts/generate_signals_calendar.py` | 入力 `mt5_data/signal_fires.csv` → `mt5_data/daily/signal_fires.csv` |
| `scripts/generate_daily_calendar_v3.py` | 同上（signal_fires 参照パス） |
| `scripts/generate_daily_calendar.py` | 入力 daily_aggregate / daily_mfe_mae のパスを `daily/` に |
| `run_daily_calendar.sh` | Step1 を「MT5 Filesコピー」→「git pull で daily/ 受信」に。または併存（自Mac MT5も持つなら）|
| `auto_sync_daily.sh` | 日次TARGETSの監視を「MacのMT5 Files」→「git pull 検知」へ寄せる（週次①はMac MT5監視のまま）|

> ⚠️ これらは**Mac作業**で、§9フェーズ1の「daily/移動」と**同一コミット群**にする（無停止移行）。VPSが先に進められるのは §5スクリプト作成と §7タスク登録の下書きまで——③の移動・push はMac配管の変更と必ず同時に行う。

---

## 9. 実装順序（段階的・各段で検証）

> ⚠️ **順序の肝（セルフレビュー 2026-06-19 で発見）**：③CSVを `daily/` へ移動した瞬間、Mac側 `generate_*.py` の入力パスが旧 `mt5_data/*.csv` のままだと**カレンダー生成がコケる**。だから「daily/への移動」と「Macパス変更」は**同一コミット群でセット**にし、どの瞬間も両マシンが壊れない状態を保つ（無停止移行）。③をVPS単独で先に動かさない。

**フェーズ0：準備（VPS先行OK・まだ動かさない）**
1. `scripts/vps_data_pool_push.sh` を配置（実行はしない）
2. タスクスケジューラ設定を下書き（有効化はフェーズ2）

**フェーズ1：箱＋Mac配管を一括（Mac中心・1コミット群で無停止移行）**
3. `mt5_data/daily/` 作成、③3CSVを `git mv` で移動
4. `.gitignore` に①追加 → `git rm --cached mt5_data/FractalWaveLog_*.csv`
5. `generate_*.py` / `run_daily_calendar.sh` の入力パスを `daily/` へ
6. `run_pipeline.sh` Step5 に②を追加
7. → **3〜6をまとめて commit → push**（Mac側が動く状態を崩さない）

**フェーズ2：VPS動脈ON（VPS作業）**
8. `git pull` で新構造を受信 → `vps_data_pool_push.sh` 手動テスト（push成功まで）
9. タスクスケジューラ有効化 → 翌日2回発火を確認

**フェーズ3：通し検証**
10. VPS push → Mac pull → 成績合流 → docs公開 → iPhone確認（1サイクル）

---

## 10. やってみて詰める点（未確定・割り切り枠）

> [[feedback_anti-perfectionism-true-meaning]]：方向性は確定。以下は実装で詰める。

- [ ] **push頻度**：1日2回が適切か、毎時要るか（フォワードで体感）
- [ ] **_EA suffixファイルの掃除**：`daily_aggregate_EA.csv` 等は回帰検証名残 → VPS Filesから削除して良い（無印と完全同一を確認済）
- [ ] **②のVPS化（将来）**：ADX_Weekly / H4PhaseAuto も手描き不要 → 系統B/C方式でEA化すればデータプール拡大。今回の射程外、次の大トラック候補
- [ ] **Mac watcherの監視方式**：git pull検知をどう実装するか（mtimeポーリング→`git fetch`比較 等）
- [ ] **タスクスケジューラ vs 常駐watcher**：VPSはスケジューラ採用だが、将来「EA出力検知で即push」にするなら別実装
- [ ] **conflict時の作法**：VPSは `daily/` のみ・Macは②docs のみ＝別ファイルで衝突しない設計だが、初回数サイクルは手動で挙動確認

---

## 11. 完了条件（この動脈が「通った」と言える状態）

1. VPSがRDP切断中も、タスクスケジューラで `daily/` を自動push し続ける
2. Macが起動→pullするだけで最新の signal_fires/daily_aggregate/daily_mfe_mae を得る
3. `mt5_data/` が両マシンで常時クリーン（pull --rebase が無事故）
4. 日次カレンダー3枚が、VPSデータ＋Mac成績の合流で公開更新される
```
