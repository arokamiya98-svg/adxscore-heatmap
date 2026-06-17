---
name: nagi-vs-range-distinction
description: 「凪」と「RANGE」は別概念。凪=ATR収束、RANGE=ADX閾値未達。UI/ラベルで混同しない
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 0ec2e3f3-5810-4be6-949c-d56801971efd
---

「凪」と「RANGE」は別概念として区別する。混在させない。

- **凪 (Nagi)** = **ATR の収束**、ボラが落ち着きへ向かうイメージ。動きが減衰している状態。
- **RANGE** = **ADX の閾値未達**、横ばい、トレンドが弱い状態。ADX が単に閾値を越えてないだけのパターンも含む。

**Why:** あろさん明示「凪だけRANGEに変えようかな？これはADXでしょ？落ち着きなんだろうけど、閾値を越えてないだけのパターンもある。ATRの凪ってもっと収束へ向かうイメージやね」（2026-06-10、日次研究カレンダー実物確認時）。

**How to apply:**
- ADX 閾値未達の状態を表示するときは「RANGE」を使う
- ATR が収束/減衰している状態を表示するときは「凪」を使う
- 既存資産（heatmap_v14、ATR Phase 等）でも今後この区別を守る
- 「凪離脱」（H4 Phase Auto v2 の5段階の一つ）は ATR 文脈なのでそのまま「凪離脱」を維持
- 関連: [[trading-method-summary]]（ATR=タイミング、ADX=評価軸の役割分担）
