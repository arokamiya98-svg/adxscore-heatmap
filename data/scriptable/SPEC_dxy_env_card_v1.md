# SPEC: DXY環境札（迷い検出札） v1 — VPSルート確定版

> 作成: 2026-07-14 おぱ / 最終更新: 2026-07-15（ルート確定）
> 根拠分析: `data/dxy/DXY_ADX56_x_XAU_SIGNALS_v1.md`（カイv1）+ `analyze_dxy_di_depth_v2.py`（DI深さ×精度）
> ステータス: 🟢 実装フェーズ（コー: EA/generator/widget、ブン: 配管・デプロイrunbook）

## ルート決定の経緯（2026-07-15確定）

1. Twelve Data案（あろさん初回希望）→ **DXY指数がTwelveに存在しない**（DXYN/DXYZ株とUUP/UDN ETFのみ。ETFは市場時間バーで物差し別物＝不可）
2. Yahoo `DX-Y.NYB` 案 → 実測検証**不合格**（`data/dxy/validate_yahoo_dxy.py`: spread相関0.596・平均絶対差5.18・深さラベル一致率33.4%。閾値も分析もHFM USDIndex由来のため載せ替え不能）
3. **VPSルートに確定**（あろさん承認）: VPSの `iADX("USDIndex",H1,56)` は分析と同一物差し＝検証不要

---

## 1. 札の性格づけ（設計思想）

- **D1環境札と同じ「環境認識」ファミリー**の一員。DXYは粗い札 — ADX(56)/DIは平滑で帯遷移に日単位。速報性は不要（毎時確定値で十分）
- 本質は方向札ではなく**「迷い検出札」**: DXYが決まってるか迷ってるかを読む
  - 根拠: 死に帯は方向でなく「揺らぎ帯」（BUY×USD_DN揺らぎ PF0.62/33%、SELL×USD_UP揺らぎ PF0.77/29%、BT/FW両ソース一致）
  - 中間帯の曖昧さ系列の4例目（D1 ADX20-30罠 / ADX56 25-30凹み と同族）
- ラベル層の札。点数化しない。組合せ判断（シグナル方向×DXY状態）はあろさんの認知の仕事、札は状態表示まで

## 2. 深さラベル（HFM USDIndex実測・段階化厳守）

|spread| = |DI+ − DI−|（USDIndex H1・ADX(56)付属DI・確定バー）

| ラベル | 閾値 | 滞在率 | 読み方（骨肉） |
|--------|------|--------|---------------|
| 拮抗 | <2 | 23% | **DXY読まない**。方向はコイントス、XAU内部だけで判断 |
| 揺らぎ | 2-5 | 29% | **⚠迷い帯**。特に「DXY追い風のはず」側が死ぬ（BUY時のドル安揺らぎ/SELL時のドル高揺らぎ） |
| 優勢 | 5-10 | 32% | 方向が意味を持つ。USD_UP優勢×BUY=押し目製造機（F後PF≈3）/ USD_DN優勢×BUYも可（両期間+） |
| 一方通行 | ≥10 | 17% | 情報はあるが**不安定帯**（BT/FW割れ）。過信しない・※印 |

- 判定は**表示値（小数1桁丸め後）**で行う（数値とラベルの見た目矛盾防止＝d1_env生成器と同規約）
- D1環境札の閾値（<5/5-10/10-16/≥16）とは**別スケール**。同じ意味論・別の物差し。UIで数値を混ぜない

## 3. データ経路（VPS・既存動脈に完全相乗り）

