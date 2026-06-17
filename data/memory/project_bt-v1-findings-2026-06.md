---
name: bt-v1-findings-2026-06
description: BT世代1（2026-06-02実行）の主要発見サマリ。XAUUSDの構造的非対称性と機能/死亡パターン
metadata: 
  node_type: memory
  type: project
  originSessionId: 4084c9b8-eb6c-4bba-ba94-51639371f291
---

2026-06-02、`ATR_WidthSignal_v3bywavelog` ベースのフラットセンサーBT実行。データ範囲 2024-01-02〜2026-06-01、全947件、6時間ウィンドウフィルター後 481件。

**Why:** ATR_WidthSignalの5パターン×BUY/SELLの構造特性を、結果フィッティングではなく構造分析で解明するため（[[bt-analysis-principles]] に基づく）。
**How to apply:** 次セッションで認識ツール組み込み or フィルター実装する時の出発点。詳細マップは `ADXSCORE/data/bt/PATTERN_REGIME_MAP_v1.md` を参照。

## 主要発見

1. **XAUUSDの構造的非対称性「買いは押し目、売りは拡張」**
   - 買い相場（D1=UP）: ATR_RM=MID-L帯（押し目=ATR落ち着き）で勝つ。MID-H帯（拡張中）で死ぬ
   - 売り相場（D1=DN）: ATR_RM=MID-H帯（拡張中=崩れ始め）で勝つ。MID-L帯では伸びない
   - 「上昇は時間をかけて、下落は一気に」というXAUUSD心理的非対称性が、ATR比率の効き方に直接出ている

2. **Cross=NONE × SELL が圧倒的死亡帯**: N=22, WR 13.6%, PF 0.21
   - 方向エネルギーがない平坦相場でSELL = 構造的にダメ

3. **パターン別の構造的役割**
   - PatA: 万能、局面非依存
   - PatB: 押し目スナイパー。UP×PD×MID-L で PF 2.96。MA_Pos BELOW_FAR で爆発（PF 3.09）
   - PatC: BU期初動専用。MID-H/HIGH発火は初動性失う
   - PatD: BU期専用節目検出。PD/HIGH帯で死亡。SELL全般弱い

4. **DN局面サンプル不足**: 全体の17%しかなく、現局面（SELL優勢のPD期、2026-06時点でDI-反応）以降の継続蓄積が必須。

5. **MA_Pos の機能性は確認、採用は保留**: PatB BUY × BELOW_FAR で PF 3.09 など示唆的だが、「高加熱フィルター単体 vs +MA_Pos」の比較BTで完全な優位性確認が必要（あろさん判断）。

## 留意

[[bt-regime-bias]] の通り、UP局面バイアス（83%）を内包。フォワード検証必須。D1ロジック（D1 ATR pattern, ADX velocity 等）はまだ深掘りしていない。

## 関連

- 詳細マップ: `ADXSCORE/data/bt/PATTERN_REGIME_MAP_v1.md`
- BTソース: `ADXSCORE/data/bt/ATR_WidthSignal_BT_v3bywavelog.mq5`
- 結果CSV: `ADXSCORE/data/bt/ATR_WidthSignal_BT_NEW.csv`（947件、UTF-16）
- フィルター戦略: [[bt-filter-strategy]]
- 分析原則: [[bt-analysis-principles]]
