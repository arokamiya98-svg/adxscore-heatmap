# PATTERN_REGIME_MAP v1 — BT世代1の発見マップ

> 作成: 2026-06-03
> ベース: `data/bt/ATR_WidthSignal_BT_NEW.csv`（947件、2024-01-02〜2026-06-01）
> 6時間フィルター適用後: 481件
> 状態: 🟡 暫定v1。過去BUY優勢期バイアスを内包、フォワード検証要。
> 原則: [[memory: bt-analysis-principles]] - 結果フィッティング禁止、構造分析優先

---

## 0. 全体傾向

```
Total (フィルター後): 481件
WIN=213, LOSS=268, WR=44.3%, PF=1.26, Net=+$2,431
SL平均: 17.5 USD（価格差）/ TP平均: 28.1 USD（RR 1.6）

D1局面分布:
  UP×PD:   202 (42.0%)  ← 最頻：上昇相場の押し目
  UP×BU:   108 (22.5%)
  UP×NONE:  83 (17.3%)
  DN×PD:    62 (12.9%)  ← 現局面（SELL優勢の収束期）
  DN×BU:    16 ( 3.3%)
  DN×NONE:  10 ( 2.1%)
```

→ 過去2.5年は買い相場ベース。DN期サンプルは絶対量で少ない。

---

## 1. 機能パターン（Top15）★保有候補

判定: N≥5 & PF≥1.3

| Rank | 局面 | Zone | Pattern | Dir | N | WR | PF | Net$ |
|------|------|------|---------|-----|---|-----|-----|------|
| 1 | UP×PD | MID-L | PatB | BUY | 15 | 60.0% | **2.96** | +164 |
| 2 | DN×PD | MID-H | PatC | SELL | 7 | 57.1% | **2.50** | +120 |
| 3 | UP×PD | MID-L | PatA | BUY | 26 | 57.7% | **2.36** | +205 |
| 4 | UP×BU | MID-H | PatC | BUY | 12 | 75.0% | **2.21** | +101 |
| 5 | DN×PD | MID-L | PatA | SELL | 13 | 46.2% | **2.07** | +154 |
| 6 | UP×PD | HIGH | PatB | BUY | 6 | 66.7% | 2.03 | +51 |
| 7 | UP×BU | MID-H | PatA | BUY | 21 | 52.4% | 1.92 | +137 |
| 8 | UP×NONE | MID-L | PatD | BUY | 8 | 50.0% | 1.89 | +43 |
| 9 | UP×NONE | MID-L | PatB | BUY | 9 | 55.6% | 1.87 | +56 |
| 10 | UP×NONE | MID-H | PatD | BUY | 11 | 54.5% | 1.81 | +131 |
| 11 | UP×PD | MID-H | PatB | BUY | 19 | 42.1% | 1.81 | +103 |
| 12 | UP×PD | MID-L | PatA | SELL | 7 | 42.9% | 1.75 | +43 |
| 13 | UP×NONE | MID-L | PatA | BUY | 9 | 55.6% | 1.68 | +29 |
| 14 | UP×BU | HIGH | PatD | BUY | 5 | 40.0% | 1.58 | +22 |
| 15 | UP×BU | MID-H | PatD | BUY | 18 | 55.6% | 1.58 | +92 |

---

## 2. 構造的ダメパターン Top6 ⚠️削減候補

判定: N≥5 & (PF≤0.7 or Net≤-50)

