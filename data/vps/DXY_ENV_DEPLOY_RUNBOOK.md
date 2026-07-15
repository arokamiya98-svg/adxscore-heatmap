# DXY環境札 VPSデプロイ runbook（あろさんRDP 1回で完走）

> 作成: 2026-07-15 おぱ（ブン枠の巻き取り）/ SPEC: `data/scriptable/SPEC_dxy_env_card_v1.md`
> 対象: 系統B EA `XAUUSD_DailyBatch_EA_v1` v1.10 差替え（DXY出力追加）
> 前提: Mac側で実装一式コミット・push済みであること（EA正本=signals/）

---

## Step 0: 接続と repo 健全性チェック（Git Bash）

```bash
cd /c/Users/Administrator/adxscore-heatmap
git diff --name-only --diff-filter=U     # ← 何か出たらSTOP（UU居残り=永久push停止の既知罠。先に解消）
git status --short                        # 想定外のdirtyが無いか一瞥
git pull --rebase --autostash origin main
tail -5 vps_pool.log                      # 直近の毎時pushが正常か（"OK push 完了"）
```

- pull で `signals/XAUUSD_DailyBatch_EA_v1.mq5` v1.10 と `scripts/vps_data_pool_push.sh`（dxy_env.csv対応）が届く
- push script は**次の毎時起動から**新リストで走る（今走ってる分は旧版・正常）

## Step 1: USDIndex の気配値と履歴

1. MT5 気配値表示に **USDIndex** があるか。無ければ 銘柄一覧（Ctrl+U）から追加
2. USDIndex の **H1チャートを一度開く**（履歴DLトリガ）。数分放置してバーが過去まで埋まるのを確認
   - 目安: 2024年まで遡れればADX(56)は即安定。浅くても**EAはDXY部だけスキップ→毎時自己回復**（XAU側2CSVは無影響）

## Step 2: EA差替え（F7必須・.ex5持ち込み不可）

1. repo の `signals/XAUUSD_DailyBatch_EA_v1.mq5` を MT5 データフォルダの `MQL5/Experts/`（既存EAと同じ場所）へ上書きコピー
2. MetaEditor で開いて **F7** → `0 errors, 0 warnings` 確認
3. 既存のアタッチ先チャート（XAUUSD）で EA を**再アタッチ**（inputsはデフォルトのまま: `DXY_Symbol=USDIndex` / `DXY_ADX_Period=56`）
4. **AutoTrading ON** と ニコちゃんマーク😊 を確認
5. エキスパートログに DXY関連のエラーが無いか一瞥（履歴不足のWARNはOK＝自己回復する）

## Step 3: 検収（次の毎時を1回見るだけでOK）

VPS側（毎時 :00 過ぎ）:
```bash
ls -la /c/Users/Administrator/AppData/Roaming/MetaQuotes/Terminal/D0E8209F77C8CF37AD8BF550E51FF075/MQL5/Files/dxy_env.csv
tail -5 /c/Users/Administrator/adxscore-heatmap/vps_pool.log   # "OK push 完了 (③daily=4 ②agg=2)" になる
```

Mac側は全自動（RDP後1〜2時間以内に順次）:
1. `mt5_data/daily/dxy_env.csv` 受信（hourly_syncのpull）
2. `docs/d1_env.json` に `"dxy"` ブロック出現
3. 公開URL確認: `https://arokamiya98-svg.github.io/adxscore-heatmap/d1_env.json`
4. iPhoneのd1_env_widgetに `DXY ⬆/⬇ …` 行（**新しいwidget jsの端末貼り替えが先に必要・APIキー不要**）

## Step 4: 抜け方

- RDPは**「切断」**で抜ける（**ログオフ厳禁**＝schtasks/credentialが死ぬ）

## ロールバック

- EAのみ差し戻し: `git log --oneline signals/XAUUSD_DailyBatch_EA_v1.mq5` で前版に checkout → F7 → 再アタッチ
- dxy_env.csv が残っても無害（generatorは古いdateを出す→widgetに⚠が付くだけ）。完全撤去はファイル削除＋コミット
- 既存XAU側2CSV（daily_aggregate / mfe_mae）はDXY改修と独立（コー実装で分離済み）

## 地雷リマインダ（本籍doc §12 より）

- UU未マージ居残り → pushだけ永久に届かない（Step 0の diff-filter=U が検知器）
- schtasks の Last Result `0x0` 確認は タスクスケジューラ → `vps_data_pool_push`
- 「WARN: 未生成 dxy_env.csv」はEA差替え**前**のログにだけ出る想定ノイズ
- USDIndexは限月ロールあり: 初回ロール跨ぎ週にDIの連続性を目視（SPEC §7-3）
