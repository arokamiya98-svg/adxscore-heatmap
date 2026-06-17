---
name: hardware-mac-environment
description: 実行環境はMacBook 12インチ 2017モデル。Intel Core m3・8GBメモリ・macOS Venturaが最終対応OS
metadata: 
  node_type: memory
  type: project
  originSessionId: 9680f5e6-e416-42b9-9329-3c878ab13dc9
---

実行環境のハードウェア・OSスペック（2026-06-01確認）：

| 要素 | 詳細 |
|------|------|
| 機種 | MacBook Retina 12-inch, 2017 |
| CPU | 1.2 GHz Dual-Core Intel Core m3（Apple Silicon前のIntel Mac） |
| GPU | Intel HD Graphics 615（1536 MB共有） |
| メモリ | 8 GB 1867 MHz LPDDR3 |
| ストレージ | 233GB（132GB空き） |
| OS | macOS Ventura 13.7.8 |

**重要な制約:**

- このハードウェアの最終サポートOSは Ventura 13.x（Sonoma 14・Sequoia 15には非対応）→ **macOSはこれ以上アップグレードできない**
- CPU性能は控えめ（Core m3, 2コア、ファンレス）→ 重い処理は時間がかかる、並列処理は要注意
- メモリ8GBは余裕がない → Wine+MT5+macOSで使い切り寄り
- Intel Macなので、Wine等のx86バイナリは直接動作（Apple SiliconのようなRosetta 2層なし）

**How to apply:**

- 重いデータ処理は Python の最適化を意識（pandas のメモリ効率、chunk処理など）
- 「macOSアップデートで環境が壊れる」リスクは内側からは無い（既にOS終端）→ **動いてる環境の維持を優先**
- MT5アップデート判断は「現状の安定性 > 最新版」で考えるのが妥当
- Apple Silicon前提のツール提案は避ける（M1/M2/M3/M4向けバイナリは動かない）
- 並列ジョブは慎重に（CPUコア2つ＋メモリ8GBだけ）
- タイプミス出やすい→と本人言及済み、PCの古さと打鍵感も関係している可能性
