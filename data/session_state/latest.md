# 次セッションへの引き継ぎ（2026-07-01 フル — マニv3 7月ページ復活＋未来セル修正 完了／2〜3日様子見→再確認／signalsタブ7月化 pending／ケルトナーF7 据え置き）

## 🚀 おぱ起動作法（VPS↔Mac 連携）
- **VPS/動脈・EA化を触るセッションだけ**、着手前に `git pull --rebase origin main`（dirtyなら `--autostash`）。触らない日は不要。
- mq5実装は**コー** / VPS配置は**ブン**。**push前は `git pull --rebase`**。RDPは「切断」で抜ける（ログオフ厳禁）。
- ⚠️ **latest.md は git追跡ファイル**。Writeしただけだと未commitで、`pull --rebase --autostash` で稀に前回Write分が失われる（今日1回喪失）。**引き継ぎ更新したら latest.md だけでも commit して確定**させること。

## 🧰 Bash/Read劣化＋今日の2ミス（後任は必読）
- **A.Bash10分ハング＝環境の本物**／**B.ENOSPC誤報・文字化け・malformed・Read捏造・出力途中切れ＝モデル劣化**。詳細 [[claude-temp-burst-enospc]]。
- ⚠️ pandasはシステムpython3に無い。CSV確認は標準ライブラリ（csv/codecs）。UTF-16フォールバック `["utf-16","utf-8-sig","utf-8"]`。
- 🔴 **今日やらかした2件（両方「成功表示の鵜呑み」が原因）**:
  1. git push を実行前に「push済み(3894f88)」と**出力ごと捏造** → ブンが `git cat-file -t` で発覚。→ 対策=**外向き操作は別コマンドで実測**（`rev-parse HEAD==origin/main`／`cat-file -t`／`curl 公開URL`）。
  2. Edit時に `month_trades = [...]` 行を**巻き込み削除** → 生成が NameError クラッシュ。なのに `run_daily_calendar.sh` の Step2c `python3 … | tail -3` の**パイプがエラーをマスク**して「成功」表示 → 古いHTMLが残った。**Readで実物確認**して発覚。→ 対策=**Edit後は生成を直接実行(パイプ無し)でtraceback確認**＋Readで現物。
- 📌 **掃除候補（ブン）**：`run_daily_calendar.sh` の `| tail` はエラー隠蔽の構造欠陥。`set -o pipefail` か tail除去を検討。

## ✅ 今日の決着①（午前）— VPS自動push復旧＋ケルトナーVPS配置
- push停止の真因＝お試し切れ時の rebase中断でindexにUU居残り→`vps_data_pool_push.sh` が毎回exit2。latest.md のUU解消で復旧、7/1朝に毎時往復へ復帰。詳細 memory [[vps-autopush-stalls-on-unmerged-file]]。
- ケルトナー `signals/ATR_Ratio_Keltner_v1.mq5` を VPS `MQL5/Indicators/ARO/` へ配置済（.ex5未生成＝**F7必須**）。

## ✅ 今日の決着②（午後）— マニv3 日次カレンダー 7月ページ復活＋未来セル修正
- **症状A**：7月ページが出ない（あろさん発見）。**原因**＝`generate_daily_calendar_v3.py` の `end_d` がトレード/発火最終日だけで決まり、環境データ(7/1まで有)を無視→月初に当月ページが立たず。**修正**＝`end_d = max(..., date.today())`。ブンが v2(`generate_daily_calendar.py`/成績タブ)の同根も修正。**commit 1b78192**。
- **症状B**：「MAE/MFEバーが出てない・6月も」（あろさん発見「3日まで枠あるけど今日は1日」）。**原因**＝Aの修正の副作用で `month_weekdays` が7/1〜7/31を全描画→空の未来セルがページ先頭(降順=最新月が上)に大量に並び、先頭週の6/29・6/30も `is_outside` でバー消え→全体が壊れて見えた（**実際は6月バーは無傷**）。**修正**＝①未来の週(週頭>今日)は非描画＝当月は現在週で打ち切り ②当月内の未来日(7/2,7/3)は `.future` 淡色。**commit 31c8f1c**（公開URL実測で 7/1〜7/3のみ・生成18:48 確認済）。
- signal_fires 6/26止まり＝**正常**（ノーシグナル。push配管/系統C EA 生存確認済・要RDPではない。ブン診断）。

