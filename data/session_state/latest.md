# 次セッションへの引き継ぎ（2026-06-19 日次動脈 完全クローズ：フェーズ3＋Step1恒久対応）

## 🚀 おぱ起動作法（VPS↔Mac 連携・毎回これを最初に）
1. **まず `git pull --rebase origin main`**（dirtyなら `git stash → pull --rebase → stash pop`）。VPSとMacは同じmainを書き合うパラレル運用。
2. この latest.md の「**今ここ**」「**次の起点**」で把握。詳細は設計書 `data/vps/日次動脈_DESIGN_v1.md`。
3. **push前も必ず `git pull --rebase`**。RDPは「切断」で抜ける（ログオフ厳禁）。

## 🎯 今ここ — 日次動脈 完全クローズ ✅✅（フル稼働＋恒久対応済）
フェーズ1(Mac無停止移行)→2(VPS動脈ON)→3(通し検証・公開)→**Step1恒久対応**まで完了。
**素の `./run_daily_calendar.sh` が安全に回る**状態（daily/はVPS正本・Macは上書きしない）。動脈は無人で回り続ける。iPhone/iPad で日次カレンダー公開も目視確認済み。

## ✅ 本日の到達（コミット）
- `d4be4ce` フェーズ1（③daily/分離・①gitignore・無停止移行）
- `f2b6276` フェーズ3（セルフチェック動的化・VPS391件でカレンダー公開）
- `dafbbf2` Step1恒久対応（Mac MT5→daily/コピー削除→**受信確認のみ**・欠損で`git pull`促し停止）
  - 検証: 素実行(--no-sync無し)で daily/上書きせず3枚生成 / 欠損時 exit1 警告停止 両方OK

## 🩸 動脈フル稼働（完成形）
```
VPS MT5 EA →(毎時) →[schtasks AM8:10/PM23:10] vps_data_pool_push.sh
  → mt5_data/daily/ → git push          ★VPS全自動
       │ git
       ▼
Mac git pull → ./run_daily_calendar.sh → 成績合流 → docs公開   ★素で安全(--no-sync不要)
       │ git push → GitHub Pages
       ▼
   iPhone/iPad で日次カレンダー
```

<<<<<<< Updated upstream
## 📌 運用メモ（今日の知見）
- **「追跡欠損」表示＝最新1-2日が48h未経過の追跡途中**（signal_fires 391件中1件=6-18=33バー / daily_mfe_mae 6-17=46・6-18=23、6-16以前は全48）。**VPS毎時更新で翌日埋まる＝正常**。異常ではない（動脈が最新を運んでる証拠）。
- **docs/*.html は生成時刻が毎回変わる→実行毎にM化**（実データ差分なし=各1行）。auto-publish(Step2.6)で正規commitされる。--no-publish検証後は `git checkout docs/` で捨ててOK。
- **素の `./run_daily_calendar.sh` はもう `--no-sync` 不要**（Step1が受信確認のみ＝安全）。

## ▶ 次の起点 候補
1. **CLAUDE.md v14**（VPSおぱ）：日次動脈フル稼働・`mt5_data/daily/`構造・系統B/C EA を反映。Step1恒久対応も完了＝まとめる好機。
2. **②(ADX_Weekly/H4PhaseAuto)のM放置** → `./run_pipeline.sh` で解消（週次更新時・設計§6）。
3. **`auto_sync_daily.sh` の日次TARGETS監視＝Step1と同根の地雷**（Mac MT5日次前提）。将来「git pull検知」へ寄せると完全一貫（VPSおぱ申し送り・別タイミングでOK）。
=======
## ⚠️ 次にやるべき恒久対応（フェーズ3で顕在化）
1. **★★ `run_daily_calendar.sh` Step1 のVPS正本問題**：現状Step1は「Mac MT5→daily/コピー」＝**VPS正本(最新391件)を古いMac版で上書きする恐れ**。今回は `--no-sync` で回避した。
   恒久対応＝Step1から日次③のMac MT5コピーを削除し「daily/はgit pull受信前提」に（設計書§8本来の指示「git pull受信ベースに」／VPSおぱ原則「daily/はVPS正本・Macは上書きしない」の実装）。
   → これを直せば**素の `./run_daily_calendar.sh` が安全に回る**（毎回 --no-sync を付け忘れる事故を防ぐ）。
   → **VPSおぱ方針回答（2026-06-19）＝GO・合意済**：Step1から日次③コピー削除＋「daily/ pull済みか存在チェック（無ければ警告で停止）」化。前提＝Macは日次EA回さない(VPS専管)・Mac MT5は週次専用。実装はMac、直後に「素の実行でdaily/を上書きしない」＆「古いdaily/で警告停止する」を検証。同根の auto_sync_daily.sh 日次監視は別タイミングで git pull検知化。
2. **②(ADX_Weekly/H4PhaseAuto)のM放置** → `./run_pipeline.sh` で解消（設計§6・週次更新時）。
>>>>>>> Stashed changes

## 📋 据え置き
- 系統A設計ズレ（`mt5_data/{trade_input,trades_enriched}.csv` tracked・個人情報シロ・将来 data/trades/寄せ or §1修正）
- `sync_mt5_data.sh` のMac既存M（中身要確認・フェーズと無関係）
- `_EA` suffix掃除 / 系統A(Mac専管) / ②のVPS化(将来) / Win2(3.5GB)判断
- VPS再起動時：schtasks「ログオン中のみ実行」＝RDPログオンまで発火しない

## 🔧 別荘 運用フロー（継続）
- push前は必ず `git pull --rebase` / RDPは「切断」で抜ける / コー実装EAは MetaEditor **F7再コンパイル必須**（.ex5は556） / `signals/`が正本

---
*日次動脈は**完全クローズ**（フル稼働＋恒久対応済・素の run_daily_calendar.sh が安全）。次＝CLAUDE.md v14反映 or auto_sync_daily.sh の同根地雷対応。設計書 `data/vps/日次動脈_DESIGN_v1.md`。*
