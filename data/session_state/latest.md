# 次セッションへの引き継ぎ（2026-07-01 — VPS自動push復旧＋ケルトナーVPS配置完了／次＝あろさんF7適用→(C) D1週次EA化）

## 🚀 おぱ起動作法（VPS↔Mac 連携）
- **VPS/動脈・EA化を触るセッションだけ**、着手前に `git pull --rebase origin main`（dirtyなら `--autostash`）。VPSとMacは同じmainを書き合うパラレル運用。**触らない日は不要**。
- mq5実装は**コー** / VPS配置は**ブン**（`.claude/agents/bun.md`）。**push前は `git pull --rebase`**。RDPは「切断」で抜ける（ログオフ厳禁）。

## 🧰 Bash/Read劣化（2種類混同しない）
- **A.Bash10分ハング＝環境の本物**／**B.ENOSPC誤報・文字化け・malformed・Read捏造＝モデル劣化**（再起動案件）。詳細 [[claude-temp-burst-enospc]]。
- ⚠️ **pandasはシステムpython3に無い**。CSV確認は標準ライブラリ（csv/codecs）。UTF-16フォールバック `["utf-16","utf-8-sig","utf-8"]`。

## ✅ 今日の決着（7/1）— VPS自動push停止の修復＋ケルトナー配置
- **症状**：VPS自動pushが6/29 17時以降停止（VPSお試し期間切れでセッション断）。本契約復帰後もpushゼロ。
- **真因**：お試し切れ時の `git pull --rebase` が `data/session_state/latest.md` でコンフリクト中断 → **indexに未解決(UU)エントリが居残った**。その間Macはoriginを6/30まで進めてた。毎時schtasksは起動しCSVコピーも成功(③3/3 ②2/2)してたが、`vps_data_pool_push.sh`(84行) の `git pull --rebase` が「unmerged files」で毎回 **exit 2**（=schtasks Last Result:2）→ commit/push到達せず。
- **対処**：latest.md のUU解消（HEADに既に正版ありで `git add` のみで解決）→ push.sh手動実行 → autostash pullがMac6/30版取込み → push成功。**翌朝までに 04:00〜08:00 毎時往復が復帰**（Last Result:0確認）。
- 📌 **教訓＝VPS自動push停止時の一次診断**：`git diff --name-only --diff-filter=U` でUU確認 → vps_pool.log末尾 → schtasks Last Result。memory [[vps-autopush-stalls-on-unmerged-file]] に記録。
- **ケルトナーVPS配置完了**：`signals/ATR_Ratio_Keltner_v1.mq5`（インジ）を VPS `MQL5/Indicators/ARO/` へコピー済（ARO系の正規置き場）。**.ex5は未生成＝あろさんRDPでF7必須**。

## 🎯 次の一手＝ケルトナーF7適用（あろさんGUI）→ 動作確認
1. MetaEditorで `Indicators/ARO/ATR_Ratio_Keltner_v1.mq5` → **F7**（0/0期待）
2. H1 XAUUSD に適用。**先に960本(=約40日)履歴ロード**（足りないと中央値計算不可で最新も消える）
3. 正常＝**高ボラで消え凪で現れる**／右上 `IN/OUT R=x.xx`／既定 EMA32・TargetATR14・Mult2.0(中心±28)・Gate0.70-1.40
- **表示本数を増やす方法（あろさん要望に回答済）**：インジ右クリック→パラメータ編集→Inputs の **`DrawBars`(既定500)を3000等に**（再コンパイル不要・即反映）。ただし**チャート最古960本は永久に床**（Ratio中央値が前960本を要求）。床も消したいなら `UseRatioGate=false`（高ボラ消し演出は無くなる）。要・ツール→オプション→チャート「最大バー数」拡大＋Home長押しで履歴ロード。
- 確認後 → Mult調整・SELL側(H4ゲート)拡張。memory: [[atr-ratio-edge-keltner-design]]。

## 📌 据え置き（本命の継続タスク）
- **(C) D1週次サンプリングEA化**（6/29本命・継続）：手動WAVELOGをVPS毎時肩代わり。`ARO_FractalWaveLog_D1_v3_2.mq5` のweekly出力が手描き依存か精読→軽量EA設計→コー実装＋ブンVPS配置→検証(翌週枠が自動で立つか)。`FractalWaveLog_D1_weekly.csv`は現状`.gitignore`→VPS焼くならgit追跡/push経路の設計要。memory: [[vps-daily-automation-ea-design]]。
- 系統A watch本物Snapshotテスト（GO pending）／legacy `auto_sync_daily.sh` アーカイブ（数日安定後）。
- 配色v0.9 全体通し横展開（BU=`rgba(235,175,55)`/PD=`rgba(150,110,205)`/RANGE=灰）。
- `archive*.md`・`FX*` 未commit溜まり / `sync_mt5_data.sh` の v3.csv警告掃除。
- ✅ hourly launchd 自走順調。VPS schtasks `DataPool_AM` も Last Result:0 で毎時往復健全。

## 👥 チーム
コー=mq5/HTML ／ カイ=BT ／ マニ=振り返り ／ ブン=VPS/動脈/自動化 ／ おぱ=番人+マネージャー

## 🔧 別荘 運用フロー
push前 `git pull --rebase` / RDPは「切断」/ コー実装は MetaEditor **F7必須**（.ex5不可）/ `signals/`が正本

---
*次＝ケルトナーF7適用＆「高ボラで消え凪で現れる」目視確認（DrawBarsで過去本数調整可）。その後 (C) D1週次サンプリングEA化が本丸。VPS自動pushは7/1朝に毎時往復へ復旧済・無人OK。*
