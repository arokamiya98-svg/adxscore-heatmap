# 次セッションへの引き継ぎ（2026-07-02 — ATR Ratio札の訂正確定＋ratio_widget H1/H4新設＋配色統一／★実機テスト待ち）

## 🚀 おぱ起動作法（踏襲）
- **VPS/動脈・EA化を触るセッションだけ** 着手前 `git pull --rebase origin main`（dirtyは`--autostash`）。今日は触ってない（Scriptable＋BT分析のみ）。
- mq5実装=**コー** / VPS配置=**ブン**。push前 `git pull --rebase`。RDPは「切断」で抜ける。
- ⚠️ **latest.md は git追跡**。更新したら latest.md だけでも commit して確定（`pull --rebase`で喪失防止）。← 今回commit済。

## 🧰 Bash/Read劣化（踏襲・必読）
- **Bash10分ハング＝環境の本物** / **ENOSPC誤報・文字化け・malformed・Read捏造・出力途中切れ＝モデル劣化**。[[claude-temp-burst-enospc]]。新セッションで立て直す。
- pandas無し＝標準ライブラリ（csv/codecs）。UTF-16フォールバック `["utf-16","utf-8-sig","utf-8"]`。
- 外向き操作は実測（rev-parse/cat-file/curl）、生成はパイプ無し直実行＋Readで現物（成功表示を鵜呑みにしない）。

## ✅ 今日の決着①（本命）— ATR Ratio 2モードの札を「実データで」確定
あろさんの直感「売り0.7／買い1.2」は**逆**だった。生データ(h4adx46, 947件)実測で確定：
- **買い＝低Ratio 0.7-1.0（押し目/圧縮解放）**。買い最高PF＝0.85-1.00 PF1.52（dedup 0.70-0.85 PF2.03）。1.0-1.2は買いの最ソフト(PF1.26)。
- **売り＝Ratio 1.0-1.2 × DN（拡張の戻り）**。売り0.85-1.00は**PF0.58の死亡帯**。
- 「1.2最高PF」の記憶違いの正体＝**主力(最頻ビン1.0-1.2・買い中央値1.07・1.2はP75)** と **最高PF(0.7)** の混同。1.2はアクション最多≠エッジ最濃。
- **"収束"の二義性**が混乱の根：ATR収束(Ratio↓0.7)＝買いボトムアウト ／ 中心線回帰(拡張1.2→EMA32)＝売り戻り叩き。
- あろさんフレーム「収束で逆張り／拡張で順張り」＝正しい。ただし**逆張り席は買い専用**（凪の逆張り売りはPF0.58の罠）。
- 既存memory [[atr-ratio-edge-keltner-design]] は「買い0.70-1.00／売り1.00-1.20×DN」で**正しい向き**＝間違い版は保存されてない。

## ✅ 今日の決着②— ratio_widget H1/H4 新設＋配色統一（★実機テスト待ち）
- 新規: `data/scriptable/ratio_widget.js`(H1) / `ratio_widget_h4.js`(H4) / `SPEC_ratio_widget_v1.md`。既存 `atr_widget.js` は無変更。
- **ATR Ratio基準線**（平均=中央値1.0 / 0.7収束 / 1.2拡張）を$で表示。**方向ラベルなし**（方向は局面で変わる変数＝フォワード判断。あろさん「ATRは値幅、方向じゃない」原則）。
- 心臓部＝**BT整合の上側中央値**（H1=960本 / H4=240本、gen2 `CalcMedian`移植・コー単体検算15/15 PASS）。カイBTの0.7/1.2ゾーンと同じ物差し。
- 配色統一（カレンダーv0.9）: **拡張=琥珀#ebaf37 / 収束=紫#966ecd / 中央値=灰#888**（方向色でなく値幅局面色。定数名も CONTRACT/EXPAND）。
- **H4実測: 33＝Ratio0.72（収束下限ドンピシャ）**。H4中央値≈45.8（局面で30〜56に振れる）＝固定値の意味がズレる＝**動的表示の要**。あろさんは感覚でH1(14=0.737)もH4(33=0.72)も収束下限を選んでた。

## 🔭 ★次アクション＝ratio_widget 実機テスト（あろさんの手番）
- `ratio_widget.js` / `ratio_widget_h4.js` を iPad Scriptable にコピー→**実キー**(atr_widgetと同じ)→Run→H1/H4並べる。
- 確認3つ: ①H4が `outputsize=400`で240本中央値取れるか(`ratio_widget_h4_cache.json`の`bars_used`) ②3値がチャート感覚と合うか ③**平均の灰#888が時刻の灰と近く沈まないか**(沈めば#aaa/白へ)。
- しっくりこなければコーに戻す（**agentId: a0f374d459f70473f**＝色/H4版, a605150a9426e66be＝初回実装。SendMessageで継続可）。
- **実機OK後**: scriptable 3ファイル＋KCEntry関連(下記)をまとめて commit。

## 🌱 KC entry / Ratio の次の種（急がない）
- 前段のKC entry BT結論: 買い=成行最良／売り=PatC(拡張)×L1中心線引きつけだけ効く(N=54中信頼・要OOS)。買い引きつけは「指値の逆選択」で負け。
- 次候補: **SELL×PatC×L1中心線を単一ルールで追検証**（DN期売り収集＋OOS）。買いはRR2.5-3.0(let it run)、売りはRRで救えない=入口勝負。
- 本籍: `data/bt/PATTERN_REGIME_MAP_v2_KCEntry.md` / memory [[kc-entry-bt-findings]]。

## ⚠️ 前回(7/1)からの生きpending
1. **★7/3〜4頃 マニv3再確認**: 7/1のMAE/MFEバーが48h完了で埋まるか / 7/2・7/3バー日々入るか / 7月ブロックが7/6(月)来て現在週で伸びるか / 未来日`.future`淡色 / signal_fires 7月発火拾うか。コマンド `curl -s https://arokamiya98-svg.github.io/adxscore-heatmap/daily_calendar_v3.html | grep -oE "2026-07-[0-9]{2}" | sort -u`。
2. **signalsタブ7月化**（承認済・未実装）: `generate_signals_calendar.py` L~226 `date_range_end=all_fire_dates[-1]`→`max(..., date.today())`。**未来週打ち切り＋future淡色もセット**（同型の穴・要確認）。パイプ無し実行→検証→該当2ファイルのみcommit。
3. **ケルトナーF7**（あろさんRDP）: MetaEditor `Indicators/ARO/ATR_Ratio_Keltner_v1.mq5`→F7(0/0)。H1 XAU・先に960本履歴。表示本数は Inputs `DrawBars`。
4. **(C) D1週次サンプリングEA化**（本命）: 手動WAVELOGをVPS毎時肩代わり。`FractalWaveLog_D1_weekly.csv`は`.gitignore`→push経路設計要。memory [[vps-daily-automation-ea-design]]。
5. 掃除: `run_daily_calendar.sh`の`|tail`エラー隠蔽（ブン・pipefail検討）／`archive*.md`・`FX*`未commit／配色v0.9横展開。

## 👥 チーム / 別荘作法
コー=mq5/HTML ／ カイ=BT ／ マニ=振り返り ／ ブン=VPS/動脈 ／ おぱ=番人+マネージャー。push前 `git pull --rebase` / RDP切断 / コー実装F7必須 / `signals/`正本。

---
*直近＝ratio_widget H1/H4 実機テスト待ち（あろさんの手番）。OKでcommit。並行して7/3〜4マニv3再確認。今日の芯＝ATR Ratio札を実データで確定（買い0.7押し目／売り1.2×DN拡張、"収束"の二義性）。*
