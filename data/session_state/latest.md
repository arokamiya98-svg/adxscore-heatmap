# 次セッションへの引き継ぎ（2026-06-19 日次動脈フェーズ1完了：Mac無停止移行）

## 🎯 今ここ — フェーズ1（Mac無停止移行）完了 ✅ push済 `d4be4ce`
Macおぱが設計書 `data/vps/日次動脈_DESIGN_v1.md` §9 フェーズ1（3〜7）を実装し、**1コミットで無停止移行**完了。VPSは動脈OFF（タスク未登録）だったので安全に移行できた。**次はVPS側フェーズ2（動脈ON）**。

## ✅ フェーズ1でやったこと（コミット `d4be4ce`・14 files / +26 -254）
1. `mt5_data/daily/` 新設、③日次3本を `git mv`（signal_fires / daily_aggregate / daily_mfe_mae_48h、97-99%一致のrename）
2. `.gitignore` に ①手描き `mt5_data/FractalWaveLog_*.csv` 追加 → `git rm --cached`（5本・**実体は手元に残存確認済**）
3. `generate_{daily_calendar,daily_calendar_v3,signals_calendar}.py` の入力パスを `daily/` へ（実コード定義6箇所のみ・コメントは温存）
4. `run_daily_calendar.sh` Step1 コピー先=`daily/`（mkdir/dst/signal_fires cp の3点）
5. `run_pipeline.sh` Step5 の `git add` に②（ADX_Weekly_v4/v3 + H4PhaseAuto）追加（§6・M放置解消）
6. **検証 `run_daily_calendar.sh --no-open --no-publish` → カレンダー3枚 全PASS**

> 💡 **検証が移行漏れを1個炙り出した**：Step2b（signals生成）の起動条件 `[ -f "$DEST/signal_fires.csv" ]` が旧パスのままで初回スキップ→ `daily/` 追従に修正して再検証で3枚とも再生成確認。無停止移行の検証プロセスが機能した。

## ▶ 次の起点 = VPSフェーズ2（VPS作業・動脈ON）
1. VPSで `git pull`（`d4be4ce` 受信＝新構造 `mt5_data/daily/` が来る）
2. `DRY_RUN=1 bash scripts/vps_data_pool_push.sh` で最終確認（予行は済）→ 本実行 `bash scripts/vps_data_pool_push.sh`（push成功まで）
3. §7 `schtasks` 2行登録（AM 08:10 / PM 23:10・実行条件「**ログオン中のみ実行**」推奨／TZ確認）
4. → **フェーズ3 通し検証**：VPS push → Mac pull → 成績合流 → docs公開 → iPhone確認（1サイクル）

## ⚠️ Macからの申し送り（フェーズ2前に一読推奨）
- **②はM放置のまま残してある**（ADX_Weekly_v4 / H4PhaseAuto が modified）。フェーズ1は構造変更のみに限定したため。→ 次回 `run_pipeline.sh` 実行で Step5 の add に乗って自動commit＝解消。VPSは②に触らない設計なので衝突しない。
- **`scripts/sync_mt5_data.sh` に既存のM**（フェーズ1着手前から）。フェーズ1と無関係なので**コミットから除外**した。中身が何の変更か要確認（週次①②コピー用＝daily/対応は不要のはず）。
- **`docs/*.html` 3枚は検証で再生成された（未commit）**。フェーズ1の純度のため含めず。次回 `run_daily_calendar.sh`（--publish）で正規push される。
- **`mt5_data/{trade_input,trades_enriched}.csv` も tracked**（系統A中間/出力）。設計書§1の認識「trades_enriched は data/trades/(gitignore) にしか無い」と実態がズレ。系統A=Mac専管なので今回は不介入。扱いは別途要検討。

## 📋 据え置き（設計から継続）
- 系統A（トレード後付け・Mac専管・後回し）
- ②のVPS化（将来の大トラック）／Win2(3.5GB)判断（EA2本常駐メモリ実測後）
- `_EA` suffixファイル掃除（無印とdiff0の回帰名残）

## 🔧 別荘 運用フロー（継続）
- 別荘からpush前は必ず `git pull --rebase`
- RDPは「切断」で抜ける（ログオフ厳禁）
- コー実装EAは MetaEditor **F7再コンパイル必須**（.ex5コマンドラインはロード不可＝556）
- `signals/`が正本 → MT5 `Experts\ARO\`(EA) / `Scripts\ARO\`(Script) へコピーしてF7

---
*次の起点＝VPSフェーズ2（`vps_data_pool_push.sh` 本実行→`schtasks`登録）→フェーズ3通し検証。設計書 `data/vps/日次動脈_DESIGN_v1.md`。Mac側フェーズ1は `d4be4ce` で完了・origin同期済。*
