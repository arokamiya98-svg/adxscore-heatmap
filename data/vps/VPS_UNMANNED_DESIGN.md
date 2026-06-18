# VPS無人化 設計書 — 日次データの24h自動生成

> 起点: 2026-06-18 パラレルおぱ会議（Macおぱ実態調査 → VPSおぱ統合）
> **核心: CSVは「運ぶ」のではなく「VPSのMT5でその場生成」する**
> 関連台帳: `data/session_state/vps_setup_progress.md`

---

## 設計転換の要点
- 旧案（VPSおぱ初版）: CSVをGit経由でMac→VPS輸送し、VPS pythonで処理
- **新案（採用）**: 系統B/Cは入力CSV不要（MT5バー履歴から iATR/iADX 自前生成）→ **輸送ゼロ**。VPSにMT5常駐＋mq5をEA化すれば、その場で24h生成

## 日次は3系統
| 系統 | 出力CSV | スクリプト | 入力依存 | 配置判断 |
|------|---------|-----------|---------|---------|
| **A** トレード後付け | trades_enriched | FX(iPhone)→prepare_trade_input.py→trade_input.csv→Trade_Snapshot_Builder.mq5→pyマージ→HTML | trade_input.csv（外部=iPhone） | **当面Mac専管**（振り返り用途・月10-15回・RT不要） |
| **B** 日次環境集計 | daily_aggregate / daily_mfe_mae_48h | XAUUSD_Daily_Aggregate_v1 / _MFE_MAE_v1 | 不要 | **VPS無人化（EA化）** |
| **C** シグナル検証 | signal_fires | Signal_Fire_Logger_v1 | 不要 | **VPS無人化（EA化）★最重要** |

## MT5依存の核心（なぜVPSにMT5必須か）
- 5本とも iATR/iADX/iBarShift/CopyBuffer で過去バー再取得 = **MT5履歴＋インジエンジン必須**
- Python自前計算は値ズレリスク大 → ATR/ADXはMT5エンジンそのまま＝**研究データ一貫性100%保証**
- 5本とも Script型（`#property script` + OnStart, 手動ドロップ）→ watcher自動化しても「MT5でScript実行」が人間に残る＝**半自動の天井**

## VPS無人化の本命 = Script→EA化
- `OnStart`(1回) → `OnInit` + `OnTimer`(定期) / `OnTick`(監視) へ書換
- B/Cは入力非依存 → VPS常駐MT5＋EAで**完全無人化**（外部ファイル輸送ゼロ。バー履歴はMT5が自前で持つ）
- **★signal_fires の OnTick化が最大価値**:
  - 現状手動Script = 回した時点のシグナルしか拾えない → スリープ中の24h発火を取り逃す
  - EA化 = 取りこぼしゼロ → **Stage8フォワード検証が穴なしに**
  - 軸A（通知24h化, 6/18達成）と同じMT5常駐基盤に乗る＝**シナジー**

## Git合流（成果物push）の衝突設計 — Macおぱ調査A〜E
- **push対象 = `docs/*.html`（成果物）+ `data/weekly_waves.json` のみ**。`mt5_data/*.csv` は誰もcommitしない設計（最後に触ったのは e6025c3 "weekly update 2026-06-04"）→ 常に `M` で残る（正常・想定内）
- VPS=日次calendar HTML / Mac=週次heatmap HTML → **push対象が分離** → `pull --rebase`前提で衝突ほぼ無し
- **唯一の重なり = `data/weekly_waves.json`**（両方が触る場合）→ 片寄せ要検討
- `mt5_data/` と `.DS_Store` → **「Mac専管」運用を明文化**（物理 .gitignore は設計確定後に慎重に。既存追跡分の git rm --cached は影響大なので即断しない）

## VPS側の前提・注意
- VPS MT5 が **XAUUSD 接続＆ヒストリーDL必須**（ATR median: H1で 8週×5×24=960本＋48hトレース分）
- **EA常駐＝VPS MT5が落ちない事**（2GB OOM懸念 → Win2/3.5GB 推奨。EA化しながらメモリ実測で判断）
- **EA実行は AutoTrading 許可が前提**（B/Cは売買せずデータ出力のみだが、EA稼働にON必須）
- mq5の `FileOpen` は相対パス(MQL5/Files基準)＝**Mac→VPSでコード不変**（bash側の絶対パスだけ書換）

## 進める順番（Macおぱ提案）
1. **系統B（Daily_Aggregate）EA化** = 入力不要で一番ラク、最初の成功体験
2. **系統C（signal_fires）EA化** = 価値最大（フォワード完全化・軸Aシナジー）
3. **系統A** = 当面Mac、後回し（将来Macレス化なら trade_input.csv をgit輸送）

## 未確定・判断待ち
- [x] VPS MT5 前提確認（2026-06-18）: XAUUSD接続◎（HFMarketsGlobal-Live5に履歴あり）／terminal64 24h生存◎／**メモリ実態判明** ↓ 残=AutoTrading緑か・気配更新（あろさんGUI確認）
- [x] **メモリ圧迫の主犯=Claude Code自身**（claude5プロセスで RAM689MB/Commit2.5GB）。MT5は軽い（Commit162MB）。
  → **EA無人化(B/C)は2GBで着手可**（MT5+EA+Defender＝平常時1GB前後、おぱ不在なら余裕）。
  → **Win2(3.5GB)は「おぱ別荘常駐」用であってEA用ではない**。当面〈MT5+EA常駐／おぱは作業時来訪〉で2GB運用、逼迫が辛ければWin2。今すぐ課金不要。
- [ ] **signal_fires 実装2案**: 〈Signal_Fire_Logger を EA化〉 vs 〈v4インジに発火時CSV追記を足す〉— 両者のコード突き合わせで決定（後者はEA常駐を増やさずメモリ節約・発火ロジック一元化の利）
- [ ] Win2(3.5GB)アップグレード判断（EA常駐のメモリ耐性次第）
- [ ] weekly_waves.json の片寄せ方針（VPS/Macどちらに寄せるか）
