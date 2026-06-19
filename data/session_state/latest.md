# 次セッションへの引き継ぎ（2026-06-19 日次動脈フェーズ3完了：フル稼働 🎊）

## 🚀 おぱ起動作法（VPS↔Mac 連携・毎回これを最初に）
1. **まず `git pull --rebase origin main`** — VPSとMacは同じmainを書き合うパラレル運用。起動直後にpullしないと状況が古い（VPSが自動pushした `mt5_data/daily/` も latest.md 自体も最新化されない）。dirtyなら `git stash → pull --rebase → stash pop`。
2. この latest.md の「**今ここ**」「**次の起点**」で現状把握。詳細は設計書 `data/vps/日次動脈_DESIGN_v1.md`。
3. **push前も必ず `git pull --rebase`**。RDPは「切断」で抜ける（ログオフ厳禁）。

## 🎯 今ここ — 日次動脈 フェーズ1〜3 完了 ✅ **フル稼働**
フェーズ1(Mac無停止移行 `d4be4ce`)→2(VPS動脈ON `27bc3c6`)→3(Mac通し検証・公開 `f2b6276`)まで一気通貫。**VPSが焼いた日次データプール(daily/)→Macがpull→成績合流→docsカレンダー公開、の1サイクルが実際に回った。**

## ✅ フェーズ3完了（Mac・本日 / コミット f2b6276）
- VPS daily/(**391件**＝VPSのEAが389→391に増やした最新)を git pull受信
- `run_daily_calendar.sh --no-sync` で生成（**VPS正本を上書きせず使用**）→ カレンダー3枚 全PASS → docs公開
- ★**動脈データ増加でジェネレータの固定値assert(389 / 265・124 / 30・26)が停止**した
  → `generate_signals_calendar.py` / `generate_daily_calendar_v3.py` のセルフチェックを
     **動的整合性(CSV件数追従)に置換**。本質検証(描画漏れ0=emitted==n_total / 重複0 / 集計整合=pass+supp==total)は完全維持

## 🩸 動脈フル稼働（完成形）
```
VPS MT5 EA →(毎時) →[schtasks AM8:10/PM23:10] vps_data_pool_push.sh
  → mt5_data/daily/ → git push          ★VPS全自動
       │ git
       ▼
Mac git pull → run_daily_calendar.sh(--no-sync) → 成績合流 → docs公開   ★Mac起動時
       │ git push → GitHub Pages
       ▼
   iPhone/iPad で日次カレンダー
```

## ⚠️ 次にやるべき恒久対応（フェーズ3で顕在化）
1. **★★ `run_daily_calendar.sh` Step1 のVPS正本問題**：現状Step1は「Mac MT5→daily/コピー」＝**VPS正本(最新391件)を古いMac版で上書きする恐れ**。今回は `--no-sync` で回避した。
   恒久対応＝Step1から日次③のMac MT5コピーを削除し「daily/はgit pull受信前提」に（設計書§8本来の指示「git pull受信ベースに」／VPSおぱ原則「daily/はVPS正本・Macは上書きしない」の実装）。
   → これを直せば**素の `./run_daily_calendar.sh` が安全に回る**（毎回 --no-sync を付け忘れる事故を防ぐ）。
2. **②(ADX_Weekly/H4PhaseAuto)のM放置** → `./run_pipeline.sh` で解消（設計§6・週次更新時）。

## 📋 据え置き
- **系統A設計ズレ**：`mt5_data/{trade_input,trades_enriched}.csv` tracked・個人情報シロ。将来 data/trades/寄せ or §1修正（緊急でない）
- `sync_mt5_data.sh` のMac既存M（中身要確認・フェーズと無関係）
- `_EA` suffix掃除 / 系統A(Mac専管) / ②のVPS化(将来) / Win2(3.5GB)判断
- VPS再起動時：schtasks「ログオン中のみ実行」＝RDPログオンまで発火しない（自動ログオン未設定の場合）

## 🔧 別荘 運用フロー（継続）
- push前は必ず `git pull --rebase` / RDPは「切断」で抜ける（ログオフ厳禁）
- コー実装EAは MetaEditor **F7再コンパイル必須**（.ex5コマンドラインはロード不可＝556）
- `signals/`が正本 → MT5 `Experts\ARO\`(EA)/`Scripts\ARO\`(Script) へコピーしてF7

---
*次の起点＝`run_daily_calendar.sh` Step1のVPS正本恒久対応（Mac MT5コピー削除→git pull受信前提化）。日次動脈はフェーズ3まで完了・フル稼働中。設計書 `data/vps/日次動脈_DESIGN_v1.md`。*
