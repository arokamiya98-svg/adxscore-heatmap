# 次セッションへの引き継ぎ（2026-11-21更新 — HFM→Exness移行・VPS復旧・DXY札を合成DXYで復活）

## ✅ 11/20〜21の収穫
1. **VPS停止の正体**: HFM口座が未使用でアーカイブ → 11/12〜価格フィード停止。箱・schtasks・push・EAは全部生きてた（EAは暦日120日窓で毎日1行ずつ古い行を落とすだけ＝診断の決め手）
2. **Exnessセント（`XAUUSDc`・Exness-MT5Real46）へ移行**: 同じVPSのMT5ターミナルで口座だけ切替＝データフォルダ不変・push script/schtasks無改修。EA4本の Allowed_Symbol を XAUUSDc に（`adfd34a6`・VPSおぱ）
3. **物差し切替点 = 2026-11-20**: Exness=GMT+0固定 / HFM=EU DST連動 GMT+2/+3（カイが132週で確定）。D1/H4足の区切りが変わった＝BT・D1環境札閾値はHFM足由来 → 8月メンテ相当の見直し項目に合流
4. **DXY札を合成DXYで復活**: ICE式SEK除外5項（EURUSDc/USDJPYc/GBPUSDc/USDCADc/USDCHFc・M5）→ カスタムシンボル `DXY_SYNTH`。系統B EA v1.11（`06a77ba9`）で毎時差分更新。dxy_env.csvスキーマ不変
   - 検証: H1 4段ラベル一致64.5%は未達だが、あろさん軸「環境把握（方向と持続）」のD1評価で方向90.5%（流れ有り日99.7%）/流れ有無86.9%/転換ズレ中央値0日 → 採用（`data/dxy/DXY_SYNTH_VALIDATION_v1.md`）
   - クセ: 合成はspreadがやや平ら（特にドル安側）。揺らぎ死に帯PF0.62/0.77は合成で非再現＝根拠として持ち越さない（SPEC冒頭に注記）
   - 11/21 06:10 d1_env.json に dxy 2026-11-20（USD_DN 揺らぎ −3.0）反映＝⚠解除
5. DXY札の目的をメモリ化: 分析でなく環境把握（DXY上昇→GOLD下落の認知・一時的か長期化か）

## 👀 様子見
- 週明け月曜: DXY_SYNTH の毎時差分更新ログ（[Synth] diff update / H1 check READY）と dxy_env の当日行が動くか
- 「長期化」表示を作るなら窓方式（直近5営業日中、同方向の流れ有り≥3日・一致87.1%）が有望（未着手）

---

# 次セッションへの引き継ぎ（2026-07-21更新 — 3日凍結の復旧＋毎時システム監査＋軽量化A/C/B′/D実装完了）

## ✅ 7/21の収穫（Macセッション・おぱ）

### 1. 3日凍結の復旧（D1ウィジェット含む全動脈）
- 原因: `.git/refs/heads/main 2` 等の**複製ref**で `git fetch` が `fatal: bad object` 即死 → hourly_sync 88回連続失敗（7/18 08:10頃〜7/21朝）。VPS側は完全に健在（毎時pushは届き続けてた）。
- 復旧: 複製rm → rebase合流（VPS分24コミット）→ run_daily_calendar → publish済み。d1_env.json は 7/21 BEAR ADX34.6 で稼働再開。

### 2. 徹底監査（あろさん発注「パイプラインとEAを洗って」）
- 正書: **`data/vps/毎時システム監査_2026-07-21.md`**（故障モードFM-1〜7）
- 法医学的結論: 「 2」複製の生成源は**iCloud自動同期ではない**（DesktopはiCloud同期外）。Finder系の日付保存コピーで、**2回とも（7/15・7/18）あろさんの手作業ウィンドウと同時刻**。発生源は止められない→無害化ガードが正解。
- 重さの本丸: ②が毎時VPSから届く→週次パイプラインが**毎時フル再実行**（weekly updateコミット1日22回）だった。
- 衝突実測: push/pull失敗は443回中12回・全て自己回復。あろさんの「:15/:30/:45分散」案は実測でVPS:00/Mac:10オフセット既設+自己回復で足りてると回答→**「分散」でなく「push集約」で採用**。
- EA3系統・VPS push scriptは健全（7/5事故の学びが効いてる）。

### 3. 軽量化 A→C→B′→D 実装・デプロイ完了（`3617c5c`・あろさんGO済み）
- **A 自己修復**: hourly_sync Step0で「* 2」複製+1h超ロック残骸を毎時掃除／fetch3連続失敗でMac通知（以降24回毎=日1回）／ログ日付化。**実弾テスト済み**（ダミー複製→🧹除去確認・通知デモ発火済み）。
- **C タイムアウト**: run_daily_calendar/run_pipeline呼び出しに600s上限（run_to bash -c包み）／生pushへ `GIT_TERMINAL_PROMPT=0` + lowSpeed検知（VPS思想に統一）。
- **B′ push集約**: `run_pipeline.sh --no-push` 新設 → hourly_syncが**毎時1コミット1push**（鮮度は毎時のまま・Mac発コミット40+/日→24/日）。手動実行は従来動作。
- **D 一本化**: publish対象の正本= `data/vps/publish_list.txt`（hourly_sync/run_daily_calendar共読・7/14置き去り事故の恒久対応）。**公開物を足す時はこのファイルに1行足すだけ**。
- E2Eテスト合格: daily+weekly再生成→4ファイル1コミット集約publish（`895ed2a`）。

## 👀 様子見ポイント（あろさん指示「やってみて様子見よう」）
- hourly_sync.log（日付付きになった）で: 🧹自己修復の発火頻度／「N回連続」表示／weekly updateコミットが消えてauto-publish 1本/時になってるか
- Mac通知が来たら = fetch3連続失敗 = 何か新しい詰まり。`find .git -name "* 2*"` から診断
- 毎時ジョブは launchd :10 のまま（plist変更なし）

## ⚠️ 生きpending（継続分）
1. **W28ヒートマップ欠落**（D1手描き線→D1スクリプト再実行→run_pipeline待ち・Mac側）。H4_XAU系も7/6のまま。
2. **update_mani --watch の baseline穴**（CSV先着だとprepareスキップ・ブン案件・監査とは別件）
3. 8月集中メンテ項目: 口開閉マップOOS（カイ）/ PatD SELL構造分析 / KC引きつけOOS / D1環境札閾値 / DXY札実戦評価
4. signalsタブ7月化（承認済未実装）/ 過去口座CSV 2本の追跡入り検討
5. 作業ツリーの複製2ファイル（`scripts/generate_daily_calendar_v3 2.py`・`data/scriptable/d1_env_widget 2.js`）— 中身照合して不要なら削除（⚠️ d1_env_widget 2.js は7/15 widget貼替時の産物で新版の可能性・削除前に要diff）

## 🚀 おぱ起動作法（踏襲）
- 着手前後 `git pull --rebase --autostash origin main`。UUチェックも入口で。
- 朝イチは d1_env.json + daily_aggregate 末尾でD1環境札ブリーフィング。
- CSV読みはUTF-16フォールバック。曜日はカレンダーで裏取り。
- mq5実装=コー / VPS配置=ブン / BT=カイ / 振り返り=マニ。`signals/`正本。EA再コンパイルはMetaEditor F7。RDPは「切断」。

---
*今回の芯＝「対策を足すほど詰まる」構造を「冪等・自己修復・異常可視化」へ転換。鮮度は毎時のまま、無音停止だけが消える設計。次: 数日の様子見→問題なければ監査doc残項目は8月メンテと合流。*
