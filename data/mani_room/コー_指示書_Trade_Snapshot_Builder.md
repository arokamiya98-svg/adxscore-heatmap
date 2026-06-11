# コー指示書: Trade_Snapshot_Builder.mq5

> あろさんのトレードCSVを「日時+価格のインデックス」として使い、
> 各エントリー時点の市場環境スナップショットと、ポジション期間中の MAE/MFE を
> MT5 から後付け取得して `trades_enriched.csv` として出力するスクリプト。
>
> 作成: メインおぱ / 2026-06-08
> 対象実装者: コー
> 関連: `data/trades/MANI_REORG_2026-06-05.md`

## 改訂履歴

### v1.1 (2026-06-08 PM)
- §2.5 MAE/MFE 計算方式を「決済期間中」→「**固定48時間 × H1/H4/D1 三層追跡**」に変更
  - 改訂理由: 決済判断（早抜け/SL狩り/建値撤退）が結果に混入し、シグナル本来の質が見えなくなる問題への対応
  - あろさん発言 (2026-06-08): 「狙ったシグナルの質自体が結果に消されて見えなくなる」
- §2.6 メタデータ列（bar_time × 4）新規追加
  - 取得元バー時刻のトレーサビリティ確保（H1/H4/D1）
- §3 アルゴリズム f-h 改訂（決済時刻独立、48時間固定追跡）
- カラム差分: -5 列削除（mae_pips, mfe_pips, mae_bar_idx, mfe_bar_idx, bars_held）, +19 列追加（48h MAE/MFE ×12, bars_traced ×3, bar_time ×4）

### v1.0 (2026-06-08 AM)
- 初版

---

## 0. 研究目的（絶対固定）

```
このスクリプトの目的はトレード分析ではない。
日時と価格をキーとして、エントリー時点の市場環境を後付け取得し、
「どの市場環境で期待値が発生しているか」を研究する基盤を作る。
```

### 禁止事項（コーが拡張提案する際の制約）

- 勝率分析 / PF分析 / 月別集計 / 損益集計を **目的化しない**
- 上記の集計機能を勝手に追加しない
- データ取得そのものを目的化しない

### 提案ルール

コーが取得項目や粒度の拡張を提案する場合、必ず以下を満たすこと:
- **「この項目が何の仮説検証に使われるのか」** を先に説明する
- **「そのデータによって何が判定できるようになるのか」** を先に説明する
- 説明できない取得項目は実装しない

---

## 1. 入出力

### 入力
```
data/mani_room/raw/imports/FX_20260608_144251.csv
  ※実際には MT5 Files/ ディレクトリにコピーしてから読む
  カラム: 約定日,決済日,通貨ペア,オーダー,新規レート,決済レート,pips,
         スタイル,ロット,損益,評価,反省,新規理由,決済理由,考察
  エンコード: UTF-8
  約30件（3/17〜6/2）
  時刻はJST（要タイムゾーン処理、§5 参照）
```

### 出力
```
MT5 Files/ → data/mani_room/enriched/trades_enriched.csv に Mac側でコピー
  カラム: 元CSV 全カラム + 後付け取得カラム（§2 参照）
  エンコード: UTF-8（FILE_TXT + UTF-8 BOM 推奨）
  改行: \n
```

---

## 2. 取得項目と仮説検証マッピング

各カラムは「**何の仮説検証に使うか**」が明確なものだけ追加する。

### 2.1 エントリー時点スナップショット（H1バー基準）

エントリー時刻直前の確定H1バー（= エントリー時点で見える最新H1バー）の値を取る。

