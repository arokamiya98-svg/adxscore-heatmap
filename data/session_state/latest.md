# 次セッションへの引き継ぎ（2026-06-30 — ATR Ratio点灯ケルトナー実装完了→VPS配置へ）

## 🚀 おぱ起動作法（VPS↔Mac 連携）
- **VPS/動脈・EA化を触るセッションだけ**、着手前に `git pull --rebase origin main`（dirtyなら `--autostash`）。VPSとMacは同じmainを書き合うパラレル運用。**触らない日は不要**。
- mq5実装は**コー** / VPS配置は**ブン**（`.claude/agents/bun.md`）。**push前は `git pull --rebase`**。RDPは「切断」で抜ける（ログオフ厳禁）。

## 🧰 Bash/Read劣化（2種類混同しない）
- **A.Bash10分ハング＝環境の本物**／**B.ENOSPC誤報・文字化け・malformed・Read捏造＝モデル劣化**（再起動案件）。詳細 [[claude-temp-burst-enospc]]。
- ⚠️ **今日6/30 おぱがRead捏造を1回やらかした**（latest.md読まずに結果を捏造→Write拒否で発覚）。Bツールは実際に呼ぶ。
- ⚠️ **pandasはシステムpython3に無い**。CSV確認は標準ライブラリ（csv/codecs）。UTF-16フォールバック `["utf-16","utf-8-sig","utf-8"]`。

## ✅ 今日の流れ（6/30）— ATR Ratio点灯ケルトナー 構想→BT→実装
- **あろさん構想**：ケルトナーの「幅＝収束待ち基準(14)」＋「ATR Ratioで表示ON/OFF（高ボラで消す）」。14はScriptableの`→14.0`と同じ"ボトムアウト待ち基準"＝認識ツール群（Scriptable／収束雲／ケルトナー）で**14基準が一本化**。
- **カイBT分析**完了 → `data/bt/PATTERN_REGIME_MAP_v2_AtrRatioEdge.md`。
  - Ratio定義 = `iATR(H1,16) ÷ 直近960本中央値`（=BT `CalcMedian` 完全一致）。
  - 買い優位 **0.70-1.00**(PF1.88) ／ 売り優位 **1.00-1.20×DN局面**(PF2.45・頑健) ／ **≥1.20はSELL死亡**(BUYは生存)。点灯条件は**方向非対称**。BT局面UP80%偏りで買い帯は現DN局面では割引。
- **実装完了**：`signals/ATR_Ratio_Keltner_v1.mq5`（コー枠切れをおぱが巻き取り）。中心EMA32／幅=TargetATR(14)×Mult／`UseRatioGate`でRatio0.70-1.40だけ点灯／DrawBars500で負荷対策。

## 🎯 次の一手＝VPS配置（あろさんGO済・VPSでやる流れ）
あろさんは**Windows App(RDP)でVPSのMT5デスクトップを常時確認できる** → VPSチャートに常駐させればインジ確認いつでも可（iPhone MT5アプリにカスタムインジは映らないがRDPなら映る＝制約回避）。
**VPS側手順**：
1. `git pull --rebase origin main` で `signals/ATR_Ratio_Keltner_v1.mq5` 取得
2. VPSのMT5 `MQL5/Indicators/` にコピー
3. MetaEditorで **F7コンパイル**（インジ。Script/EAではない）
4. H1 XAUUSDに適用。**960本(=H1約40日)履歴をロード**してから（足りないと最新も消える）
- 設計メモ：Mult=2.0(中心±28)。収束雲±14に揃えるならMult=1.0。正常動作＝**高ボラで消え凪で現れる**。右上ラベル`IN/OUT R=x.xx`。memory: [[atr-ratio-edge-keltner-design]]。

## 📌 据え置き
- **(C) D1週次サンプリングEA化**（前回6/29本命・継続）：手動WAVELOGをVPS毎時肩代わり。`ARO_FractalWaveLog_D1_v3_2.mq5` のweekly出力が手描き依存か精読→軽量EA設計→コー実装＋ブンVPS配置→検証(翌週枠が自動で立つか)。`FractalWaveLog_D1_weekly.csv`は現状`.gitignore`→VPS焼くならgit追跡/push経路の設計要。memory: [[vps-daily-automation-ea-design]]。
- 系統A watch本物Snapshotテスト（GO pending）／legacy `auto_sync_daily.sh` アーカイブ（数日安定後）。
- 配色v0.9 全体通し横展開（BU=`rgba(235,175,55)`/PD=`rgba(150,110,205)`/RANGE=灰）。
- `archive*.md`・`FX*` 未commit溜まり / `sync_mt5_data.sh` の v3.csv警告掃除。
- ✅ hourly launchd 自走順調（:10毎時 ExitStatus=0）。`hourly_sync.log` 時々確認でOK。

## 👥 チーム
コー=mq5/HTML ／ カイ=BT ／ マニ=振り返り ／ ブン=VPS/動脈/自動化 ／ おぱ=番人+マネージャー

## 🔧 別荘 運用フロー
push前 `git pull --rebase` / RDPは「切断」/ コー実装は MetaEditor **F7必須**（.ex5不可）/ `signals/`が正本

---
*次＝VPS配置（pull→Indicators→F7→H1適用→960本履歴）。「高ボラで消え凪で現れる」目視確認後、Mult調整・SELL側(H4ゲート)拡張。*
