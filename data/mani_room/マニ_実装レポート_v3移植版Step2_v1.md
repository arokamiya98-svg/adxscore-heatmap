# マニ実装レポート: 日次認識カレンダー v3 移植版 Step 2

> 実装: 2026-06-12 マニ
> 指示書: `data/mani_room/マニ_指示書_v3移植版Step2_v0.3.md`（唯一の正）
> 対象: `scripts/generate_daily_calendar_v3.py`
> 出力: `data/trades/processed/daily_calendar_v3.html`（再生成済み）

---

## B1: ドロワー opacity バグ — 原因と修正

### 原因（特定済み・実行ベースで実証）

JS の `fireCard()` が **外側 `<div class="fire-card ...">` の閉じ `</div>` を返していなかった**。

```js
// 修正前（カードを閉じずに終わる）
return `<div class="fire-card${f.pass_all ? "" : " suppressed"}">` +
  ... +
  filt + mmSteps(f);          // ← </div> がない
```

`tradeCard()` は末尾 `+ \`</div>\`` で閉じているのに、`fireCard()` だけ閉じていなかった。
`drill-body.innerHTML` に流し込む際、ブラウザが未閉鎖 div を**入れ子として解釈** → 抑制カード（`.fire-card.suppressed { opacity: 0.55 }`）以降の全カード（後続発火カード・実トレードカードまで）がその**子要素になり opacity を継承** → 全部薄くなって読めない、という現象。

### 修正

```js
// 修正後
filt + mmSteps(f) + `</div>`;
```

### 検証（2026-05-06 = 発火10件/うち抑制8件/実トレード1件の混在日）

生成HTMLから実際の `fireCard` / `V3_FIRES` を抽出・実行して div 開閉バランスを計測:

```
$ node（生成HTML内の fireCard を eval して 2026-05-06 のドロワーbodyを実生成）
2026-05-06 ドロワーbody(発火10件): 最終depth = 0 / 最小depth = 0 （期待 0 / 0 = 入れ子なし・過剰閉じなし）
抑制カード1枚の div バランス = 0 （期待 0）
```

修正前の構造シミュレーション（同日10カード）では未閉鎖 div = 10（実トレードカードが10段入れ子）、修正後 = 0（全カードが兄弟要素）。opacity は個々の抑制カードのみに適用される。

---

## B2: 9本フィルター デフォルトON

- **ドット**: CSS `#tab-calendar:not(.show-all-fires) .fire-dot.suppressed { display: none; }` でデフォルト非表示。全ドット抑制の日は行ごと非表示（`.fires-row.all-suppressed`）
- **ドロワー**: `renderDrill()` がトグル状態で `pass_all` フィルター。pass ゼロ日は「pass_all の発火なし（抑制 N件 — 全発火表示で確認）」表示。トグル切替時、開いているドロワーは即再描画
- **ヘッダー集計**: `<span id="v3-fire-summary">` 連動
  - デフォルト: `シグナル発火: 265件 (pass_all のみ表示 / 抑制 124件 非表示)`
  - トグルON: `シグナル発火: 389件 (pass 265 / 抑制 124 薄表示)`
- **トグルUI**: 凡例直下に `.fires-filter-bar`（チェックボックス「全発火表示（抑制 124 件を薄表示で追加）」）

## B3: 期間のトレードログ基準化 + 折りたたみ

- `default_start_month = max(トレード初月, 最終月-5ヶ月) = max(2026-03, 2026-01) = 2026-03`
- 2025-03〜2026-02（12ヶ月・発火のみの期間）を `<details class="past-months">` で折りたたみ。summary =「過去を表示 ▸ 2025-03〜2026-02（トレードログ開始前・発火のみの期間 / 12ヶ月）」、展開時「過去を隠す ▾」
- 発火389全件は DOM に常に存在（展開 + 全発火表示トグルで全件可視）。セルクリック→ドロワーも折りたたみ内で動作（リスナーは DOM 全セルに付与済み）

---

## 検証コマンド + 出力

### 生成（セルフチェック内蔵、全 assert PASS）

```
$ python3 scripts/generate_daily_calendar_v3.py
OK 出力: /Users/aro/Desktop/ADXSCORE/data/trades/processed/daily_calendar_v3.html
[A1-1] signal_fires.csv 読込   : 389 件（期待 389）
[A1-2] HTML描画 fire-dot 数    : 389 件（期待 389）
[A1-5] pass_all 集計           : TRUE 265 / FALSE 124（期待 265 / 124）
[A2-1] ドロワー用トレード      : 30 件 / 26 日（期待 30件・26日）
[B1-1] fireCard 閉じタグ修正    : OK（mmSteps(f) + `</div>` 出力済み）
[B2-1] デフォルト表示ドット数  : 265 件（期待 265 = pass_all のみ）
[B2-2] 全発火表示時ドット数    : 389 件（期待 389、抑制 124 件は薄表示）
[B2-3] フィルタートグルUI      : OK / ヘッダー連動 OK
[B3-1] デフォルト表示開始月    : 2026-03（期待 2026-03 = トレードログ基準 / 直近6ヶ月上限）
[B3-2] 折りたたみ過去月        : 2025-03〜2026-02 の 12 ヶ月（details 出現 1 箇所、期待 1）
全チェック PASS ✅
```

### ドット数（デフォルト 265 / 展開時 389）

```
$ grep -o 'class="fire-dot[^"]*"' data/trades/processed/daily_calendar_v3.html | wc -l
fire-dot 総数(全発火表示=展開時):  389
suppressed(デフォルト非表示):      124
デフォルト表示(pass_allのみ):      265
```

### B3 構造（折りたたみ内/外の月割り）

```
$ python3（month-title の details 内外判定）
B3 折りたたみ内: 2025年 3月 〜 2026年 2月 (12ヶ月)
B3 デフォルト表示月: ['2026年 3月', '2026年 4月', '2026年 5月', '2026年 6月']
```

### 禁止4ファイル diff なし

```
$ git diff --stat -- scripts/generate_daily_calendar.py data/trades/processed/trades_calendar.html \
    scripts/generate_signals_calendar.py data/trades/processed/signals_calendar.html
(出力なし = diff なし)
```

- `generate_daily_calendar.py` / `generate_signals_calendar.py`: git 追跡・diff なし
- `trades_calendar.html` / `signals_calendar.html`: git 未追跡の生成物。mtime = 本日 06:24（今回の v3 生成 07:25 より前）＝ 今回タスクで未変更。v3 スクリプトの書き込み先は `daily_calendar_v3.html` の 1 ファイルのみ（`out_path = OUT / "daily_calendar_v3.html"`）

---

## 変更しないこと（遵守確認）

- トレード帯（++59k 形式）: 触っていない（バー化中止を docstring に明記）
- 土曜発火の金曜セル併載: 維持（fold 31件、A1-6 で確認）
- v2 由来の見た目・機能: 変更なし（変更は B1〜B3 の追加 CSS/JS/折りたたみのみ）

## 完了条件チェック

- [x] B1: 抑制混在日（2026-05-06）のドロワーで実トレードカードがフル可読（div バランス 0 を実行ベースで実証）
- [x] B2: デフォルト = pass のみ（ドット 265）、トグルで 389 全件
- [x] B3: デフォルト表示 2026-03〜2026-06、過去 12 ヶ月は折りたたみ・展開で発火全件
- [x] 禁止4ファイル diff なし / 検証コマンド+出力貼付
- [x] レポート本ファイル

*マニ Step 2 完了 — 2026-06-12*