| カラム名 | MT5 取得元 | 仮説検証 |
|---|---|---|
| `h1_atr16` | `iATR(NULL, PERIOD_H1, 16, shift)` | ATR収束底/拡張期の期待値分布構造分析 |
| `h1_atr32` | `iATR(NULL, PERIOD_H1, 32, shift)` | 同上、長期軸 |
| `h1_atr_ratio` | `h1_atr16 / h1_atr32` | ATR Zone (LOW/NORMAL/HIGH) 別期待値分布 |
| `h1_adx32` | `iADX(NULL, PERIOD_H1, 32, MODE_MAIN, shift)` | 「ADX強いトレンドのフォローが利益率高い」仮説検証 |
| `h1_di_plus` | `iADX(NULL, PERIOD_H1, 32, MODE_PLUSDI, shift)` | 方向性と期待値の関係 |
| `h1_di_minus` | `iADX(NULL, PERIOD_H1, 32, MODE_MINUSDI, shift)` | 同上 |

### 2.2 H4 スナップショット（H4バー基準）

エントリー時刻直前の確定H4バーの値を取る。

| カラム名 | MT5 取得元 | 仮説検証 |
|---|---|---|
| `h4_atr8` | `iATR(NULL, PERIOD_H4, 8, shift)` | H4翻訳層（T1〜T4）と期待値の関係 |
| `h4_atr46` | `iATR(NULL, PERIOD_H4, 46, shift)` | 同上、長期軸 |
| `h4_atr_ratio` | `h4_atr8 / h4_atr46` | H4 ATR Zone 別期待値分布 |
| `h4_adx46` | `iADX(NULL, PERIOD_H4, 46, MODE_MAIN, shift)` | BT世代2 「46周期採用根拠」の実トレ検証 |
| `h4_di_plus` | `iADX(NULL, PERIOD_H4, 46, MODE_PLUSDI, shift)` | H4 方向性と期待値 |
| `h4_di_minus` | `iADX(NULL, PERIOD_H4, 46, MODE_MINUSDI, shift)` | 同上 |

### 2.3 D1 スナップショット（D1バー基準）

エントリー時刻直前の確定D1バーの値を取る。

| カラム名 | MT5 取得元 | 仮説検証 |
|---|---|---|
| `d1_atr22` | `iATR(NULL, PERIOD_D1, 22, shift)` | D1 大局フェーズと期待値の関係 |
| `d1_atr42` | `iATR(NULL, PERIOD_D1, 42, shift)` | 同上、長期軸 |
| `d1_atr_ratio` | `d1_atr22 / d1_atr42` | D1 ATR Zone 別期待値分布 |
| `d1_adx22` | `iADX(NULL, PERIOD_D1, 22, MODE_MAIN, shift)` | D1 大局トレンド強度と期待値 |
| `d1_di_plus` | `iADX(NULL, PERIOD_D1, 22, MODE_PLUSDI, shift)` | D1 方向性と期待値 |
| `d1_di_minus` | `iADX(NULL, PERIOD_D1, 22, MODE_MINUSDI, shift)` | 同上 |

### 2.4 Phase / Pattern（カスタム計算 or 既存出力参照）

| カラム名 | 取得元 | 仮説検証 |
|---|---|---|
| `h4_phase_auto` | `ARO_H4PhaseAuto_v1` ロジックを内部実装 or 既存CSV参照 | 5段階自動判定（BU/PD/凪/収束底/凪離脱）別期待値。「凪離脱はフェイク（BT PF0.49）」実トレ検証 |
| `d1_phase` | D1 ATR22/42 クロス方向 + 経過バーから判定 | D1 BU/PD期別の期待値 |
| `h1_pattern` | v3bywavelog/v4 mq5 のシグナル判定ロジック内部実装 | 「RISING_DECEL × NORMAL 最強」BT発見の実トレ検証 |

**実装方針**: 既存 mq5 のロジックを参照しつつ、内部で再計算する。既存CSV (`H4PhaseAuto_weekly.csv` 等) 参照は補助的（突合確認用）。

### 2.5 ポジション期間動態（MAE/MFE）【v1.1 改訂: 固定48時間 × 三層】

#### 改訂背景（重要）

> エントリー〜決済期間で MAE/MFE を計算すると、あろさんの「決済判断（早抜け / SL狩り / 建値撤退）」が結果に混入し、**シグナル本来の質が見えなくなる**。
> 研究目的「どの市場環境で期待値が発生しているか」を正しく測るには、決済判断と独立に **エントリーから固定48時間** を追跡する必要がある。
> あろさん発言 (2026-06-08): 「狙ったシグナルの質自体が結果に消されて見えなくなる」