```
VPS: XAUUSD_DailyBatch_EA_v1（系統B・毎時）に追加
  └ iADX("USDIndex", PERIOD_H1, 56) の最終確定バー(shift=1)を取得
     → mt5_data/daily/dxy_env.csv（1日1行・当日行を毎時更新・UTF-8-sig）
     列: date, dxy_adx56, dxy_di_plus, dxy_di_minus, dxy_di_spread, dxy_di_dir
  ↓ 既存 vps_data_pool_push（daily/）
Mac: generate_d1_env_json.py
  └ dxy_env.csv を読み d1_env.json に "dxy" ブロックをマージ
     （ファイル欠落/パース不能時はブロック省略＝グレースフル）
  ↓ 既存 run_daily_calendar.sh Step2.55→2.6 / hourly_sync publish（両リスト登録済み 2026-07-14修理）
iPhone: d1_env_widget.js — 既に読んでいる d1_env.json の dxy ブロックを表示
  （Twelve fetch/Wilder JS計算/APIキーは全廃 → キー管理消滅）
```

**daily_aggregate.csv には列を足さない**（複数コンシューマのスキーマ不変・別ファイル分離）。

## 4. JSONスキーマ（d1_env.json 追記分）

```json
"dxy": {
  "date": "2026-07-15",
  "adx56": 14.2,
  "di_spread": 9.8,
  "di_dir": "USD_UP",
  "depth_label": "優勢",
  "spread_range_5d": { "min": 8.3, "max": 13.3 }
}
```

- `di_spread` 符号付き（+ = USD_UP）。`spread_range_5d` は直近5**営業日**（土日行除外・D1と同じ地雷対策）
- dxy_env.csv が無い/読めない → `"dxy"` キー自体を出さない（widgetは「取得待ち」表示）

## 5. UI表示（実装済みUIを維持・データ源だけ差替え）

| 状態 | 表示 | 色 |
|------|------|----|
| 拮抗 | `DXY ─ 拮抗`（方向・数値なし） | グレー |
| 揺らぎ | `DXY 〰 迷い +3.2` | アンバー |
| 優勢 | `DXY ⬆/⬇ 優勢 +9.8 (5d 8~13)` | DI基準の方向色（D1札と同じ） |
| 一方通行 | `DXY ⬆⬆/⬇⬇ 一方通行※ +12.4` | 方向色濃 + ※ |
| データ無し | `DXY ─ 取得待ち` | グレー |

- 方向色はDI基準のみ・良し悪しの色付け禁止（USD_UP優勢×BUYが最強セルという逆説が根拠）
- 5dレンジは優勢以上のみ表示。dxyブロックのdateが2営業日以上古い場合は ⚠ を添える

## 6. 実装分担

| 担当 | 作業 |
|------|------|
| コー | ① EA改修（USDIndex ADX56→dxy_env.csv・既存書込パターン踏襲・Mac wineコンパイル0 errors確認） ② generate_d1_env_json.py のdxyマージ ③ d1_env_widget.js のデータ源差替え（Twelve/Wilder/キャッシュ/キー全廃） |
| ブン | vps_data_pool_push の対象確認（dxy_env.csv が乗るか）・VPSデプロイrunbook作成（EA差替え/F7/再アタッチ/USDIndex気配値・履歴確認）・動脈地雷スイープ |
| あろさん | VPS RDP 1回（runbook実行）・widget端末反映（キー不要になった版）・導入後数日の目視 |

## 7. 地雷・注意

1. **VPS MT5にUSDIndexがあるか**（気配値追加＋H1履歴DL。EA側は `SymbolSelect` で保険）
2. **履歴未ロード時の初回**: iADXがINVALID/空を返す → **その時刻は書かない**（0値行禁止・次の毎時で自己回復）
3. USDIndexは期限付き先物系 — 限月ロール跨ぎのDI連続性を初回ロールで目視確認
4. 土曜行地雷はD1と同根 — generator側で営業日フィルタ
5. 動脈原則: 固定件数assert禁止（データ増加が常態）

## 8. v1で見送るもの（理由つき）

- ADX56帯（25-30凹み）の表示: N=38の弱シグナル段階（フォワード追認後に再検討）
- 順風/向かい風の自動判定表示: 組合せ判断はあろさんの認知の仕事
- ratio_widget への重複表示: 認知負荷（足すより絞る）
- Twelve/Yahoo外部APIルート: 上記経緯により廃案（検証スクリプトは `data/dxy/validate_yahoo_dxy.py` に保存）
