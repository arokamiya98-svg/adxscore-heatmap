# ブン指示書 — ②自動集計のVPS書き移行＋VPS配置（v1）

> 発行: 2026-06-26（おぱ）
> 前提: EA 2本 実装・コンパイル0/0・**Mac実機回帰合格**（確定週一致・進行中週W26出力確認）済み
> 関連: `コー_指示書_②自動集計_*.md`（EA実装）/ `日次動脈_DESIGN_v1.md`（本籍）

---

## 0. 設計思想（あろさん明言・2026-06-26）★この移行の根っこ

**CSVは「場所(Mac/VPS)」でなく「あろさんの手作業 か / 自動化できる か」で分ける。**

| 区分 | 中身 | 置き場 |
|---|---|---|
| **手作業の聖域** | ①手描きwavelog（FractalWaveLog・トレンドライン認知行為）/ 系統A Snapshot（トレードCSV→enriched） | **Mac**（あろさんが手で作る） |
| **自動化の前線** | ②自動集計（ADX_Weekly / H4PhaseAuto・今EA化）/ ③日次daily（系統B/C・既配置） | **VPS 24h無人** |

狙い＝**手で作れないところは全部自動化し、あろさんは手描きとSnapshotという認知の聖域に集中する。**
→ これまで②は「Macが手動Script実行→push」だった。これを**VPS毎時EA→push**に倒す。

---

## 1. 移行対象と成果物
- VPS配置するEA: `signals/ARO_H4PhaseAuto_EA_v1.mq5` / `signals/ADX_Weekly_Above_EA_v1.mq5`
- 出力CSV（VPSが書く・UTF-16）: `mt5_data/ADX_Weekly_Above_v4.csv` / `mt5_data/H4PhaseAuto_weekly.csv`
  - ※ ③dailyと違い `mt5_data/` **直下**（`daily/` サブフォルダでない）

---

## 2. ブンがやること（スクリプト・配管・ドキュメント）

### (B) push配管の拡張
- `scripts/vps_data_pool_push.sh` / `.bat` を確認。現状③daily（signal_fires/daily_aggregate/daily_mfe_mae_48h）のみ運んでるなら、**②2本（ADX_Weekly_Above_v4.csv / H4PhaseAuto_weekly.csv）も** VPS MQL5/Files → `mt5_data/` 直下へコピーしてpushするよう拡張。
- ②はUTF-16のままコピー（変換しない）。

### (C) Mac側の②書き込みを止める ★最重要（二重書き＝コンフリクト防止）
- `scripts/sync_mt5_data.sh` / `run_pipeline.sh` で、②（ADX_Weekly_Above_v4.csv / H4PhaseAuto_weekly.csv）を Mac MQL5/Files → `mt5_data/` にコピーして `git add`/push している経路を**停止**する。
- 移行後の Mac は②を**受信のみ**（`hourly_sync` が pull → `process_wavelog.py` → heatmap再生成）。
- ⚠️ MacでEAをアタッチしたまま（検証で動かした2本）でも、**mt5_dataへのコピー経路さえ止めればpushされない＝無害**。EAを外すかは任意。要は「②をpushするのはVPSだけ」にする。
- ① 手描きwavelog（FractalWaveLog系）のMac書き経路は**温存**（聖域・触らない）。

### (D) 住み分けドキュメント更新
- `CLAUDE.md` §7/§15 の「②=Macがpush」を「**②=VPSが毎時EAで書く**」に更新。CSV3分類を「手作業/自動化」軸で書き直す（§0の表を反映）。
- `data/vps/日次動脈_DESIGN_v1.md` にも②のVPS書き移行を反映。

---

## 3. あろさん手動パート（ブンは手順書を整える・実機RDP操作は本人）
1. VPS RDP → MetaEditorで2本を**F7コンパイル**（.ex5生成）
2. XAUUSDチャートにアタッチ: **ADX_Weekly_EA=H1 / H4PhaseAuto_EA=H4**、**AutoTrading ON**
   → 既存 系統B/C EA と合わせ**チャート計4枚**（あろさん「4枚で稼働可」確認済）
3. RDPは「**切断**」で抜ける（ログオフ厳禁＝EA継続）
> ブンはこの3手順を分かりやすい手順書（コピペ可）として用意して返すこと。

---

## 4. 地雷（同根の穴）
- VPSが書くファイルが②2本増える → push前 `git pull --rebase` 必須（既存作法・徹底）。
- **(C)が完了するまで本番移行しない**。Mac/VPS両方が②を書くとコンフリクト地獄。順序は (B)(C)整備 → あろさんVPS配置 → 観察。
- ②CSVはheatmapの入力。VPS push失敗で②が古いとheatmapが古くなる → push成否ログを確認。
- 進行中週(W26)が毎時動く＝②は毎時差分が出てコミットが毎時増える（③と同じ常態）。**固定値件数assertを置かない**（動的整合性へ・既知地雷 [[vps-daily-automation-ea-design]]）。
- ①手描き(Mac)と②(VPS)は同じ `process_wavelog.py` でマージされる。①が進行中週空でも②が埋まる設計は確認済（進行中週＝指標だけ毎時最新）。

---

## 5. 完了条件
- (B)(C)(D) 整備完了・commit
- あろさんVPS配置後、VPS 2本EAが毎時②CSV更新→push
- Mac `hourly_sync` が②受信 → **進行中週W26のADXスコア・H4Phaseが毎時動く**heatmap再生成
- Mac側②書き経路停止（二重書き無し）を実際のpushログで確認
- 1〜2時間観察してコンフリクト無し

## 6. 完了後にメインおぱへ返すこと
- (B)push配管拡張の差分 / (C)Macで止めた経路（スクリプト名・箇所）/ (D)ドキュメント更新箇所
- あろさん向けVPS配置手順書
- 観察結果（毎時更新が回ったか・コンフリクト有無）

> mq5ロジック・戦略判断・閾値はやらない（コー/おぱの領分）。インフラ配管・住み分け・地雷潰しに徹する。判断が要る箇所はメインおぱへ質問で返す。
