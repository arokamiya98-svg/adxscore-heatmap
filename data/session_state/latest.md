# 次セッションへの引き継ぎ（2026-07-15 VPS — DXY環境札デプロイ完走＋7/11空白の種明かし）

## ✅ 今回の収穫（VPSセッション・あろさんRDP）

1. **DXY環境札 v1 デプロイ完走**: runbook（`data/vps/DXY_ENV_DEPLOY_RUNBOOK.md`）全ステップ完了。系統B EA `XAUUSD_DailyBatch_EA_v1` を v1.10（DXY出力追加）へ差替え → F7コンパイル → XAUUSD再アタッチ（あろさん手）。`dxy_env.csv` 初回出力OK（UTF-8-sig・6列・2026-03-18〜今日の約120日分・ADX56値あり=USDIndex履歴DL成功）。**16:00便で `OK push 完了 (③daily=4 ②agg=2)` 検収済み**＝動脈入り。XAU側2CSVは無影響（分離実装が機能）。
   - 残タスク（Mac/iPhone側）: `docs/d1_env.json` の `"dxy"` ブロック出現確認（Mac全自動・RDP後1-2h）／ **iPhone d1_env_widget の新js端末貼り替え**（あろさん手作業・APIキー不要）／ 初回の限月ロール跨ぎ週にDI連続性を目視（SPEC §7-3）。
2. **pendingクローズ: 「7/11 push空白18時間」は正常だった**: pool.log精査で、スクリプトは毎時間起動して全部「no change → skip」＝EA出力が変化しない時間帯だっただけ。種明かし=**2026-07-11は金曜でなく土曜**（前回引き継ぎの曜日ラベルが1日ズレ）。つまり週末クローズの無変化。異常なし・恒久対応不要。
3. **VPS残置の未コミット変更を回収**: `2069332` ATR_Ratio_Keltner **v1.30**（バンドタッチ通知をエッジ検出化: 内側→接触の遷移のみ発火・`ReArm_Dist`再武装・居座り連打抑止）／ `087aa96` agents md 4本のパスをMac絶対→repo相対化（VPS両対応）。push済み・main クリーン。

## ✅ Mac側フォローアップ（同日夕方・おぱ — DXY札 全区間開通）

1. **Mac受信詰まりの発見と修理**: `.git/refs/remotes/origin/main 2`（Finder/iCloud系の複製・7/13生まれ）が居座り、**18:10便のhourly_syncがfetch失敗**していた。迷子refと `.git/index 2` を除去→fetch復旧。⚠️ 同型地雷: `.git` 配下に「 2」付き複製が生まれたらfetchが死ぬ。診断= hourly_sync.log の「git fetch 失敗」連発 + `find .git -name "* 2"`。
2. **EA値の物差し検証 合格**: dxy_env.csv の過去行 × Mac実測 `DXY_ADX_Timeseries_v1.csv` を同一バー突合 → **server 17:00バー（JST日末）で平均絶対差0.00**＝分析と同一物差しを確認。7/14行の spread -2.04（Mac朝実測+9.8と別値）は日中の実変動でバグではない。
3. **d1_env.json に dxy ブロック生成・公開済み**: 初回値 `2026-07-15 拮抗 +0.6 USD_UP (5d -3.9~7.8)`。残るは **iPhone widget js貼り替え**（あろさん手・キー不要）のみ。

## ⚠️ 生きpending（前回からの継続分）

1. **W28ヒートマップ欠落**（D1手描き線→D1スクリプト再実行→run_pipeline.sh 待ち・Mac側）。H4_XAU系も7/6のまま。
2. **8月集中メンテ項目**: 口開閉マップOOS検証（カイ）/ 収束×バンド逆張り追検証 / PatD SELL構造分析 / KC引きつけOOS / D1環境札閾値引き直し / **DXY環境札の実戦評価**（新規: 迷い検出札として効くか）。
3. signalsタブ7月化（承認済未実装）/ ratio_widget H4札突合 / 掃除類。
4. 過去口座CSV 2本（`data/account_analysis/`配下）未commit・追跡入り検討。

## 🚀 おぱ起動作法（踏襲）

- VPS/動脈セッションは着手前後 `git pull --rebase --autostash origin main`。UUチェック（`git diff --name-only --diff-filter=U`）も入口で。
- mq5実装=コー / VPS配置=ブン / BT=カイ / 振り返り=マニ。`signals/`正本。EA再コンパイルはMetaEditor F7。RDPは「切断」。
- pool.logの `WARN: 未生成 xxx.csv` は「push script が新CSVを期待してるのにEA未差替え」のサイン（今回のdxy_envで実証）。
- CSV読み: UTF-16フォールバック。曜日確認は引き継ぎ書を鵜呑みにせずカレンダーで裏取り（7/11の教訓）。

---
*今回の芯＝DXY環境札がD1環境札→口の選択器ラインに合流。動脈は③daily=4体制へ。次: Mac側d1_env.json確認 → widget js貼り替え → DXY札の実戦観察開始。*