| # | 局面 | Zone | Pattern | Dir | N | WR | PF | Net$ | 構造的理由 |
|---|------|------|---------|-----|---|-----|-----|------|----------|
| 1 | UP×NONE | MID-H | PatC | BUY | 10 | **0.0%** | **0.00** | -245 | 中立期＋拡張中＋ABOVE系MA = エネルギー消耗の終端で初動買い→高値掴み |
| 2 | UP×BU | MID-H | PatB | BUY | 12 | 25% | 0.26 | -150 | H1_DI-優勢の中BUY → 短期下落中の押し目買い=逆張り |
| 3 | UP×PD | MID-H | PatA | SELL | 7 | 14% | 0.09 | -106 | 上昇相場の押し目期にATR拡張SELL → 大反発の根に逆張り |
| 4 | UP×PD | MID-H | PatC | BUY | 14 | 29% | 0.62 | -63 | 高ADX＋ABOVE_FAR=トレンド消耗終端でBUY |
| 5 | UP×NONE | MID-H | PatA | BUY | 8 | 38% | 0.60 | -37 | エネルギーなし＋ATR拡張＋価格高=方向出ない |
| 6 | UP×NONE | MID-H | PatB | SELL | 5 | 20% | 0.42 | -29 | 中立期SELL（構造ミスマッチ） |

**共通点**: 全部 **ATR_RM=MID-H帯**。買い相場のATR拡張中で発火するBUY/SELLは構造的に踏まれる。

---

## 3. 単一軸での「死亡条件」

### 3.1 D1_ATR_Cross_Dir × Direction（最強の構造発見）
```
NONE × SELL: N=22  WR 13.6%  PF 0.21 ⚠️★★★ 圧倒的死亡帯
```
**Cross=NONE = 方向エネルギーがない平坦相場**。ここでSELLを出すとほぼ確実に踏まれる。
構造的に説明可能：エネルギーがない方向に張る = 失敗。

### 3.2 Pattern × ATR_Zone
```
PatB × MID-H: PF 0.75 (N=53) ⚠️ ← PatB死亡帯（押し目すでに過ぎた）
PatC × MID-H: PF 0.83 (N=61) ⚠️ ← 初動の意味成立しない
PatD × HIGH:  PF 0.77 (N=10) ⚠️ ← H4節目はピーク後で死亡
PatD × MID-L: PF 0.81 (N=49) ⚠️ ← 収束しすぎてブレイク力なし
```

### 3.3 Pattern × Direction（素の挙動）
```
PatB SELL: PF 0.68 (N=35) ⚠️ ← 売りPatBは構造的に弱い
PatC BUY:  PF 0.72 (N=42) ⚠️ ← 初動BUY全体で弱い
PatC SELL: PF 0.81 (N=25) ⚠️
PatD SELL: PF 0.48 (N=11) ⚠️ ← 売りPatDは消滅候補
```

### 3.4 ATR_Zone × Direction（参考）
```
HIGH × SELL:  N=18  WR 33.3%  PF 0.66 ⚠️ 高ATR売りは死ぬ
MID-H × SELL: N=57  WR 35.1%  PF 0.97 ⚠️ 拡張中売りも踏まれる
```

---

## 4. 構造的発見（物語化）

### 4.1 XAUUSDの非対称性「買いは押し目、売りは拡張」
- **買い相場**: MID-L帯（押し目=ATR落ち着き）で勝つ。MID-H帯（拡張中）で死ぬ。
- **売り相場**: MID-H帯（拡張中=崩れ始め）で勝つ。MID-L帯（収束しすぎ）では伸びない。
- **構造的理由**: 「上昇は時間をかけて、下落は一気に」というXAUUSDの心理的非対称性が、ATR比率の効き方に直接出ている。

### 4.2 Cross期の意味
- **BU** = ATR_Short > ATR_Long（拡張中、エネルギー出てる）
- **PD** = ATR_Short が ATR_Long を下抜け（拡張ピーク後の収束、リバーサル要素）
- **NONE** = 過去20本以内クロスなし（方向不定の平坦期）→ SELLが構造的に死ぬ

