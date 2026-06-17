---
name: bt-signal-log
description: ATR_WidthSignal BT結果ログ群。data/bt/ に集約。v3=フィルター済み27件(2026-01〜05) / v3wavelog=未フィルター全件記録（旧872件は凍結ゾーン）
metadata: 
  node_type: memory
  type: reference
  originSessionId: e25c809f-e5d5-46e3-be00-8af871c12fac
---

ATR_WidthSignal シリーズのBT結果ログ。マニの「BT＝シグナル素地の期待値」参照用。

## v3（フィルター済み）

- ファイル: `/Users/aro/Desktop/ADXSCORE/data/bt/ATR_WidthSignal_BT_v3.csv`
- エンコーディング: **UTF-16 LE BOM付き**
- 行数: 28（ヘッダー含む）、**27トレード**
- 列数: **31**
- 期間: **2026-01-05 〜 2026-05-27**
- 状態: **5/28以降は未収録 → 要再BT実行**
- 出自: Claude Chat由来ソースを 2026-06-02 にMT5で実行
- ソース: `/Users/aro/Desktop/ADXSCORE/data/bt/ATR_WidthSignal_BT_v3.mq5`
- タグ: 「PF2/勝率50近辺の現行モデル前完成系」想定だが、27件全WINで実態と乖離

## ⚠️ 再現性懸念（2026-06-02 あろさん指摘）

> ちょっとやり過ぎなBTやな…再現性とパフォーマンス基準で見たら今のEAの検証もう一度やりたいね！

- 27件全WIN = **再現性とパフォーマンス基準で「やり過ぎ」の疑い**（過剰最適化 or 期間バイアス）
- 現EAを基準にした **再BT検証が必要** （将来TODO、別件として保管）
- 直近セッションでは触らない。データ整理・参照先整理を優先
- 既存27件CSVは参考保管とし、戦略判断の根拠としては使わない
- 関連: [[bt-regime-bias]] - BTの局面バイアス原則

### 主要列（31列）

```
TradeNo, OpenTime, CloseTime, Pattern (PatA/PatC/PatS), Direction (BUY/SELL),
EntryPrice, SL, TP, SL_Pips, TP_Pips, Lot,
ATR, ATR_Avg, ATR_Med, ATR_Ratio, Vel3, ATR_Accel, ATR_Zone,
H4_ADX, H4_DI+, H4_DI-, H4_Zone,
H1_ADX, H1_DI+, H1_DI-, H1_Zone,
Weekday, Hour, Result, Profit_USD, Profit_Pips
```

## v3wavelog（未フィルター・全BUY/SELL記録）

- ソース: `/Users/aro/Desktop/ADXSCORE/data/bt/ATR_WidthSignal_BT_v3wavelog.mq5` + `.ex5`
- 内容: ATR_WidthSignal が出した BUY/SELL シグナルを**全件フィルターなし**記録する仕様
- 旧結果CSV: 872トレード、48列、最終更新 2026-05-27 朝
- 旧結果ファイル: `ADX２８検証ファイル/ATR_WidthSignal_BT_v3wavelog.csv`（**凍結ゾーン・参照不可**、[[mani-work-zone]] 参照）
- 状態: 現用周期(H1=32, H4=46)での再BT 未実行
- 用途: シグナル素地の出現頻度確認（実戦想定ではない）
- 出自経緯: D1フェーズ統合のロジック化検証用として取り出されたが、結局手動トレンドライン依存でロジック化レベル未達

## 位置付け

- これは [[mani-evaluation-criteria]] の「BT＝シグナル素地の期待値」側のデータ
- マニはこれを参照して「あろさんがエントリした環境の過去BT勝率」を計算できる
- ただし、**マニが評価するのはリアル側の立ち回り**であって、BT勝率そのものではない
- BTでWINな環境でもリアルでLOSSなら「シグナル素地は良かったが立ち回りで損ねた」可能性
- BTでLOSSな環境でもリアルでWINなら「シグナル素地は弱かったが裁量で取った」可能性

## 集計コード（python）の最小例

```python
import csv
with open("/Users/aro/Desktop/ADXSCORE/data/bt/ATR_WidthSignal_BT_v3.csv",
          encoding="utf-16") as f:
    rows = list(csv.DictReader(f))

# 例: BUY のみ勝率
buy = [r for r in rows if r["Direction"]=="BUY"]
wins = [r for r in buy if r["Result"]=="WIN"]
print(f"{len(wins)}/{len(buy)} = {len(wins)/len(buy)*100:.1f}%")
```

## 関連メモリ

- [[mani-evaluation-criteria]] - 評価軸（BTとリアルの役割分担）
- [[mani-work-zone]] - 参照ゾーン定義（ADXSCORE/配下のみ）
- [[bt-regime-bias]] - BT統計の局面バイアス
