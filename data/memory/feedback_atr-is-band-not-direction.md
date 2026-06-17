---
name: atr-is-band-not-direction
description: ATR Phase (BU/PD) は値幅情報。色を価格方向と混同しない。BU=青/PD=赤の単純化は誤り
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 0ec2e3f3-5810-4be6-949c-d56801971efd
---

ATR Phase は値幅情報（ボラの拡張/縮小）であって、価格方向ではない。UI 配色で「BU=青、PD=赤」のように方向色を割り当てるのは概念上の誤り。

- **ATR Phase**:
  - **BU** = ボラ拡張（**値幅**が広がる）
  - **PD** = ボラ縮小（**値幅**が狭まる）
- **DI 方向**:
  - **UP** = 価格が**上昇**方向
  - **DOWN** = 価格が**下落**方向

価格は ATR Phase が PD でも大下落することはある。だから色は「価格方向 (DI) で青/赤」「ATR Phase (BU/PD) で鮮やかさ/サブ系」の二段構えにする。

**Why:** あろさん明示「BUの下落、上昇を本来の青赤で、PD期をサブ系の色にして欲しい。これはボラティリティの爆発と縮小だけど価格は別に大下落にもなってる。ATRって値幅情報だから BU=青、PD=赤 ってのが間違えてる」（2026-06-10、日次研究カレンダー実物確認時）。

**How to apply:**

UI で「ATR Phase × DI 方向」を色で表す場合の標準マッピング:

| ATR Phase | DI方向 | 色 | 意味 |
|---|---|---|---|
| BU (拡張) | UP | **メイン青（鮮やか）** | 拡張×上昇 |
| BU (拡張) | DOWN | **メイン赤（鮮やか）** | 拡張×下落 |
| PD (縮小) | UP | サブ青（淡い） | 縮小×上昇 |
| PD (縮小) | DOWN | サブ赤（淡い） | 縮小×下落 |
| RANGE (ADX未達) | - | グレー | - |

- 色相 = 価格方向（DI）、鮮やかさ = ATR Phase の主従
- 「BU=青、PD=赤」のような単一軸での色分けは禁止
- 関連: [[trading-method-summary]]（ATR=タイミング、ADX=評価軸の役割分担）、[[nagi-vs-range-distinction]]