#### 計算仕様

エントリー時刻から **固定48時間（H1=48本 / H4=12本 / D1=2本）** を H1/H4/D1 それぞれで追跡し、最大有利/不利を計算する。

```
BUY:
  MFE = max(高値) - エントリー価格
  MAE = エントリー価格 - min(安値)

SELL:
  MFE = エントリー価格 - min(安値)
  MAE = max(高値) - エントリー価格
```

すべて **絶対値**（不利/有利の幅、常に正）。
単位は **USD**（XAUUSD のドル建て、1USD単位）。

#### カラム一覧（仮説検証マッピング付き）

| カラム名 | 単位 | 仮説検証 |
|---|---|---|
| `h1_mfe_usd_48h` | USD | H1単位48時間の最大有利幅 → シグナル本来の TP ポテンシャル |
| `h1_mfe_bar_idx_48h` | bar | H1 MFE到達バー数（1〜48）→ 持ち時間最適化「36本仮説」検証 |
| `h1_mae_usd_48h` | USD | H1単位48時間 MAE → SL構造根拠 |
| `h1_mae_bar_idx_48h` | bar | H1 MAE到達バー数 → SL タイミング分析 |
| `h4_mfe_usd_48h` | USD | H4単位（12本）で見た MFE → ノイズ除去後の動きの大きさ |
| `h4_mfe_bar_idx_48h` | bar | H4 MFE到達バー数（1〜12）→ H4視点の保有時間 |
| `h4_mae_usd_48h` | USD | H4単位 MAE → H4視点のリスク幅 |
| `h4_mae_bar_idx_48h` | bar | H4 MAE到達バー数 |
| `d1_mfe_usd_48h` | USD | D1単位（2本）の MFE → 日足クローズ単位、大局トレンド整合性 |
| `d1_mfe_bar_idx_48h` | bar | D1 MFE到達バー数（1〜2）|
| `d1_mae_usd_48h` | USD | D1単位 MAE → 大局視点のリスク幅 |
| `d1_mae_bar_idx_48h` | bar | D1 MAE到達バー数 |
| `h1_bars_traced_48h` | bar | 実際に追えた H1 バー数（直近は48未満の不完全データ）|
| `h4_bars_traced_48h` | bar | 実際に追えた H4 バー数（最大12）|
| `d1_bars_traced_48h` | bar | 実際に追えた D1 バー数（最大2）|

#### H1/H4/D1 三層追跡の意義

```
H1 (48本) ← 細かい動きまで含めた MAE/MFE
H4 (12本) ← ヒゲ・ノイズが除去された動き
D1 (2本)  ← 日足クローズ単位の純粋な方向動き

これら3層を並べることで以下が見える:
- H1 が大きく H4 が小さい → ヒゲで早抜けされやすい環境
- H4 が大きく H1 が小さい → 一瞬の伸びだけで構造的に弱い動き
- D1 単位で動いてる → 大局トレンド整合
- 各層で一貫した方向性 → ノイズ少ない期待値
```

#### 削除カラム（v1.0 → v1.1）

```
✗ mae_pips      （決済期間中ベース、研究目的に該当しない）
✗ mfe_pips      （同上）
✗ mae_bar_idx   （48時間版に置き換え）
✗ mfe_bar_idx   （同上）
✗ bars_held     （決済判断混入のため不要。エントリー〜決済時間は Mac 側で算出可能）
```

#### エッジケース

- ヒストリカルバーが48時間分足りない場合（直近トレード等）→ 取れる本数だけ追跡、`*_bars_traced_48h` に実本数を記録
- `*_bars_traced_48h` が 48/12/2 未満 = 「不完全データ」フラグ扱い（マニ側で除外可能）
- ヒストリカル取得不能の場合は全 MAE/MFE 列を空欄出力
- エントリー時刻が市場休場中 → 直近の確定バーから48時間追跡（連続H1足ベース）
- 決済時刻情報は MAE/MFE 計算に**使わない**（決済判断と独立）