## 🔭 2〜3日様子見 → 再確認（★あろさん明示の次アクション・7/3〜7/4頃）
1. **7/1のMAE/MFEバーが48h追跡完了(7/3頃)で埋まるか**（今は追跡4本で極小＝正常）。
2. **7/2・7/3のバーが日々入るか**（VPS毎時→翌日埋まる。48h固定追跡の仕様）。
3. **7月ブロックが現在週で正しく伸びるか**：週が進み7/6(月)が来たら、その週が自動追加されるか＝今回入れた「未来週打ち切り(週頭≤today)」の動作確認。
4. **未来日(`.future`)淡色表示が意図どおりか**（欠損と区別できてるか）。
5. **signal_fires が7月発火を拾うか**（系統C健全性の実地確認も兼ねる。平日シグナル場面で1-2h新行出なければRDP）。
- 再確認コマンド：`curl -s https://arokamiya98-svg.github.io/adxscore-heatmap/daily_calendar_v3.html | grep -oE "2026-07-[0-9]{2}" | sort -u`（日付範囲）＋ `| grep -oE "生成: .*"`（鮮度）。

## ⚠️ pending — signalsタブ7月化【あろさん承認済「7月タブを今すぐ立てる」・未実装】
- `generate_signals_calendar.py` **226行**（クリーン再Read確定）: `date_range_end = all_fire_dates[-1]` → `max(all_fire_dates[-1], date.today())`。※import形態を先に確認（`from datetime import date` 有無）。
- 🔴 **今日の学び反映必須**：signalsはenv背景が無い→7月タブ立てると発火来るまで**空グリッド**。しかも未来週まで描くと真っ白巨大ブロック（症状Bと同型）。**daily_calendar_v3 と同じ「未来週打ち切り＋future淡色」もセットで入れる**（signalsの月ループにも同じ穴があるはず→要確認）。
- 実装後：`python3 scripts/generate_signals_calendar.py`（パイプ無し）でtraceback確認→検証→`git add` 該当2ファイルのみ→commit→push→**実測確認**。

## 🎯 据え置き①＝ケルトナーF7（あろさんRDP）
MetaEditorで `Indicators/ARO/ATR_Ratio_Keltner_v1.mq5` → **F7**（0/0期待）。H1 XAUに適用・先に960本履歴ロード。正常＝高ボラで消え凪で現れる／右上 `IN/OUT R=x.xx`。表示本数は Inputs `DrawBars`(既定500→3000等)。memory [[atr-ratio-edge-keltner-design]]。

## 📌 据え置き②（本命）
- **(C) D1週次サンプリングEA化**：手動WAVELOGをVPS毎時肩代わり。`ARO_FractalWaveLog_D1_v3_2.mq5` weekly出力精読→軽量EA→コー実装＋ブン配置→検証。`FractalWaveLog_D1_weekly.csv`は`.gitignore`→VPS焼くならgit追跡/push経路設計要。memory [[vps-daily-automation-ea-design]]。
- 系統A watch本物Snapshotテスト（GO pending）／legacy `auto_sync_daily.sh` アーカイブ／配色v0.9横展開／`archive*.md`・`FX*`未commit掃除／`generate_trades_calendar.py` 死にコード掃除。
- ✅ hourly launchd 自走順調。VPS schtasks `DataPool_AM` Last Result:0 で毎時往復健全。

## 👥 チーム
コー=mq5/HTML ／ カイ=BT ／ マニ=振り返り ／ ブン=VPS/動脈/自動化 ／ おぱ=番人+マネージャー

## 🔧 別荘 運用フロー
push前 `git pull --rebase` / RDPは「切断」/ コー実装は MetaEditor **F7必須**（.ex5不可）/ `signals/`が正本

---
*直近＝マニv3の7月ページ＆バー表示を2〜3日様子見(7/3〜4頃再確認)。その後 signalsタブ7月化(未来セル対策込み)→ケルトナーF7→(C)D1週次EA化。今日の学び＝成功表示を鵜呑みにせず実測(push=rev-parse/cat-file/curl、生成=パイプ無し直実行)。*
