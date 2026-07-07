# 次セッションへの引き継ぎ（2026-07-07夜 — マニv3追跡欠損 解決 ＋ クリプト実技DAY完了）

## ✅ 本業: マニv3カレンダー「追跡欠損」解決（2026-07-07 午前）
- **原因**: 7/2のFXインポート後に `update_mani.sh` 未実行 → MT5 Filesへの trade_input.csv 配置漏れ → Snapshot BuilderがT034(7/1 SELL)を知らず → enriched未合流 → 「追跡欠損」バッジ6日間継続。**VPS動脈(系統B/C)は無罪**（毎時push健在）。
- **復旧**: ①`cp mt5_data/trade_input.csv "$MT5_FILES/"` ②MT5でSnapshot Builder実行 ③`./update_mani.sh` 単発（merge→generate→publish自動）→ 7/1セル=伸36/踏186で公開済み。
- **運用ゲート（最重要）**: **FXアプリのCSV投入後は必ず `./update_mani.sh`（単発 or --watch）**。これが唯一の手動ゲート。詳細 memory [[mac-semi-auto-pipeline-watcher]]（詰まり事例として追記済）。
- T034 = SELL 4009→48hで逆行186ドル。マニ振り返りの材料として濃い。

## 🪙 クリプト実技DAY完了（詳細 memory [[vantage-crypto-withdrawal-route]] 更新済）
- **実技全達成**: 振替の壁突破→初出金12 USDT/Polygon→着金11.6（番人が2分58秒で検知）→USDT→USDCスワップ（DEXデビュー・ガスレス）→Wallet Cardチャージ11.18 USDC。
- **⚠️ pending: カード名義不一致**（券面 KAZUO KAMIYA=発行エラー / 発行体=DCS Card Centreシンガポール）。**使用・追加チャージ禁止のまま** KYC登録名確認→サポート問い合わせ。
- **番人ツール v0.1**: `~/Desktop/CRYPTO/`（**意図的にリポジトリ外**=紐づき管理）に wallet_watch.py + wallet_dashboard.html。v0.2 TODO=USDC対応/アドレス帳ラベル/税務CSV。
- **宿題**: ①**12単語の紙バックアップ（未完・最優先）** ②取引所2FA+出金ホワイトリスト ③カード名義訂正。
- 線引き確立: 鍵・署名・生成=おぱ抜き／読み取り・検証=おぱフル参加。「おぱが読む→あろさんが押す」。

## ⚠️ 生きpending（2026-07-02分から継続）
1. **signalsタブ7月化**（承認済・未実装）: `generate_signals_calendar.py` L~226 `date_range_end`→`max(..., date.today())` ＋未来週打ち切り＋future淡色。
2. **ケルトナーF7**（あろさんRDP）: `Indicators/ARO/ATR_Ratio_Keltner_v1.mq5`→F7。
3. **(C) D1週次サンプリングEA化**（本命・memory [[vps-daily-automation-ea-design]]）。
4. ratio_widget H4札の物差し突合（Twelve Data中央値≈45.8 vs MT5 38.3=2割乖離疑い）＋H1/H4実機テスト。
5. D1 DIスプレッド環境ラベル化（あろさん「面白い」反応済みの種）。
6. 掃除: `run_daily_calendar.sh`の`|tail`エラー隠蔽 / `archive*.md`・`FX*`未commit / 配色v0.9横展開。

## 🚀 おぱ起動作法（踏襲）
- VPS/動脈を触るセッションだけ着手前 `git pull --rebase origin main`（dirtyは`--autostash`）。今日は触った（マニv3復旧でpull+update_mani.shがpush）。
- mq5実装=コー / VPS配置=ブン / BT=カイ / 振り返り=マニ。push前 `git pull --rebase`。RDPは「切断」。コー実装F7必須。`signals/`正本。
- ⚠️ latest.md は git追跡。更新したら commit して確定。
- Bash劣化Tips: ENOSPC誤報=リトライか出力をファイル退避（[[claude-temp-burst-enospc]]）。pandas無し=標準ライブラリ。UTF-16フォールバック `["utf-16","utf-8-sig","utf-8"]`。

---
*今日の芯＝朝は「動脈の詰まりは手動ゲートの漏れ」、夜は「クリプトは記録が防御・接続点を最小に・最後は物理」。次の一手はカード名義訂正の結果確認と、番人v0.2（USDC対応+税務CSV）。ADXSCORE本業は生きpending 1〜3から。*