---

### 2.6 メタデータ列【v1.1 新規】

取得元の時刻トレーサビリティ用。研究の妥当性を後から検証するための必須情報。

| カラム名 | 内容 | 用途 |
|---|---|---|
| `entry_bar_time` | エントリー時刻が属する H1 バーの開始時刻（JST形式 `yyyy-mm-dd HH:MM`）| エントリー実時刻と取得バーの照合 |
| `h1_bar_time` | H1 指標値の取得元バー時刻 | H1 ATR/ADX/Pattern の元データを後から検証 |
| `h4_bar_time` | H4 指標値の取得元バー時刻 | H4 Phase Auto/ATR の元データ検証 |
| `d1_bar_time` | D1 指標値の取得元バー時刻 | D1 Phase/ATR の元データ検証 |

#### 用途

- 「この `h4_phase_auto` = BU は何時のH4バー由来?」を即特定
- Phase 切り替わり瞬間付近のエントリーで、どちら側のバーの状態が記録されたか確認
- バグや異常値があった時、元データに遡って原因究明可能
- 別シートに MT5 を開いて「`h4_bar_time` の時刻にチャートを合わせる」だけで検証可能

#### フォーマット

JST 表記、`yyyy-mm-dd HH:MM` 固定（例: `2026-03-19 12:00`）。サーバー時刻ではなく**最終的に JST に戻す**こと（あろさんが見るのは JST）。

---

## 3. アルゴリズム

```
1. 入力CSVを読み込み、行ごとに処理
2. 各行について:
   a. 約定日（JST）→ サーバー時刻に変換（§5）
   b. その時刻に対応するH1バーのインデックスを求める
      iBarShift(NULL, PERIOD_H1, entry_time_server)
   c. shift = max(0, idx) として、エントリー直前の確定H1バー
   d. § 2.1〜2.3 の全指標を iATR/iADX で取得
   e. § 2.4 の Phase/Pattern を計算 or 既存ロジック参照
   f. エントリー時刻から固定48時間を H1/H4/D1 それぞれで追跡:
      - H1: エントリー後 48本（48時間相当）の High/Low を走査
      - H4: エントリー後 12本（48時間相当）の High/Low を走査
      - D1: エントリー後 2本の High/Low を走査
      - 各層で MAE/MFE と到達バー数を記録
      - ヒストリカル不足の場合は実取得本数を bars_traced に記録
      - 決済時刻情報は使わない（決済判断と独立）
   g. メタデータ列の取得元バー時刻を JST に変換して記録
      （entry_bar_time, h1_bar_time, h4_bar_time, d1_bar_time）
   h. 元CSV カラム + 取得カラムを連結して1行として出力
3. ヘッダ + 全行を trades_enriched.csv に書き出し
```

---

## 4. MT5 設計

### 4.1 ファイル種別: Script（EAではない）
- 1回実行で全件処理して終了
- `OnStart()` で完結

### 4.2 入力ファイルの配置
```
MT5 Files/
├ trade_input.csv     ← あろさんがコピー（mani_room/raw/imports/ からコピー）
└ trades_enriched.csv ← Script が出力
```

### 4.3 CSV パース
- 元 CSV は **複数行に渡るquoteフィールド**を含む（新規理由・決済理由・考察）
- MT5 FileReadString だけだと multi-line quote 解釈が難しい
- **推奨**: 入力CSVは「**1行=1トレード**」に正規化されたシンプル版を別途用意
  - Mac 側 Python で前処理: multi-line を `\\n` エスケープに変換
  - もしくは「指標取得に必要な情報だけ抜き出した中間 CSV」を渡す
    - 必要カラム: `trade_id, entry_jst, exit_jst, direction, entry_price`
    - これで MT5 側は楽
- **判断**: 中間 CSV 方式を推奨（コーは中間 CSV を読む、Mac側で前処理スクリプト書く）