### 4.3 パターン別の構造的役割
| Pattern | 性格 | 機能帯 | 死亡帯 |
|---------|------|--------|--------|
| **PatA** | 万能センサー | 局面非依存（MID-L, MID-Hどちらも） | UP×PD×MID-H (逆張りSELLで死) |
| **PatB** | 押し目スナイパー | UP×PD×MID-L (PF 2.96)、SELL全般弱い | UP×MID-H BUY（押し目過ぎ）、SELL全般 |
| **PatC** | BU期初動 | UP×BU×MID-H (PF 2.21) | MID-H/HIGH全般（初動の意味なし）|
| **PatD** | H4節目検出 | UP×BU×MID-H (PF 1.58) | PD期全般、HIGH、SELL全般 |
| **PatE** | サンプル少 | 評価不能 | - |

### 4.4 補足発見（採用保留）
- **MA_Pos が PatB BUY の生死を分ける**: BELOW_FAR で PF 3.09、NEAR/BELOW_NEAR で 1.0前後
  - 「深い押し目で勝つ、浅い押し目で踏まれる」という構造
  - **採用判断**: 高加熱フィルター単体 vs +MA_Pos の比較BTで完全な優位性確認後（次セッション課題）

---

## 5. フィルター実装候補（強い→弱い）

[[memory: bt-filter-strategy]] に従い、**ダメパターン削減を主軸**にする:

### 5.1 強い削減推奨（構造的説明あり）
1. **Cross=NONE × SELL 全停止**（PF 0.21、最大死亡帯）
2. **UP×NONE×MID-H 全Pattern**（局面6つ全死）
3. **PatD SELL 全停止**（PF 0.48）
4. **PatC × MID-H 全停止**（PF 0.83、構造矛盾）

### 5.2 中程度の削減候補
5. **PatB × MID-H BUY 注意**（PF 0.75、押し目過ぎ）
6. **PatD × HIGH 全停止**（PF 0.77）
7. **PatC BUY 全体警戒**（PF 0.72）
8. **PatB SELL 全体警戒**（PF 0.68）

### 5.3 想定効果（推定）
- 元PF 1.26 → 1.6〜1.9程度（マイナスパターンを構造的に排除）
- 削減件数: 481件中 約100件程度
- ※ 実際の効果は再BTで検証要

---

## 6. 留意点

| 項目 | 内容 |
|------|------|
| **局面バイアス** | UP 83.1% / DN 17.2%。サンプル偏り強い |
| **DN×BU 局面サンプル不足** | N=16のみ。現局面（SELL優勢のPD期）継続前提で蓄積必要 |
| **フォワード検証必須** | このマップはBT統計の優位性。実トレードでの再現性は別途確認 |
| **MA_Pos 採用は別途** | 高加熱フィルター単体 vs +MA_Pos の比較BT必要 |
| **D1ロジック未深掘り** | D1 ATRパターン/ADX velocity 等の詳細は未分析 |

---

## 7. 次への種（宿題）

| # | 課題 | 優先度 |
|---|------|--------|
| 1 | フィルター実装BT（5.1〜5.2 を mq5 化、再BT） | 高 |
| 2 | DI Velocity を BT mq5 に追加（発火→決済時のDI推移記録） | 中 |
| 3 | 高加熱フィルター単体 vs +MA_Pos の比較BT | 中 |
| 4 | DN×BU 局面のサンプル蓄積（フォワード or 過去期間拡張） | 高 |
| 5 | PatA SELL WIN群の構造分析（リバーサル捕捉の中身） | 低 |
| 6 | 時間帯（Hour）別の分析 | 低 |
| 7 | このマップを heatmap_v14 等の認識ツールに組み込み | 高（フェーズ2本筋） |

---

## 8. 関連ファイル

- BTソース: `data/bt/ATR_WidthSignal_BT_v3bywavelog.mq5`
- BT結果CSV: `data/bt/ATR_WidthSignal_BT_NEW.csv`
- 仕様書: `data/bt/SPEC_new_BT.md`
- SLTP設計: `data/bt/SLTP_design.html`
- 分析原則: [[memory: bt-analysis-principles]]
- 局面バイアス注意: [[memory: bt-regime-bias]]
- フィルター戦略: [[memory: bt-filter-strategy]]
- BT世代1発見サマリ: [[memory: bt-v1-findings-2026-06]]
