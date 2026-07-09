# Scriptable D1環境札 Widget v1 仕様書

> 作成: 2026-07-10 / メインおぱ
> 実装担当: **コー**（widget js）＋ **ブン**（JSON生成・動脈組み込み）
> 実装ファイル: `data/scriptable/d1_env_widget.js`（**新規**・既存 `atr_widget.js` / `ratio_widget*.js` は一切触らない）
> 関連: `SPEC_atr_widget_v1.md` / `SPEC_ratio_widget_v1.md` / CLAUDE.md §11 D1ラベラーv1.2（Layer B/C）
> 発端: 2026-07-09〜10 セッション。D1 DIスプレッドの拮抗化（-18→-2→-10）があろさんの認識外だった件。「D1 DIスプレッド環境ラベル化」の種（あろさん「面白い」2回目）の発芽。

---

## 1. 設計コンセプト

**D1環境（大局）の「方向」と「拮抗度」を2枚のラベルで分離表示する認識ツール。**

- 課題: チャートのADX反応ゾーン（赤色分け）だけでは **DI内部の拮抗度が見えない**。2026-07-03〜06にスプレッドが-2まで拮抗していたのを、あろさんは「まだBEAR」の一枚看板で見ていた → 環境の不確定感の正体が事後にしか分からなかった。
- 解: **方向ラベル（BEAR/BULL/RANGE）× 拮抗度ラベル（拮抗/揺らぎ/優勢/一方通行）** の2軸。方向が同じでも拮抗度で「環境の確度」が変わる。
- **ラベル層厳守**: 点数化しない。段階ラベルのみ（連続グラデーション禁止・あろさんの認識粒度は段階）。
- **RANGE ≠ 凪**: RANGE = ADX閾値未達（横ばい）。凪（ATR収束）とは別概念。このウィジェットのRANGEはADX基準。

### 既存ウィジェットとの住み分け

| | atr_widget | ratio_widget | **d1_env_widget（新規）** |
|---|---|---|---|
| TF | H1/H4 | H1(/H4) | **D1のみ** |
| 役割 | 加熱🔴で止める | 収束/拡張の$基準線 | **大局の方向×確度** |
| データ | Twelve Data 計算 | Twelve Data 計算 | **MT5確定値（VPS動脈）** |
| 鮮度 | リアルタイム | リアルタイム | 毎時（D1は1日1回変化で十分） |

---

## 2. データルート（確定値ルート・Twelve Data不使用）

**D1環境は大局ラベル＝「確定情報＞計算予測」の対象。** ADX/DIの二重平滑は自前計算だと誤差が蓄積し、D1は日足境界（サーバーGMT+2/3 vs UTC）ズレの影響も大きい（ratio_widget H4札の2割乖離と同じ穴）。よってMT5のiADX直値を運ぶ。

```
VPS EA（毎時） → mt5_data/daily/daily_aggregate.csv （既存・触らない）
    ↓
[新規] scripts/generate_d1_env_json.py → docs/d1_env.json （ブン）
    ↓ run_daily_calendar.sh に1ステップ追加＋publishホワイトリストに追加（ブン）
GitHub Pages: https://arokamiya98-svg.github.io/adxscore-heatmap/d1_env.json
    ↓
Scriptable d1_env_widget.js が fetch（コー）
```

---

## 3. JSON スキーマ（docs/d1_env.json）

```json
{
  "updated": "2026-07-09",
  "generated_at": "2026-07-10 09:42",
  "adx22": 31.0,
  "adx_state": "BEAR",
  "di_plus": 15.3,
  "di_minus": 24.8,
  "di_spread": -9.5,
  "spread_range_5d": { "min": -10.4, "max": -2.0 },
  "spread_label": "揺らぎ",
  "atr_ratio": 1.04,
  "atr_cross_dir": "UP",
  "atr_cross_days": 21
}
```

### 生成ロジック（generate_d1_env_json.py・ブン実装）

入力: `mt5_data/daily/daily_aggregate.csv`（UTF-8-sig）。最終行＝最新確定日。

| フィールド | 定義 |
|---|---|
| `adx_state` | `d1_adx22 < 20 → "RANGE"`（方向を出さない）／ `>= 20 → d1_di_dir`（"BEAR"/"BULL"） |
| `di_spread` | `d1_di_spread` 最新値（符号付き。負=DI-優勢） |
| `spread_range_5d` | 直近5営業日の `d1_di_spread` min/max。**⚠️ daily_aggregate には土曜行（VPS土曜JST朝稼働による金曜バー複製）が混在するため、土日行を除外した直近5行を使う**（2026-07-10 ブン発見・確定） |
| `spread_label` | \|spread\|で段階: **<5 拮抗 / 5〜10 揺らぎ / 10〜16 優勢 / ≥16 一方通行**（2026-03〜07実測102日の四分位: 25%=4.3 / 50%=8.9 / 75%=13.7） |
| `atr_ratio` | `d1_atr22_42_ratio` 最新値 |
| `atr_cross_dir` | ratio ≥ 1.0 → "UP"（拡張フェーズ）／ < 1.0 → "DOWN"（収束フェーズ） |
| `atr_cross_days` | ratio系列（**土日行除外**）を遡り、直近の1.0跨ぎからの営業日数（クロス後最初の同サイド行=0日目、EA規約と同一）。データ範囲内に跨ぎ無し→ `99` 固定（表示 "99+"）。検証済: 07-08時点=21 ＝ EA `d1_cross_bars` と完全一致 |