### 4.4 出力CSV
- ヘッダ + 全行
- カラム順: trade_id + 元CSVの全カラム + 取得カラム
- `FileOpen(name, FILE_WRITE|FILE_TXT|FILE_ANSI)` or UTF-8 BOM 手動付加
- 数値は固定小数点（例: ATR は小数3桁）

---

## 5. タイムゾーン処理（要注意）

```
CSV 約定日 = JST（日本時間）
MT5 サーバー時刻 = ブローカーサーバー時刻（多くは GMT+2/+3 = EET/EEST）

JST (UTC+9) → サーバー時刻への変換:
  サーバー時刻 = JST - 9時間 + サーバーオフセット

サーバーオフセットは TimeGMTOffset() / TimeDaylightSavings() で取得
または ブローカーから確認（例: HFMarkets は GMT+2 冬, GMT+3 夏）
```

### 推奨実装
```cpp
datetime jstToServer(datetime jst) {
    // JST (UTC+9) → UTC
    datetime utc = jst - 9 * 3600;
    // UTC → サーバー時刻
    datetime server_offset_sec = (datetime)(TimeGMTOffset() + (TimeDaylightSavings() ? 3600 : 0));
    return utc + server_offset_sec;
}
```

**動作確認**: 既知の1件（例: 2026/03/19 13:47 売り）でサーバー時刻に変換し、H1足インデックスを iBarShift で取って、その時刻の H1 OHLC が想定通りか手動確認すること。

---

## 6. エッジケース

| 状況 | 対応 |
|---|---|
| 決済日空欄 | MAE/MFE/bars_held を空欄出力 |
| 取得失敗（iATR が 0 返す等）| 当該カラムを空欄出力、ログに記録 |
| エントリー時刻が市場休場中（土日等）| 直前の最終確定バーから取得 |
| iBarShift が -1（バーが見つからない）| 当該行は全取得カラム空欄出力、ログ |
| シンボル不一致（XAUUSD 以外） | 当該行スキップ、ログに記録 |
| ヒストリカルデータ不足 | エラーログを出して終了（部分出力しない）|

---

## 7. 動作確認手順

### 7.1 単体テスト
```
1. 1件だけ含む trade_input.csv で実行
   推奨サンプル: 2026/03/19 13:47 売り（暴落相乗り、勝ち）
2. 出力カラムを目視確認
   - h1_atr16, h1_atr32 が MT5 チャート上の表示値と一致するか
   - h4_phase_auto が H4 Phase Auto v1 と一致するか
   - mae_pips, mfe_pips が手計算と一致するか
```

### 7.2 全件テスト
```
3. 全30件で実行
4. 出力 CSV の行数 = 入力行数 + 1（ヘッダ）
5. 取得カラムが全行で埋まっているか（空欄=エッジケース該当のみであること）
```

### 7.3 整合性チェック
```
6. 既存 weekly_waves.json / H4PhaseAuto_weekly.csv と
   出力 trades_enriched.csv の同一週のサンプルを突合
   d1_phase / h4_phase_auto が一致するか
   一致しない場合: タイムゾーン処理 or Phase 計算ロジックを再確認
```

---

## 8. 提出物

```
1. signals/Trade_Snapshot_Builder.mq5（または mt5_data 直下）
2. 1件単体テストの出力 CSV + 比較レポート（MT5 チャート値との突合）
3. 全件テストの出力 CSV
4. エラーログ（あれば）
```

---

## 9. メインおぱとの連携

- 不明点・判断迷う点は **すぐ報告**
- 取得項目追加/変更を提案する場合は §0 の提案ルールに従う
- mq5 実装で困った場合: 既存スクリプト（ATR_WidthSignal_v4.mq5, ARO_H4PhaseAuto_v1.mq5, ARO_FractalWaveLog_D1_v3_2.mq5）の実装パターンを参照
- 完成したら mt5_data/ に出力配置 + Mac 側で `data/mani_room/enriched/` に同期する手順を教える

---

*このスクリプトは「マニの部屋」の研究用データ基盤の入口。*
*ここで取得されたデータが、すべての仮説検証の母集団になる。*
