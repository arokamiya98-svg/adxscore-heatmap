# 次セッションへの引き継ぎ（2026-06-19 日次動脈フェーズ2完了：VPS動脈ON・自動化稼働）

## 🎯 今ここ — 日次動脈 フェーズ1＋2 完了 ✅
Mac無停止移行（フェーズ1）→ VPS動脈ON＋schtasks自動化（フェーズ2）まで一気通貫で完了。**VPSが日次データプールを自動pushする動脈が稼働開始**。残るは**フェーズ3（Mac側：git pull→成績合流→docs公開）のみ**＝次回Mac起動時に1サイクル回せば動脈フル稼働。

## ✅ フェーズ1完了（Mac・コミット d4be4ce）
- ③日次3本を `mt5_data/daily/` へ git mv／①FractalWaveLog を .gitignore+rm --cached
- generate_*.py 3本・run_daily_calendar.sh のパスを daily/ へ／run_pipeline.sh Step5に②add
- 検証 run_daily_calendar.sh → カレンダー3枚 全PASS（Step2b起動条件の移行漏れを検証で捕捉→修正）

## ✅ フェーズ2完了（VPS・本日）
1. **初回本実行 push 成功**（commit `5fd8a44` / daily 3本：signal_fires 392・daily_aggregate 86・daily_mfe_mae 85行）
2. **`.bat` ラッパー新設**（`scripts/vps_data_pool_push.bat`）＝schtasks の二重引用符エスケープ回避
3. **schtasks 2タスク登録**：`ADXSCORE_DataPool_AM`(08:10)/`_PM`(23:10)・JST・Status Ready・「ログオン中のみ実行」
4. **`schtasks /Run` 実機テスト合格**：bat→bash→スクリプト全経路通過・**Last Result 0**・「no change skip」も正常
- スクリプトに `DRY_RUN=1`（本実行前の安全確認）／`vps_pool.log` は .gitignore 済

## 🩸 動脈の現状
```
VPS MT5 EA →(毎時) MT5Files →[schtasks AM/PM] vps_data_pool_push.sh
  → mt5_data/daily/ → git push   ★ここまで自動稼働中
       │ git
       ▼
Mac git pull → 成績合流(trade_input) → 日次カレンダー → docs公開  ★フェーズ3=次回Mac起動時
```

## ▶ 次の起点 = フェーズ3（Mac・通し検証）
次回Mac起動時に1回：
1. `git pull`（VPSがpushした daily/ 最新を受信）
2. `run_daily_calendar.sh`（成績オーバーレイ込みで日次カレンダー生成→docs公開→push）
3. iPhone/iPadで反映確認 → **動脈フル稼働**
- ②(ADX_Weekly/H4PhaseAuto)のM放置は、この時 `run_pipeline.sh` で自動解消（設計§6）

## 📋 据え置き
- **系統A 設計ズレ**：`mt5_data/{trade_input,trades_enriched}.csv` が tracked。個人情報チェック＝**シロ**（口座/氏名/メール/入金 ヒットゼロ・trade_id連番＋時刻＋価格＋ATR/MFEのみ＝公開OK）。ただし設計§1「data/trades にしか無い」記述と実態ズレ→将来 data/trades/ 寄せ or §1修正を検討（緊急でない）
- **VPS再起動時の注意**：schtasksは「ログオン中のみ実行」＝再起動後はRDPログオンするまで発火しない（自動ログオン未設定の場合）。長期完全無人なら自動ログオン or「関わらず実行」化を検討
- `_EA` suffixファイル掃除（無印とdiff0の回帰名残・VPS MT5 Files）
- 系統A（トレード後付け・Mac専管）／②のVPS化（将来の大トラック）／Win2(3.5GB)判断
- `sync_mt5_data.sh` のMac既存M（中身要確認・フェーズと無関係）

## 🔧 別荘 運用フロー（継続）
- 別荘からpush前は必ず `git pull --rebase`
- RDPは「切断」で抜ける（ログオフ厳禁）→ schtasksは「ログオン中のみ実行」なのでセッション維持で発火する
- コー実装EAは MetaEditor **F7再コンパイル必須**（.ex5コマンドラインはロード不可＝556）
- `signals/`が正本 → MT5 `Experts\ARO\`(EA)/`Scripts\ARO\`(Script) へコピーしてF7

---
*次の起点＝フェーズ3（Mac：git pull→run_daily_calendar.sh→docs公開で動脈フル稼働）。VPS側はフェーズ2まで完了・schtasks AM8:10/PM23:10 自動稼働中。設計書 data/vps/日次動脈_DESIGN_v1.md。*
