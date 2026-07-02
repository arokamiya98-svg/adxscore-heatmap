# SPEC: ATR_Ratio_Timeseries_v1.mq5（反転×H4収束 共起検証の基盤時系列）

> 作成: 2026-07-02 ／ 発注: おぱ → 実装: コー
> 目的: 「価格反転（トレンド転換）時にH4 ATRが収束入りしていることが多いか」を検証するための
> **H1バーごとの H1_Ratio / H4_Ratio 時系列CSV** を出力する Script。
> 反転点との突合・ベースレート・到達順序の分析は全て Mac側 Python で行う。
> mq5 は時系列を吐くだけ＝シンプルに保つ。

---

## 1. 種別・置き場所

- **Script型**（EAではない。1回実行で完結）
- 正本: `data/bt/ATR_Ratio_Timeseries_v1.mq5`
- 実行: あろさんが MT5 の H1 XAUUSD チャートで実行（コンパイルは MetaEditor F7）
- 出力: `MQL5/Files/ATR_Ratio_Timeseries_v1.csv`

## 2. 物差し（最重要・変更禁止）

`data/bt/ATR_WidthSignal_BT_gen3_kc.mq5` と完全に同じ定義：

| 項目 | 定義 |
|---|---|
| H1 ATR短期 | iATR(H1, 16) |
| H1 ATR長期 | iATR(H1, 32) |
| H1 中央値 | `CalcMedian`（gen3 L408 移植・上側中央値 `tmp[cnt/2]`）を **過去960本** の ATR16 に適用 |
| H1_Ratio | ATR16現在値 / H1中央値 |
| H4 ATR短期 | iATR(H4, 8) |
| H4 ATR長期 | iATR(H4, 46) |
| H4 中央値 | 同 CalcMedian を **過去240本** の ATR8 に適用 |
| H4_Ratio | ATR8現在値 / H4中央値 |

- CalcMedian は gen3 からコピー（改変しない）
- H4値は H1バー時刻→`iBarShift(_Symbol, PERIOD_H4, t)` で対応するH4バーの値。
  同じH4バーに属するH1バー4本は同じH4値になる（それで正しい）。
  H4側の中央値は H4バーが変わった時だけ再計算すればよい（キャッシュ可）。

## 3. 出力仕様

- 期間: **2024-01-01 00:00 〜 実行時点** の全H1バー（1行/バー、確定バーのみ）
- 先頭バーでも Ratio が計算できるよう、内部バッファは 2024-01-01 より 960+α 本 過去から確保
- エンコード: gen3 と同方式（FILE_UNICODE = UTF-16）。Python側はフォールバック読みするのでどちらでも可、ただし既存BT系と揃えること
- 列（ヘッダ必須）:

```
Time,H1_ATR16,H1_ATR32,H1_Med960,H1_Ratio,H4_ATR8,H4_ATR46,H4_Med240,H4_Ratio
```

- Time は `yyyy.MM.dd HH:mm`（H1バー開始時刻）
- 数値は DoubleToString(x, 3)（ATR生値は 3〜5桁裁量可、Ratioは3桁）
- 中央値が計算不能（データ不足）の行はスキップせず Ratio=0 で出力（Python側で除外する）

## 4. 実装ノート

- 約12,500 H1バー × CalcMedian(960) は Intel m3 + Wine でそれなりに重い。
  H1中央値はフル再計算でよいが、**進捗表示（Comment、500バーごと等）** を入れること
- 処理が分単位で終わらない場合のみ相談（サンプリング間引きは分析精度を落とすので最終手段）
- ヒストリー不足対策: 実行前に H1/H4 のバー読み込みが必要。CopyBuffer 失敗時はリトライ or 明示エラー
- 検算（コー側で必須）:
  1. 最終行付近の H1_Ratio / H4_Ratio が、BT gen2 CSV（`data/bt/ATR_WidthSignal_BT_h4adx46.csv`）の
     近接時刻シグナルの `H1_ATR_Ratio_Median` / `H4_ATR_Ratio_Median` とオーダー一致すること
     （完全一致でなくてよい。0.01オーダーのズレ許容・大きくズレたら物差し取り違え）
  2. 行数 ≒ 期間の H1バー数（週末除外で ~6,200本/年 × 2.5年）

## 5. このCSVで行う分析（Mac側・参考）

1. **共起率とリフト**: 反転点（WaveLog H1手描き波457個の起点 + H4波47個の起点）での
   H4_Ratio<0.85（および<0.70）率 ÷ 全期間ベースレート
2. **H1体力仮説**: 反転点で H1_Ratio が平均帯（0.85-1.15）に留まっている率
3. **到達順序**: 反転前 lookback 内で H4 と H1 のどちらが先に 0.85 を下抜けたか
4. ボトムアウト（PD→BU）／ピークアウト（BU→PD）別の非対称性

## 6. やらないこと

- シグナル判定・フィルター・売買ロジック（一切入れない）
- 波検出（WaveLog_Export_v1_6 の役割。混ぜない）
- mt5_data/ への自動同期（分析用につき手動コピー運用）
