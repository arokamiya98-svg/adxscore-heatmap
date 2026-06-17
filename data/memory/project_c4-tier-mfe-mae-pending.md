---
name: c4-tier-mfe-mae-pending
description: コー C4 案件 = 時間別 MFE/MAE @12/24/36/48h 推移取得。ATR帯×時系列のクロス探索の本丸。Trade_Snapshot_Builder + Daily_MFE_MAE 両方の mq5 改修
metadata: 
  node_type: memory
  type: project
  originSessionId: eef91938-feba-4253-8551-3c016bc3980e
---

マニの部屋プロジェクト「日次研究カレンダー」の **本丸データ案件**。
2026-06-10 にコー宛に v0.2 指示書として発注。

## C4 の正体

**時間別 MFE/MAE @12/24/36/48h 推移取得**

## 研究上の必然性

現状の MFE/MAE は 48h時点の最大値のみ。これでは:
- 「ATR 高い時、12h 以内に勝負がつく」のか「48h 粘ると伸びる」のか **判別不能**
- 「ATR 低い時、遅く伸びる」のか「最初から伸びない」のか **判別不能**
- → **ATR帯 × 時間推移 × 勝敗 のクロス探索が不可能**

C4 はこれを解決するため、12h / 24h / 36h / 48h 各時点の **累積最大MFE・最大MAE** を取得する。

## 改修対象

- `signals/Trade_Snapshot_Builder.mq5` v1.1 → v1.2（C4-A）
- `signals/XAUUSD_Daily_MFE_MAE_v1.mq5` v1 → v1.1（C4-B）

## 新規カラム（概要）

```
# H1 三層（1h足ベース）
h1_mfe_usd_12h, h1_mae_usd_12h
h1_mfe_usd_24h, h1_mae_usd_24h
h1_mfe_usd_36h, h1_mae_usd_36h
h1_mfe_usd_48h, h1_mae_usd_48h   ← 既存

# H4 三層（4h足ベース）同様
# D1 三層（1日足ベース、24h/48h のみ意味あり）

# BUY/SELL 仮想（Daily_MFE_MAE 側）同様
```

## C4 と マニ UI の関係

```
[並列発注 2026-06-10]
  マニ v0.2 : 円グラフ起点 UI + ATR 絶対値ソート + バグ修正
  コー C4    : @12/24/36/48h データ取得

[完成順]
  マニ v0.2 先に完成 → 「ATR帯と勝敗の傾向」を眺められる
  C4 後に完成        → マニ第2弾で「時間推移列」追加
                       → ATR帯 × 時系列 のクロス探索が解禁
```

## 関連ファイル（発注時点 2026-06-10）

- `data/mani_room/コー_指示書_日次研究データ取得_v0.2.md` — C4 発注書
- `data/mani_room/マニ_指示書_日次研究カレンダー_v0.2.md` — マニ並列発注
- `data/mani_room/enriched/trades_enriched_full.csv` — 30トレード enriched（C4 で 12/24/36/48h カラム追加予定）
- `mt5_data/daily_mfe_mae_48h.csv` — 84日分（C4 で 12/24/36/48h カラム追加予定）

## C3 との関係

- C3 (v4 シグナル発火ログ) は **C4 完了後に再判断**
- 取り逃がし/過剰反応の検出は付随情報、C4 が本丸のため後回し

## 関連メモリ

- [[research-purpose-and-rules]] — 研究目的固定（C4 の必然性の根拠）
- [[team-opa-role-division]] — コーが C4 担当、マニが UI 担当
