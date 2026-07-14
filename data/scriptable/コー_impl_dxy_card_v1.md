# コー実装指示書: DXY環境札（迷い検出札）v1 — d1_env_widget.js 改修

> 発行: 2026-07-15 おぱ（あろさん承認済み・SPEC確定）
> 正書SPEC: `data/scriptable/SPEC_dxy_env_card_v1.md`（§5 UI表・§7 地雷は必読）
> 対象ファイル: `data/scriptable/d1_env_widget.js`（このリポジトリ内ミラーが正本。端末反映はあろさん手動）

---

## 0. スコープ

- **d1_env_widget.js 単一ファイルの改修のみ**。d1_env.json生成側・hourly_sync・VPS・他widgetは一切触らない
- atr_widget.js（同ディレクトリ）の Wilder計算・API呼び出し・キャッシュfallbackの**流儀を踏襲**する（読んでから書く）

## 1. CONFIG追加

既存CONFIGに追加（キーは必ずプレースホルダーのまま。実キーは端末側であろさんが投入）:

```js
dxy: {
  api_key: "<TWELVE_DATA_API_KEY>",
  symbol: "DXY",              // プラン都合で変える可能性あり→設定化
  interval: "1h",
  outputsize: 1500,           // ADX(56) Wilder収束用（終端値のみ使用）
  adx_period: 56,
  thresholds: [2, 5, 10],     // 拮抗/揺らぎ/優勢/一方通行 の境界
  cache_file: "dxy_env_cache.json",
  cache_stale_hours: 24
}
```

## 2. データ取得（Twelve Data）

- `https://api.twelvedata.com/time_series?symbol=DXY&interval=1h&outputsize=1500&timezone=UTC&apikey=...`
- レスポンスは新しい順 → **古い順に反転**してから計算
- **確定バーのみ**: 最新バーのdatetimeが現在UTC時のバーなら形成中として捨てる（判定が面倒なら「常に先頭1本捨てる」で可＝粗い札なので1h遅れは許容）
- `status: "error"` / HTTP失敗 / パース失敗 → §5キャッシュfallbackへ。Request に timeoutInterval 10s

## 3. Wilder ADX(56)/DI 計算（JS実装）

標準Wilder。1500本を古い順に:

1. TR / +DM / -DM を各バーで算出
2. 初期値: 最初のperiod本の単純和 → 以後 Wilder平滑 `X = X_prev - X_prev/56 + x_now`
3. DI+ = 100 * SmoothedDM+ / SmoothedTR、DI- 同様
4. DX = 100 * |DI+ - DI-| / (DI+ + DI-)、ADX = DXのWilder平滑（初期はperiod本平均）
5. **使用するのは終端（最終確定バー）の ADX / DI+ / DI- のみ**。先頭側は収束用で表示に使わない
6. spread = DI+ - DI-（符号付き。+ = USD_UP）

検収用に、計算結果を `console.log` で出す（date, adx56, di+, di-, spread, label）。

## 4. ラベル判定と5dレンジ

- |spread| を SPEC §2 の段階に分類: <2 拮抗 / 2-5 揺らぎ / 5-10 優勢 / ≥10 一方通行（**表示値=小数1桁に丸めてから判定**。数値とラベルの見た目矛盾防止＝d1_env生成器と同規約）
- 5dレンジ: spread系列をUTC日付でグループ → **土日を除外** → 各営業日の最終バーspread → 直近5営業日の min/max

## 5. キャッシュ（iCloud・atr_widget流儀）

- 成功時: `dxy_env_cache.json` に `{fetched_at, adx56, di_plus, di_minus, spread, depth_label, di_dir, range5d:{min,max}}` を保存
- 失敗時: キャッシュがあれば表示＋小さく `(キャッシュ)` 注記。`fetched_at` が24h超なら ⚠ を添える（D1札の鮮度警告と同じ視覚言語）
- キャッシュも無い初回失敗: `DXY ─ 取得待ち`（グレー）

## 6. UI（既存レイアウトにDXY行を1行追加）

既存のD1表示はレイアウト・フォント・色を**一切変えない**。ヘアライン区切りの下にDXY行:

| 状態 | 表示 | 色 |
|------|------|----|
| 拮抗 | `DXY ─ 拮抗` （方向・数値なし） | グレー |
| 揺らぎ | `DXY 〰 迷い +3.2` | アンバー |
| 優勢 | `DXY ⬆ 優勢 +9.8 (5d 8~13)` | 既存のDI方向色を流用 |
| 一方通行 | `DXY ⬆⬆ 一方通行※ +12.4 (5d …)` | 方向色濃 + ※ |

- 矢印: spread>0 ⬆ / <0 ⬇（一方通行は⬆⬆/⬇⬇）
- 5dレンジ表示は**優勢以上のみ**
- 良し悪しの色付け禁止（方向色はDI基準のみ・SPEC §5）

## 7. リフレッシュ

- `widget.refreshAfterDate` を**60分後**に設定（粗い札・API予算節約。既存設定がこれより短ければ60分に引き上げてよい — D1札は日次なので実害なし）

## 8. 検収チェックリスト（実装後に自分で確認できる範囲）

- [ ] 構文エラーなし（node等での簡易パース確認可）
- [ ] APIキー未設定（プレースホルダー）の状態で落ちずに「取得待ち」表示になるコードパスになっている
- [ ] Wilder実装がatr_widget.jsの既存Wilder ATRと同じ流儀（配列向き・初期化）
- [ ] D1側の既存表示ロジックに差分が無い（git diffで確認）
- [ ] console.logで終端値検収が可能

## 9. 禁止・注意

- 実APIキーをコードに書かない（リポジトリはPUBLIC）
- 点数化・順風/向かい風の自動判定を足さない（SPEC §8見送り事項）
- D1環境札の閾値（<5/5-10/10-16/≥16）と混同しない — DXYは 2/5/10 の別物差し
- ファイル分割しない（Scriptableは単一スクリプト運用）