**検証手順（実装後1回）**: `atr_cross_days` を `mt5_data/daily/signal_fires.csv` の `d1_cross_bars`（EA計算値）と直近発火日で突合。参考: 2026-07-08発火 #416 は `d1_cross_bars=21`・`cross_dir=BU`（=UP）→ 一致すること。

---

## 4. 表示（small ウィジェット・レイアウトモック）

```
┌────────────────────┐
│ D1 環境            7/9 │   ← updated 日付
│                        │
│ BEAR   ADX 31          │   ← 行1: 方向×ADX実値（最大サイズ）
│ DI -9.5  〰 揺らぎ      │   ← 行2: スプレッド現値＋おぱラベル
│   5日: -2 〜 -10        │   ← 行3: 直近レンジ（小さく）
│ ATR ↑拡張 21日目        │   ← 行4: クロスフェーズ
└────────────────────┘
```

### 表示ルール

- **行1（方向×ADX）**: `adx_state` が主役。
  - `BEAR` = 赤 / `BULL` = 青（**色はDI方向のみ**。ATR系に色を焼かない）
  - `RANGE` = グレー。このとき表示は `RANGE  ADX 18`（方向文字を出さない）
- **行2（拮抗度）**: `DI {di_spread}` ＋ おぱラベル。ラベルアイコン: **🌫 拮抗 / 〰 揺らぎ / ➡ 優勢 / 🔥 一方通行**。文字色はニュートラル（白/グレー系）＝拮抗度は方向情報ではない。
- **行3（直近レンジ）**: `5日: {max} 〜 {min}` 小フォント・サブ色。拮抗化/再拡大の「動き」を読むための帯。
- **行4（ATRクロス）**: `ATR ↑拡張 {days}日目` / `ATR ↓収束 {days}日目`。ラベルのみ、ratio数値は出さない（幅の実値は ratio_widget の領分）。
- **鮮度ガード**: `updated` が3営業日超過 → ヘッダに ⚠️（動脈停止の検知）。
- **fetch失敗時**: iCloud にキャッシュした前回JSONで表示＋ヘッダに 🔌（atr_widget と同じFileManagerパターン）。

### 禁止事項（このウィジェットで絶対にやらないこと）

- ❌ スプレッドやADXの点数化・スコア合成（ラベル層。ADXスコアは週次ヒートマップの領分）
- ❌ 連続値のグラデーション表示（段階ラベルのみ）
- ❌ 売買方向の示唆（「売り環境」等の文言禁止。方向はDI事実の表示まで）
- ❌ Twelve Data での自前ADX計算へのフォールバック（確定値が取れないなら⚠️を出して止まる）

---

## 5. 実装分担と順序

| # | 担当 | 作業 | 完了条件 |
|---|---|---|---|
| 1 | ブン | `scripts/generate_d1_env_json.py` 新規（§3） | ローカル実行で docs/d1_env.json 生成・§3検証手順パス |
| 2 | ブン | `run_daily_calendar.sh` に生成ステップ追加＋ **Step2.6 publishホワイトリストに d1_env.json 追加** | 素の `./run_daily_calendar.sh` で Pages に JSON が上がる |
| 3 | コー | `data/scriptable/d1_env_widget.js` 新規（§4） | 実機で表示・fetch失敗キャッシュ動作確認 |

- 依存: 3 は 2 の Pages URL 疎通後に実機確認（実装自体は並行可）。
- ⚠️ ブンは動脈に触るため作業前 `git pull --rebase`、既存3枚のpublish動作を壊さないこと（Step1恒久対応 `dafbbf2` の受信確認ロジックに手を入れない）。

---

## 6. 運用メモ

- 更新頻度: VPS毎時push → Macのrun_daily_calendar実行タイミングでJSON更新。D1確定値は1日1回変化なので十分。
- 配置想定: iPhone/iPadホームの既存ウィジェット群に追加（small）。上=Widget Web週次マクロ / 下=Scriptableライブ群、の「下」に入る。
- 8月集中メンテで閾値（5/10/16）を再計測（サンプル102日→蓄積後に四分位を引き直し）。
