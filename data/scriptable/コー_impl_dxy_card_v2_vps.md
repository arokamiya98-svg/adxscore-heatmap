# コー実装指示書 v2: DXY環境札 — VPSルート切替（EA/generator/widget 3点）

> 発行: 2026-07-15 おぱ（あろさん承認済み）
> 正書SPEC: `data/scriptable/SPEC_dxy_env_card_v1.md`（VPSルート確定版・必読）
> 前提: v1指示書（Twelve版）で実装したwidgetのUI/ラベル部は**資産として維持**、データ源だけ差し替える

---

## 作業① EA改修: `signals/XAUUSD_DailyBatch_EA_v1.mq5`

**まず既存EAを読んで**、daily_aggregate.csv の書込パターン（当日行の更新方式・エンコーディング・タイマー構造）を把握し、**同じ流儀で** DXY出力を追加する。

- 追加input: `input string DXY_Symbol = "USDIndex";`
- OnInit または初回計算前に `SymbolSelect(DXY_Symbol, true)` で気配値登録の保険
- `iADX(DXY_Symbol, PERIOD_H1, 56)` — ハンドルは初期化時に1回生成・失敗時はDXY部だけスキップ（**既存のXAU処理を道連れにしない**）
- 毎時の書込タイミングで、最終**確定**バー（shift=1）の ADX/DI+/DI- を CopyBuffer 取得
  - 取得失敗（履歴未ロード・空バッファ・値<=0）→ **その回のDXY書込をスキップ**（0値行禁止・ログだけ出す・次の毎時で自己回復）
- 出力: `MQL5/Files/…/dxy_env.csv`（daily_aggregate.csv と同じディレクトリ = mt5_data/daily/ に届く場所。既存EAの出力パス定義に合わせる）
  - 形式: **UTF-8-sig（BOM付き）**・他daily系と同方式
  - ヘッダー: `date,dxy_adx56,dxy_di_plus,dxy_di_minus,dxy_di_spread,dxy_di_dir`
  - 1日1行・当日行を毎時上書き更新（daily_aggregate と同じ更新機構を踏襲）
  - `dxy_di_spread` = DI+ − DI−（符号付き小数2桁）、`dxy_di_dir` = spread>0 ? "USD_UP" : "USD_DN"
- **コンパイル確認必須**: Mac wine CLIで 0 errors / 0 warnings
  ```
  cd "/Users/aro/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/Program Files/MetaTrader 5"
  "/Applications/MetaTrader 5.app/Contents/SharedSupport/wine/bin/wine" metaeditor64.exe /compile:"MQL5\\Experts\\...(実際の配置に合わせる)" /log
  ```
  ※ リポジトリの signals/ が正本。Mac MT5側のEA実体の場所は既存配置を確認して合わせる（無ければ signals/ のコピーで一時コンパイル→ログ確認→掃除）

## 作業② generator改修: `scripts/generate_d1_env_json.py`

- `mt5_data/daily/dxy_env.csv`（UTF-8-sig）を読む。**ファイル欠落/全行パース不能なら "dxy" キーを出さずに従来通りのJSONを出す**（既存D1部の動作は一切変えない）
- 既存の営業日フィルタ（weekday>=5除外）・「表示値で分類」規約をDXYにも適用
- 最新営業日行 → `adx56`(小数1桁), `di_spread`(小数1桁), `di_dir`, `depth_label`（|spread|丸め後: <2拮抗 / <5揺らぎ / <10優勢 / ≥10一方通行）
- `spread_range_5d` = 除外後系列の直近5行の di_spread min/max（小数1桁）
- `date` = 採用行の日付。SPEC §4 のスキーマ通り
- 固定件数assert禁止（動脈原則）。docstringの生成ロジック表にDXY節を追記

## 作業③ widget改修: `data/scriptable/d1_env_widget.js`

- **Twelve関連を全廃**: CONFIG.dxy の api_key/symbol/outputsize、fetchDxySeries、calculateWilderADX、calcDxyRange5d、dxy_env_cache.json のキャッシュ機構 — すべて削除（git履歴に残るので温存不要）
- `getDxy()` を「**既にfetchしているd1_env.jsonの `dxy` ブロックを整形するだけ**」に差し替え
  - `dxy` キー無し → `DXY ─ 取得待ち`（グレー）
  - `dxy.date` が2営業日以上古い → 行に ⚠ を添える（鮮度警告・D1と同じ視覚言語）
- **UI表・色・矢印・※・5dレンジ表示規則はv1実装のまま**（SPEC §5）。depth_labelはJSON側の値をそのまま使う（widget内で再判定しない＝判定ロジックの一元化）
- CONFIG.dxy は `{ stale_business_days: 2 }` 程度まで縮小
- 検収: `node --input-type=module --check` 構文OK / dxy有り・無し・古いdate の3パスをスタブで確認 / 既存D1表示部に差分ゼロ（git diff）

## 禁止・注意

- 実キー・外部API呼び出しをwidgetに残さない（全廃の確認）
- daily_aggregate.csv のスキーマ・既存列に触らない
- 点数化・順風/向かい風判定を足さない（SPEC §8）
- EAのXAU側処理・既存出力3ファイルの動作を変えない
