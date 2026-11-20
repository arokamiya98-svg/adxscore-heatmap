# コー指示書: DXY環境札 v3 — 合成DXY（Exness FX5ペア）への載せ替え

> 作成: 2026-11-20 おぱ / 親SPEC: `data/scriptable/SPEC_dxy_env_card_v1.md`
> 背景: HFM口座アーカイブ（11/12〜価格停止）→ Exnessセント（`XAUUSDc`）へ移行。Exnessに USDIndex が無く、DXY札が 11/12 で凍結（⚠表示中）。
> あろさん意向: DXY札は「地味にいい情報」＝残したい。

---

## 0. 方針（一行）

**ICE DXYの公式式をExnessセントのFX5ペアで再現した合成DXYを作り、HFM USDIndexとの一致を検証してから系統B EAに載せる。検証合格まで本番に触らない。**

## 1. 合成式

ICE公式（6通貨）:
```
DXY = 50.14348112 × EURUSD^-0.576 × USDJPY^0.136 × GBPUSD^-0.119
                  × USDCAD^0.091 × USDSEK^0.042 × USDCHF^0.036
```
Exnessセントの在庫（あろさん確認 2026-11-20）: `EURUSDc` `USDJPYc` `GBPUSDc` `USDCADc` `USDCHFc` ✅ ／ **USDSEK ❌**

→ **SEK項を落とした5項で計算**（本家ウェイトの95.8%）。指数は乗数を変えてもADX/DIが変わらないので、定数は 50.14348112 のまま、ウェイトの再正規化もしない（シンプル優先・検証で不足なら再検討）。

- `Forex_Indicator` グループの `USDEUCc` 等はセント換算用の別物＝使わない
- セント口座でもFXレートはスタンダードと同じ値（ロット単位が違うだけ）

## 2. 作り方（推奨: カスタムシンボル方式）

1. 5ペアの **M1** 足を取得 → 時刻で突合（欠けた分は直前値で埋める） → M1ごとに合成値を計算
   - 合成M1のOHLC: O/H/L/C それぞれ成分のO/H/L/Cから計算（Hは EUR/GBP が負の指数なので **EURUSD・GBPUSDのLow** を使う、等の符号に注意。厳密でなくてよい＝H1に集約すれば誤差は吸収される）
2. `CustomSymbolCreate("DXY_SYNTH")` → `CustomRatesUpdate` でM1を書き込み → MT5がH1を自動生成
3. 以降は普通に `iADX("DXY_SYNTH", PERIOD_H1, 56)` が使える
   - おまけ: あろさんがチャートで DXY_SYNTH を開ける（認知の道具にもなる）

M1の履歴が足りない場合は M5 にフォールバックして可。どちらを使ったかはログとCSVヘッダに残す。

## 3. Phase 1 — 検証（★ここを通るまで Phase 2 禁止）

### 3.1 コー: 検証用Script
- `data/dxy/DXY_ADX_Timeseries_v1.mq5` をベースに、`DXY_Synth_Timeseries_v1.mq5` を作成
- 出力: `DXY_Synth_Timeseries_v1.csv` — **v1と同じ列**（Time,Close,ADX,DI_Plus,DI_Minus,ATR_S,ATR_L,Med960,Ratio）・UTF-16
- 期間: 2024-01-01〜最新（v1との重なり＝2024-01〜2026-07-14）
- 実行場所: Exnessにつながった MT5（VPS か Mac。履歴が深い方）

### 3.2 カイ: 突合（`data/dxy/validate_yahoo_dxy.py` を流用）
- 正解: `data/dxy/DXY_ADX_Timeseries_v1.csv`（HFM USDIndex・13,687本）
- ⚠ サーバー時刻が違う（HFM GMT+2/3 → Exness GMT+0 のはず）＝ validate_yahoo の時刻オフセット自動検出を使う
- 見る数字（Yahoo不合格時と同じ物差し）:

| 指標 | Yahoo（不合格） | **合格ライン** |
|------|----------------|---------------|
| di_spread 相関 | 0.596 | **≥ 0.90** |
| 平均絶対差 \|spread\| | 5.18 | **≤ 2.0** |
| 深さラベル一致率（<2/2-5/5-10/≥10） | 33.4% | **≥ 75%** |
| di_dir 一致率 | — | **≥ 90%** |

- 判定:
  - **合格** → 閾値そのまま Phase 2 へ
  - **ラベル一致だけ不足**（相関は高い） → 合成側の分布で閾値を引き直す案をおぱに返す（滞在率 23/29/32/17% を保つ分位点で）
  - **相関が低い** → 不採用。おぱに返す（原因の推定付き）

## 4. Phase 2 — 本番組み込み（合格後）

- `signals/XAUUSD_DailyBatch_EA_v1.mq5`:
  - OnTimer の先頭で DXY_SYNTH を差分更新（最新M1まで）してから既存の Dxy_GenerateCsv を回す
  - input `DXY_Symbol` の初期値 → `"DXY_SYNTH"`、成分5ペアとウェイトは input 化（銘柄名サフィックス `c` もここ）
  - 成分のどれかが取れない回は既存と同じく **DXY出力のみskip・既存ファイルを壊さない**
- **出力CSV `dxy_env.csv` のスキーマは不変** → Mac側 generator・ウィジェットは改修ゼロ
- SPEC_dxy_env_card_v1.md に「データ源: HFM USDIndex（〜2026-11-12）→ 合成DXY（2026-11-20〜）」を追記
- VPS配置は VPSおぱ（pull → MQL5へコピー → metaeditor CLI compile → チャートへ再アタッチはあろさん）

## 5. 禁止・注意

- 深さラベルは**ラベル層**。点数化しない（SPEC §1）
- 検証前に本番の dxy_env.csv を合成値で上書きしない（凍結中のHFM値＋⚠の方が「嘘をつかない」）
- 成分の欠損を直前値で埋める時、**週末をまたいだ埋めはしない**（月曜の窓開けを0変化にしない）
