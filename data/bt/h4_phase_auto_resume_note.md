# H4 Phase Auto v2 実装 - コー再投入用メモ

> 状況: 2026-06-04 ~12:36 に session limit で停止
> リセット時刻: 13:10 (Asia/Tokyo)
> 推定状況: **実装ほぼ完了、最終報告のみ未送信**

---

## 確認済み（おぱによる事前チェック）

4ファイル全部に「収束底」「凪離脱」が入ってる:

| ファイル | サイズ/箇所 |
|---|---|
| `signals/ARO_H4PhaseAuto_v1.mq5` | 13662 bytes / 「収束底」「凪離脱」6箇所 |
| `scripts/process_wavelog.py` | 「収束底」「凪離脱」5箇所 |
| `scripts/generate_heatmap_v14.py` | 「収束底」「凪離脱」8箇所 |
| `docs/heatmap_v14.html` | 「収束底」「凪離脱」7箇所 |

---

## コー再投入時のタスク（3つだけ）

### Task 1: 4ファイル整合性最終チェック
- mq5の `H4PhaseAuto()` 関数が仕様書 v2 通り（5段階, BU/PD/凪/収束底/凪離脱）
- mq5 CSV出力列が10列（H4_ATR_Diff 含む）
- mq5 内で Cross_Dir を BU/PD/NONE に変換出力（UP/DOWN ではなく）
- process_wavelog.py の `h4_phase_auto()` 関数が同じロジック
- generate_heatmap_v14.py のCSS 5段階（hp-syusoku=緑, hp-fake=オレンジ警告）
- 凪離脱の点滅 CSS は控えめ

### Task 2: パイプライン動作確認（py側のみ）
- `python3 scripts/process_wavelog.py` 実行成功
- weekly_waves.json に `h4_phase_auto`, `h4_atr_diff` フィールド出力
- `python3 scripts/generate_heatmap_v14.py` 実行成功
- ※ mq5 BTスクリプト走らせて新CSV取得はあろさんがMT5でやる範囲、コーは不要

### Task 3: 最終報告（メインおぱへ）
1. 実装完了確認
2. 実装上の判断事項（指示書から外れた部分、独自判断）
3. あろさんへのテスト依頼項目（MT5でやってもらうこと）

---

## 仕様書

```
/Users/aro/Desktop/ADXSCORE/data/bt/h4_phase_auto_spec.md
```

v1→v2 の変更点（凪3層細分、収束底・凪離脱追加、BU/PD命名統一）が明記済み。

---

## メモ
- session limit までに 29 tool uses 使った
- duration ~356秒
- 完成度高い状態だった可能性大、報告だけ未送信
