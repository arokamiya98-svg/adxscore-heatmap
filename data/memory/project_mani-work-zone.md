---
name: mani-work-zone
description: マニ（振り返り評価役サブエージェント）の参照データゾーン定義。ADXSCORE/配下のみが正規参照、ADX２８検証ファイル/は凍結
metadata: 
  node_type: memory
  type: project
  originSessionId: e25c809f-e5d5-46e3-be00-8af871c12fac
---

マニ（[[mani-evaluation-criteria]] で定義された評価軸を持つサブエージェント）が
振り返り・評価・最適解提示に使うデータゾーンを明示的に固定する。

## 正規参照ゾーン

```
/Users/aro/Desktop/ADXSCORE/
├── data/
│   ├── bt/          ← BT結果（将来のD1 ADX局面別BTを含む）
│   ├── forward/     ← 手動フォワードテスト記録
│   └── INVENTORY.md ← 索引（鮮度・信頼度・由来）
├── mt5_data/        ← 週次パイプライン正規データ
├── signals/         ← 現用シグナルmq5ミラー
└── retrospect/      ← 振り返り記録
```

## 凍結ゾーン（参照禁止）

`/Users/aro/Desktop/ADX２８検証ファイル/` (334ファイル)

- ADX28周期での旧検証（H1=28, H4=30）
- 現行はH1=32, H4=46 → 周期ズレ・誤誘導リスク
- マニが評価する際、ここを読み込まない・引用しない
- 「最適解」の根拠データとして引用するのも禁止

**Why:** マニの評価には [[mani-evaluation-criteria]] のルール1（「ダメなら最適解を必ず示す」）が含まれる。最適解の根拠データが旧周期だと、誤った最適解を提示し、戦略を誤誘導する。参照ゾーンを物理的に分けることで、評価の質と一貫性を担保する。これは [[fwd-data-pipeline-weakness]] と [[bt-regime-bias]] の延長で、「現在の局面・現在の周期に整合するデータだけを参照する」という運用ルール。

**How to apply:**
- マニを起動する際、データソースは ADXSCORE/ 配下に限定
- BT集計するときは `ADXSCORE/data/bt/` のCSVを使う（[[bt-signal-log]] パスもここに更新する）
- 会話やプロンプトに「ADX２８検証ファイル/」が出てきても、参照しない・読み込まない
- 新しいBT結果・FW記録は必ず ADXSCORE/data/ 配下に置く（運用ルール）
- マニのトレード運用分析サポートの「核」をこのゾーンで育てる

## 関連メモリ

- [[mani-evaluation-criteria]] - マニの評価軸本体
- [[bt-signal-log]] - 参照BTファイル（パス更新予定）
- [[adxscore-tool-current-state]] - ADXSCOREツール構成
- [[bt-regime-bias]] - BT統計の局面バイアス
- [[fwd-data-pipeline-weakness]] - 波形抽出の構造的弱点
