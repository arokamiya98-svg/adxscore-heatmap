#!/usr/bin/env python3
"""
generate_daily_calendar_v3.py
─────────────────────────────
日次認識カレンダー v3 移植版（v2ベース + シグナル統合 / Step 2）

指示書: data/mani_room/マニ_指示書_日次認識カレンダーv3移植版_v0.2.md (Step 1)
        data/mani_room/マニ_指示書_v3移植版Step2_v0.3.md (Step 2)

Step 2（2026-06-12 あろさん実見フィードバック反映）:
  B1: ドロワー opacity バグ修正 — fireCard() の閉じ </div> 欠落で後続カード
      （実トレードカード含む）が抑制カード内に入れ子になり opacity 0.55 が
      全部に継承されていた。閉じタグ追加で個々の抑制カードのみに限定。
  B2: 9本フィルター デフォルトON — デフォルト = pass_all=TRUE のみ表示
      （ドット・ドロワー・ヘッダー集計とも）。「全発火表示」トグルで
      抑制 124 件を薄表示で追加。
  B3: 期間のトレードログ基準化 — デフォルト表示 = トレード記録開始月
      （2026-03）以降かつ直近6ヶ月上限。それ以前（2025-03〜2026-02、
      発火のみの期間）は <details> 折りたたみ「過去を表示 ▸」で展開。
      発火389全件は DOM に常に存在（展開で全件可視）。
  変更しないこと: トレード帯（++59k形式）現状維持確定 / 土曜→金曜セル併載維持 /
      その他 v2 由来の見た目・機能すべて。
方針  : v2 (generate_daily_calendar.py) を正として、Step 1 の3点だけを移植。
        それ以外の v2 の見た目・機能（色・数字・金額帯・円グラフ・テーブル・ソート）は一切変えない。

  A1: セル最下部にシグナルドット行を追加
      - データ: mt5_data/signal_fires.csv (UTF-8-sig, 389件)
      - 視覚言語は signals_calendar v2 と完全同一（PAT_COLORS 10色 / ▲▼ / pass_all=FALSE は薄表示）
  A2: セルクリック → 右固定ドロワー
      - シグナルカード + 実トレードカード（MFE/MAE 12/24/36/48h 同一フォーマット、
        server時間併記、新規理由折りたたみ）— signals_calendar v2 の実装を流用
      - v2 既存のクリック挙動（円グラフ連動・テーブルソート等は別タブ）とは衝突しない
  A3: セル右上の「SC28」等スコア数値テキスト削除（ホバー title 内のスコア値は残す）

設計判断（マニ裁量、実装レポート参照）:
  (1) JST土曜発火 31件（= サーバー金曜深夜。全31件のサーバー日付が金曜であることを確認済み）
      は金曜セルに併載 → v2 の月〜金5列レイアウトを維持しつつ 389 全件描画を満たす。
      ドット/カードには「土」マークで区別。
  (2) カレンダー期間は発火CSV全期間に拡張（2025-03〜）— 「発火389全件描画」の完了条件のため。
      月単位の見た目・セル構造は v2 と同一（トレードのない月は件数0表示）。
  (3) ドロワーJSは V3_ 接頭辞 + IIFE で v2 既存 JS（TRADES 等）と名前衝突を回避。

────────── 以下、v2 (generate_daily_calendar.py) の履歴コメント（保持） ──────────

日次研究カレンダー v1.1
- 階層化原則: H4(主役 46%) / H1(補助 16%) / D1(セル外帯) / シグナル(8%) / 結果(14%)
- 視覚化: 色相=DI方向 / 段階明度=ADX強度(閾値ベース階段) / 凪=グレー
- v0.4 変更点: 連続グラデ → 閾値ベース段階明度（H4=5段 / H1=4段）
- v0.5 変更点: トレード日の H4 中央主役を MAE/MFE 表示に置換
- v0.6 変更点: 結果背景=ポジション方向 / 文字色=損益
- v0.7 変更点:
  (1) ADX 25+ を派手にグロウ（box-shadow + saturation/lightness UP）
  (2) D1 帯の「凪」を「RANGE」にリネーム（ADX文脈の概念整理）
  (3) 建値(損益0)をさらに目立たなく
  (4) 非トレード日にも環境メモを薄く追加
- v0.8 変更点（あろさん指摘の概念整理）:
  (1) DI spread 数値表示を完全削除（色相で既に方向を表現済み、情報重複）
  (2) ADX 値表示 → H1×H4 合成スコア(0-100) に置換
  (3) D1 帯の色マッピングを概念的に正しく（色相=DI / 鮮やかさ=ATR Phase）
- v1.0 変更点（C1 daily_mfe_mae_48h.csv 統合）:
  (1) 非トレード日の中央クリーン化を撤回 → 仮想 MFE/MAE 復活
      ・データ源: mt5_data/daily_mfe_mae_48h.csv (JST 14:00 仮想エントリー 48h追跡)
      ・BUY/SELL 両方コンパクト並列 (案A) — 番人観点で優劣付けゼロ
      ・トレード日との見た目区別: フォントサイズ縮小+彩度低下で「補助情報」感
  (2) 「景色×結果の並列読み」完成 — 背景=環境 / 中央=結果(実 or 仮想)
  (3) 仮想エントリーは事実情報拡張のみ — 「機会損失」「取り逃がし」等の判断ラベル禁止
      [[research-purpose-and-rules]] 準拠
- v1.1 変更点（あろさん「もうちょいわかりやすく」フィードバック）:
  (1) 非トレード日も MFE/MAE バースタイルで表示（中央 tick から左右に伸びるバー）
      ・トレード日と同じバー構造、BUY と SELL の2本を縦に並列
      ・ボリューム感が一目で伝わる
  (2) 全体比正規化に統一
      ・固定 BAR_MAX=300 USD → CSV 全期間の p95 値を 100% 基準に変更
      ・トレード日のバーも全体比に統一（仮想と実の並列読みが正確に）
      ・全期間の中での相対ボリュームが視覚化される
  (3) 数値表示はバー上に小さく補助、バーが主役
- v1.2 変更点（C2 daily_aggregate.csv 統合、日次粒度本格化）:
  (1) 環境データソースを「週次 weekly_waves.json」→「日次 daily_aggregate.csv」優先に切替
      ・同週内同値問題を解消、日次粒度で景色変化
      ・CSV欠損日は weekly_waves.json でフォールバック
  (2) H4/H1 の 3軸 (max/close/mean) を役割で使い分け（ハイブリッド構成）
      ・背景濃淡 = mean (1日全体の温度感、近似的代表値)
      ・スコア計算 = max (「伸びた瞬間」哲学、ADX素地の事実情報)
      ・DI 方向   = close (確定情報、既存仕様維持)
      ※ 軸選択は事実情報の選択であり、判断ラベル化なし [[research-purpose-and-rules]]
  (3) 内部キー名は既存に合わせて改修コスト最小化
      ・h4_adx46 (旧週次値そのまま) → 背景用に mean を投入
      ・h1_avg_adx (週次の H1 平均) → 背景用に mean を投入
      ・スコア計算は別途 max を直接参照
- v1.3 変更点（あろさん画面確認後フィードバック）:
  (1) 非トレード日の BUY/SELL 2本バーを「値動きレンジバー」1本に統合
      ・BUY MFE = SELL MAE（上方向の伸び）/ BUY MAE = SELL MFE（下方向の伸び）→ 同じ情報の二重表示
      ・1本バー: 右=上方向の最大伸び / 左=下方向の最大伸び / 中央 tick=entry
      ・方向中立で「値動きの範囲」を表現、認知負荷削減
      ・トレード日のバーは方向確定なので現状維持（実利=MFE、実損=MAE）
  (2) トレード日に pattern + H1 ATR Ratio タグ追加
      ・場所: シグナル行を拡張（▲ + パターン名 + ATR比率）
      ・色フラット（パターン別色分けは BT 知見の UI 焼き付け NG）
      ・事実情報のみ、「PatA=いい / 高ATR=危険」等の評価ラベル化禁止
- v1.4 変更点（あろさんフィードバック 2026-06-10）:
  (1) パターンタグの参照先を「反省」列（意思決定の正本）に変更
      ・旧: enriched の h1_pattern（ATR Velocity 計算値: FLAT/EXPANDING 等）
      ・新: トレードログ FX_*.csv の「反省」列（PAT-A/B/C/D/ATR収束底/その他）
      ・「あろさんが入った時に何のシグナルを見ていたか」を反映
      ・構造化タグ（PAT-A 等）→ 通常表示 / 「その他」→ 控えめ表示 / 空欄 → 非表示
      ・ATR Ratio タグは数値情報なので enriched 維持

仕様: data/mani_room/マニ_ワイヤーフレーム提案_v0.3.md
指示: data/mani_room/マニ_指示書_日次研究カレンダー_v0.1.md

入力:
    data/mani_room/raw/imports/FX_*.csv (最新)
    mt5_data/daily_aggregate.csv (日次 D1/H4/H1 集計、優先)
    data/weekly_waves.json (週次、フォールバック)
出力:
    data/trades/processed/trades_calendar.html
"""
import csv
import json
import math
from collections import defaultdict
from datetime import datetime, timedelta, date
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TRADES_DIR = ROOT / "data" / "mani_room" / "raw" / "imports"
ENRICHED = ROOT / "data" / "mani_room" / "enriched" / "trades_enriched_full.csv"
OUT = ROOT / "data" / "trades" / "processed"
WAVES = ROOT / "data" / "weekly_waves.json"
# v1.0: 仮想 48h MFE/MAE (JST 14:00 仮想エントリー、C1出力)
DAILY_MFE_MAE = ROOT / "mt5_data" / "daily" / "daily_mfe_mae_48h.csv"
# v1.2: 日次 D1/H4/H1 集計（C2出力、最優先データソース）
DAILY_AGG = ROOT / "mt5_data" / "daily" / "daily_aggregate.csv"
# v3-A1: シグナル発火ログ（Signal_Fire_Logger v1 出力、UTF-8-sig）
FIRES_CSV = ROOT / "mt5_data" / "daily" / "signal_fires.csv"
OUT.mkdir(parents=True, exist_ok=True)

# ============================================================
# ユーティリティ（先に定義）
# ============================================================
def _f(x):
    """安全 float 変換（空欄は None）"""
    if x is None or x == "":
        return None
    try:
        return float(x)
    except (ValueError, TypeError):
        return None

# ============================================================
# 入力
# ============================================================
src = sorted(TRADES_DIR.glob("FX_*.csv"))[-1]
with open(src, encoding="utf-8") as f:
    trade_rows = list(csv.DictReader(f))
with open(WAVES, encoding="utf-8") as f:
    weeks = json.load(f)

# enriched (48h固定 MAE/MFE 取得用) — trade_id ベースでマップ
# v0.2 bugfix: utf-8-sig で BOM を取り除く。utf-8 のままだと先頭列キー
# が "﻿約定日" になり、後段の er["約定日"] 等が常に KeyError →
# enriched 全件マッチ失敗 → drilldown-table が全行「—」表示になる。
enriched_map = {}
if ENRICHED.exists():
    with open(ENRICHED, encoding="utf-8-sig") as f:
        for r in csv.DictReader(f):
            tid = r.get("trade_id", "").strip()
            if tid:
                enriched_map[tid] = r

# v1.0: 仮想 48h MFE/MAE (JST 14:00) を date でマップ
# C1 (signals/XAUUSD_Daily_MFE_MAE_v1.mq5) 出力、UTF-8 BOM
daily_mfe_mae_map = {}
if DAILY_MFE_MAE.exists():
    with open(DAILY_MFE_MAE, encoding="utf-8-sig") as f:
        for r in csv.DictReader(f):
            try:
                d = datetime.strptime(r["date"], "%Y-%m-%d").date()
            except Exception:
                continue
            daily_mfe_mae_map[d] = {
                "buy_mfe": _f(r.get("buy_mfe_usd")),
                "buy_mae": _f(r.get("buy_mae_usd")),
                "sell_mfe": _f(r.get("sell_mfe_usd")),
                "sell_mae": _f(r.get("sell_mae_usd")),
                "entry_price": _f(r.get("virtual_entry_price")),
                "bars_traced": _f(r.get("bars_traced")),
            }

# ============================================================
# v1.1: 全期間 MFE/MAE 正規化基準（p95）
# ============================================================
# あろさんフィードバック: 「全体比表示で、その日の値動きのボリューム感が見れる」
# 設計:
#   - CSV 全期間の buy_mfe/buy_mae/sell_mfe/sell_mae 全値から p95 を算出
#   - p95 を 100% 基準にクリップ正規化（極端な外れ値で他が潰れないように）
#   - トレード日も非トレード日も同じ基準で並列読み可能
#   - 番人観点: 計算ロジックのみ、判断ラベルなし
def _calc_bar_norm_base():
    all_vals = []
    for v in daily_mfe_mae_map.values():
        for k in ("buy_mfe", "buy_mae", "sell_mfe", "sell_mae"):
            x = v.get(k)
            if x is not None and x > 0:
                all_vals.append(x)
    if not all_vals:
        return 300.0  # フォールバック（旧 BAR_MAX）
    all_vals.sort(reverse=True)
    p95_idx = max(0, int(len(all_vals) * 0.05))
    return all_vals[p95_idx]

BAR_NORM_BASE = _calc_bar_norm_base()
# 全期間統計（凡例に出す）
_all_vals_for_stats = []
for v in daily_mfe_mae_map.values():
    for k in ("buy_mfe", "buy_mae", "sell_mfe", "sell_mae"):
        x = v.get(k)
        if x is not None and x > 0:
            _all_vals_for_stats.append(x)
BAR_MAX_OBS = max(_all_vals_for_stats) if _all_vals_for_stats else 0.0

week_map = {w["week"]: w for w in weeks}

# ============================================================
# v1.2: 日次 daily_aggregate.csv 読み込み（C2出力）
# ============================================================
# 軸選択ロジック（マニ判断、案C ハイブリッド）:
#   - 背景濃淡（h4_adx46 / h1_avg_adx 既存キー）= mean（1日全体の温度感）
#   - スコア計算用 ADX = max（「伸びた瞬間」哲学、別途キー h1_adx_max / h4_adx_max）
#   - DI 方向 = close（確定情報、既存仕様維持）
#
# 既存キー名互換マッピング:
#   h4_adx46     ← h4_adx46_mean    （背景用）
#   h4_adx_max   ← h4_adx46_max     （スコア用、新規キー）
#   h1_avg_adx   ← h1_adx32_mean    （背景用）
#   h1_adx_max   ← h1_adx32_max     （スコア用、新規キー）
#   h4_di_spread ← h4_di_spread_close
#   h4_di_dir    ← h4_di_dir
#   d1_adx22     ← d1_adx22
#   d1_di_dir    ← d1_di_dir
#   d1_di_spread ← d1_di_spread
#
# 番人観点: 軸選択は事実情報の選択、優劣判定なし [[research-purpose-and-rules]]
def _parse_daily_agg_row(r):
    """daily_aggregate.csv の1行 → 既存互換 rec dict"""
    return {
        # D1
        "d1_adx22": _f(r.get("d1_adx22")),
        "d1_di_plus": _f(r.get("d1_di_plus")),
        "d1_di_minus": _f(r.get("d1_di_minus")),
        "d1_di_spread": _f(r.get("d1_di_spread")),
        "d1_di_dir": r.get("d1_di_dir", "").strip() or None,
        "d1_atr22": _f(r.get("d1_atr22")),
        "d1_atr42": _f(r.get("d1_atr42")),
        "d1_atr22_42_ratio": _f(r.get("d1_atr22_42_ratio")),
        # H4 既存互換キー（背景用に mean を投入）
        "h4_adx46": _f(r.get("h4_adx46_mean")),
        # H4 スコア用 max（新規キー）
        "h4_adx_max": _f(r.get("h4_adx46_max")),
        "h4_adx_close": _f(r.get("h4_adx46_close")),
        "h4_di_plus": _f(r.get("h4_di_plus_close")),
        "h4_di_minus": _f(r.get("h4_di_minus_close")),
        "h4_di_spread": _f(r.get("h4_di_spread_close")),
        "h4_di_dir": r.get("h4_di_dir", "").strip() or None,
        "h4_atr8": _f(r.get("h4_atr8_close")),
        "h4_atr46": _f(r.get("h4_atr46_close")),
        "h4_atr8_46_ratio": _f(r.get("h4_atr8_46_ratio_close")),
        # H1 既存互換キー（背景用に mean を投入）
        "h1_avg_adx": _f(r.get("h1_adx32_mean")),
        # H1 スコア用 max（新規キー）
        "h1_adx_max": _f(r.get("h1_adx32_max")),
        "h1_adx_close": _f(r.get("h1_adx32_close")),
        "h1_di_plus": _f(r.get("h1_di_plus_close")),
        "h1_di_minus": _f(r.get("h1_di_minus_close")),
        "h1_di_spread": _f(r.get("h1_di_spread_close")),
        "h1_di_dir": r.get("h1_di_dir", "").strip() or None,
        "h1_atr16": _f(r.get("h1_atr16_close")),
        "h1_atr32": _f(r.get("h1_atr32_close")),
        "h1_atr16_32_ratio": _f(r.get("h1_atr16_32_ratio_close")),
        "_source": "daily_agg",  # デバッグ/サニティ用
    }

daily_agg_map = {}
if DAILY_AGG.exists():
    # UTF-8 (BOM 有無両対応) で読み込み
    with open(DAILY_AGG, encoding="utf-8-sig") as f:
        for r in csv.DictReader(f):
            try:
                d = datetime.strptime(r["date"], "%Y-%m-%d").date()
            except Exception:
                continue
            daily_agg_map[d] = _parse_daily_agg_row(r)

def date_to_iso_week(d):
    iso = d.isocalendar()
    return f"{iso[0]}-W{iso[1]:02d}"

def get_rec(d):
    """日次データ優先 + 週次フォールバック（v1.2）

    1. daily_aggregate.csv にその日のデータがあれば日次優先で返却
       - ただし日次CSV にない項目（h4_phase_auto / d1_pattern / tier / fib_*）
         は同週の weekly_waves.json から補完
    2. 日次CSV にその日のデータが無ければ週次値で代用（旧挙動 fallback）
    """
    week_rec = week_map.get(date_to_iso_week(d))
    daily_rec = daily_agg_map.get(d)

    if daily_rec is None:
        # 日次データ無 → 週次のみ（fallback）
        return week_rec

    # 日次データあり → 週次から補完項目をマージ
    merged = dict(daily_rec)
    if week_rec:
        # 日次CSVに無い項目を週次から取る（環境メモ・構造ラベル系）
        for k in (
            "h4_phase_auto", "d1_pattern", "tier",
            "fib_zone", "fib_pos", "fib_level", "fib_bu_days", "fib_pd_days",
            "fib_days_to_end", "fib_anchor",
            "h4_pattern", "h4_atr_ratio", "h4_atr_class", "h4_atr_zone3",
            "h4_atr_cross", "h4_ma46_side", "h4_cross_dir", "h4_atr_diff",
            "d1_atr_ratio", "d1_atr_zone", "d1_atr_zone3", "d1_atr_trend",
            "atr_class", "phase_align",
            "adx_score", "h4_pct20", "h4_pct25", "h1_pct20",
        ):
            if k in week_rec and k not in merged:
                merged[k] = week_rec[k]
    return merged

# ============================================================
# トレード日次集計
# ============================================================
trade_by_date = defaultdict(list)
for r in trade_rows:
    try:
        d = datetime.strptime(r["約定日"][:10], "%Y/%m/%d").date()
    except Exception:
        continue
    # enriched マッチング: 約定日 + 新規レート + オーダーで疑似 ID 生成
    # （enriched 側に明示的な trade_id があるが、FX_*.csv 側に無いので
    #   約定日+方向+entry_price で照合する）
    entry_rate = _f(r["新規レート"]) or 0
    direction = "BUY" if r["オーダー"] == "買い" else "SELL"
    # enriched 探索（同日・同方向・entry_price 一致）
    enriched_row = None
    for er in enriched_map.values():
        try:
            er_d = datetime.strptime(er["約定日"][:10], "%Y/%m/%d").date()
        except Exception:
            continue
        if er_d != d:
            continue
        if er.get("direction", "").upper() != direction:
            continue
        ep = _f(er.get("entry_price"))
        if ep is not None and abs(ep - entry_rate) < 0.01:
            enriched_row = er
            break

    # H4 の 48h固定 MAE/MFE を取得（採用判断: H4=戦略翻訳層と整合）
    h4_mfe = h4_mae = None
    # v1.3: ATR Ratio タグ用に enriched から取得（数値情報、計算値で正当）
    h1_atr_ratio = None
    if enriched_row:
        h4_mfe = _f(enriched_row.get("h4_mfe_usd_48h"))
        h4_mae = _f(enriched_row.get("h4_mae_usd_48h"))
        h1_atr_ratio = _f(enriched_row.get("h1_atr_ratio"))

    # v1.4: パターンタグは「反省」列（あろさんの意思決定の正本）から直接取得
    #   - 計算値の h1_pattern (FLAT/EXPANDING 等) ではなく、入った時の判断タグを表示
    #   - 構造化タグ (PAT-A/B/C/D/ATR収束底) → そのまま
    #   - 「その他」 → 控えめ表示（あろさんが意識的に分類外として残してる）
    #   - 空欄 → タグなし
    decision_tag = (r.get("反省") or "").strip() or None

    trade_by_date[d].append({
        "pl": float(r["損益"]) if r["損益"] else 0,
        "order": r["オーダー"],
        "star": r["評価"],
        "lot": float(r["ロット"]) if r["ロット"] else 0,
        "pips": float(r["pips"]) if r["pips"] else 0,
        "entry_rate": entry_rate,
        "exit_rate": float(r["決済レート"]) if r["決済レート"] else 0,
        "h4_mfe_48h": h4_mfe,
        "h4_mae_48h": h4_mae,
        "decision_tag": decision_tag,
        "h1_atr_ratio": h1_atr_ratio,
    })

all_dates = sorted(trade_by_date.keys())

# ============================================================
# v3-A1: signal_fires.csv 読み込み
# 解釈ロジックは generate_signals_calendar.py v2 と完全同一
# （PATTERN_COLORS は v4 実機矢印色テーブル、変更禁止）
# ============================================================
PATTERN_COLORS = {
    "PatA": {"BUY": "#FFD700", "SELL": "#DAA520"},  # Gold / Goldenrod
    "PatB": {"BUY": "#00FFFF", "SELL": "#00BFFF"},  # Aqua / DeepSkyBlue
    "PatC": {"BUY": "#32CD32", "SELL": "#2E8B57"},  # LimeGreen / SeaGreen
    "PatD": {"BUY": "#FF00FF", "SELL": "#C71585"},  # Magenta / MediumVioletRed
    "PatE": {"BUY": "#FFA500", "SELL": "#FF8C00"},  # Orange / DarkOrange
}
PATTERNS = ["PatA", "PatB", "PatC", "PatD", "PatE"]
FILTER_COLS = [
    ("f1_none_sell", "F1 none_sell"),
    ("f2_patb_midh_sell", "F2 patb_midh_sell"),
    ("f3_patd_pd_buy", "F3 patd_pd_buy"),
    ("f4_patc_up_none_midh", "F4 patc_up_none_midh"),
    ("f5_patb_up_bu_midh", "F5 patb_up_bu_midh"),
    ("f6_patc_up_pd_midh", "F6 patc_up_pd_midh"),
    ("f7_tight_sell", "F7 tight_sell"),
    ("f8_patc_none_sell", "F8 patc_none_sell"),
    ("f9_pata_weakup_sell", "F9 pata_weakup_sell"),
]

# ⚠️ 必ず utf-8-sig（BOM事件再発防止: utf-8 だと先頭キーが "﻿fire_id" になり全マッチ失敗）
with open(FIRES_CSV, encoding="utf-8-sig") as f:
    _fire_raw = list(csv.DictReader(f))
assert "fire_id" in _fire_raw[0], f"BOM混入の疑い: 先頭キー={list(_fire_raw[0].keys())[0]!r}"

fires = []
for r in _fire_raw:
    fd = datetime.strptime(r["date"], "%Y-%m-%d").date()
    # 設計判断(1): JST土曜発火（=サーバー金曜深夜）は金曜セルに併載
    #   - v2 の月〜金5列レイアウトを維持したまま 389 全件描画を満たすため
    #   - 全31件のサーバー日付が金曜であることをデータで確認済み（チャート整合）
    if fd.weekday() == 5:
        cell_d = fd - timedelta(days=1)
        fold = True
    else:
        cell_d = fd
        fold = False
    hits = [label for col, label in FILTER_COLS if r.get(col) == "TRUE"]
    fires.append({
        "fid": r["fire_id"],
        "date": r["date"],
        "cell_date": str(cell_d),
        "_cell_d": cell_d,
        "fold": fold,
        "time_jst": r["time_jst"][11:16],          # "HH:MM"
        "time_server": r["time_server"][5:16],     # "MM-DD HH:MM"（日付跨ぎ明示）
        "pattern": r["pattern"],
        "direction": r["direction"],
        "entry_price": _f(r["entry_price"]),
        "pass_all": r["pass_all"] == "TRUE",
        "filter_hits": hits,
        # 環境（段階ラベル優先 + 生値は補助）
        "atr_zone": r["atr_zone"],
        "h1_atr_ratio": _f(r["h1_atr_ratio"]),
        "h1_adx_zone": r["h1_adx_zone"],
        "h1_adx32": _f(r["h1_adx32"]),
        "h1_pattern": r["h1_pattern"],
        "h4_adx_zone": r["h4_adx_zone"],
        "h4_adx46": _f(r["h4_adx46"]),
        "h4_cross_dir": r["h4_cross_dir"],
        "h4_cross_bars": r["h4_cross_bars"],
        "cross_dir": r["cross_dir"],               # D1 ATRクロス局面 BU/PD/NONE
        "d1_cross_bars": r["d1_cross_bars"],
        "d1_adx22": _f(r["d1_adx22"]),
        "d1_di_dir": r["d1_di_dir"],
        # MFE/MAE 推移（48h固定追跡）
        "mfe": [_f(r["mfe_12h"]), _f(r["mfe_24h"]), _f(r["mfe_36h"]), _f(r["mfe_48h"])],
        "mae": [_f(r["mae_12h"]), _f(r["mae_24h"]), _f(r["mae_36h"]), _f(r["mae_48h"])],
        "bars_traced": _f(r["bars_traced"]),
    })

fires.sort(key=lambda x: (x["date"], x["time_jst"], int(x["fid"])))
fires_by_cell = defaultdict(list)
for fr in fires:
    fires_by_cell[fr["_cell_d"]].append(fr)
n_fires_total = len(fires)
n_fires_pass = sum(1 for fr in fires if fr["pass_all"])
n_fires_supp = n_fires_total - n_fires_pass

# ============================================================
# v3-A2: ドロワー用 実トレードカードデータ
# generate_signals_calendar.py v2 と同一の解釈:
#   - pips: CSV はポイント値 → /100 で USD 価格幅（MFE/MAE と同スケール）
#   - タグ = 「反省」列（意思決定の正本） / ★ = 「評価」列
#   - 出さないもの: 損益額・ロット・累計系・考察・決済理由（研究ルール準拠）
# ============================================================
drill_trades = []
drill_trades_by_date = defaultdict(list)
for _er in enriched_map.values():
    ej = (_er.get("entry_jst") or "").strip()
    if not ej:
        continue
    try:
        _dd = datetime.strptime(ej[:10], "%Y-%m-%d").date()
    except ValueError:
        continue
    ex = (_er.get("exit_jst") or "").strip()
    if ex:
        # 同日決済は HH:MM、日跨ぎは MM-DD HH:MM（シグナルカードと同流儀）
        exit_disp = ex[11:16] if ex[:10] == ej[:10] else ex[5:16]
    else:
        exit_disp = "—"
    _pips_raw = _f(_er.get("pips"))
    drill_trades.append({
        "tid": _er.get("trade_id", "").strip(),
        "date": ej[:10],
        "_d": _dd,
        "entry_time": ej[11:16],
        "exit_disp": exit_disp,
        "direction": (_er.get("direction") or "").upper(),
        "pips": None if _pips_raw is None else _pips_raw / 100.0,  # USD価格幅
        "style": (_er.get("スタイル") or "").strip(),
        "star": (_er.get("評価") or "").strip(),
        "tag": (_er.get("反省") or "").strip(),
        "reason": (_er.get("新規理由") or "").strip(),
        "mfe": [_f(_er.get("h1_mfe_usd_12h")), _f(_er.get("h1_mfe_usd_24h")),
                _f(_er.get("h1_mfe_usd_36h")), _f(_er.get("h1_mfe_usd_48h"))],
        "mae": [_f(_er.get("h1_mae_usd_12h")), _f(_er.get("h1_mae_usd_24h")),
                _f(_er.get("h1_mae_usd_36h")), _f(_er.get("h1_mae_usd_48h"))],
        "bars_traced": _f(_er.get("h1_bars_traced_48h")),
    })
drill_trades.sort(key=lambda t: (t["date"], t["entry_time"]))
for _t in drill_trades:
    drill_trades_by_date[_t["_d"]].append(_t)
n_drill_trades = len(drill_trades)
n_drill_trade_days = len(drill_trades_by_date)

# トレード期間 + 前後マージン
# v3 設計判断(2): 発火389全件描画のため、期間は発火CSV全期間との合算に拡張
all_fire_cell_dates = sorted(fires_by_cell.keys())
start = min(all_dates[0], all_fire_cell_dates[0]).replace(day=1)
# 2026-07-01 fix: 月ブロックの終端に date.today() を含める。トレード/発火の最終日だけで
#   end_d を決めると、月初にトレード0・発火0の当月ページが立たない（環境データ
#   daily_agg/mfe_mae が当月まで来ていても期間計算では未使用だった）。
#   → 今日までは必ず月ブロックを立てる（ノートレード月の「景色」も認識対象）。
end_d = max(all_dates[-1], all_fire_cell_dates[-1], date.today())
end = (end_d.replace(day=28) + timedelta(days=4)).replace(day=1)

# ============================================================
# 階層的可視化ロジック (v0.4 — 段階化)
# ============================================================
# あろさんの認識粒度は段階的（連続値で判断してない）。
# 連続グラデーション → 閾値ベースの階段明度に置き換え。
# 評価ラベル（HOT/強/弱）は出さない、明度の階段のみ。

# --- H4 段階化テーブル ---
# (下限ADX, 明度lightness%) — adx >= 下限 でマッチ
# 候補: 15-20-25-30-35 の5段でステップ、+ <15 の凪
H4_STEPS = [
    # (lo, lightness, saturation, step_name, glow_strength)
    # v0.7: ADX 25+ は派手に光らせる（lightness/saturation UP、glow効果）
    # あろさん指示「ADX 25以上の場面はもっと目立つように色を光らせていい」
    # glow_strength: 0=なし / 1〜3=段階的なbox-shadow強度
    (35, 50, 95, "s5", 3),  # 最強: lightness 50, sat 95, glow強
    (30, 44, 88, "s4", 2),  # 強: lightness 44, sat 88, glow中
    (25, 38, 80, "s3", 1),  # 派手化境界: lightness 38, sat 80, glow弱
    (20, 22, 65, "s2", 0),  # 中: 控えめ
    (15, 14, 55, "s1", 0),  # 弱: 控えめ
]
H4_NAGI_MAX = 15  # ADX < 15 は凪扱い

# --- H1 段階化テーブル (補助 → 刻み少なめ) ---
H1_STEPS = [
    (25, 26, "s4"),
    (20, 20, "s3"),
    (15, 14, "s2"),
    (10, 9,  "s1"),
]
H1_NAGI_MAX = 10  # H1 は凪閾値を下げる（補助なので感度高め）

def h4_step(adx_val):
    """ADX値 → (lightness%, saturation%, step_name, glow_strength)。凪なら None。

    v0.7: saturation/glow_strength を追加（ADX 25+ を派手化）
    """
    if adx_val is None or adx_val < H4_NAGI_MAX:
        return None
    for lo, light, sat, name, glow in H4_STEPS:
        if adx_val >= lo:
            return (light, sat, name, glow)
    return None  # フォールバック（理論上ここには来ない）

def h1_step(adx_val):
    """H1 ADX値 → (lightness%, step_name)。凪なら None。"""
    if adx_val is None or adx_val < H1_NAGI_MAX:
        return None
    for lo, light, name in H1_STEPS:
        if adx_val >= lo:
            return (light, name)
    return None

# ============================================================
# v0.8: H1×H4 合成スコア（日次版）
# ============================================================
# 設計方針（番人観点）:
#   - 既存 process_wavelog.calc_adx_score（週次）の幾何平均構造を継承
#   - 週次は H4_Pct_Above20 が利用可能だが、日次では H4 ADX 単点値しかない
#     → H4 ADX 値そのものを正規化して使用（H4_norm）
#   - パターン重み付け / ATR Zone 係数 / 加熱帯ペナルティは入れない（純粋強度のみ）
#   - 値は 0-100、片方ゼロでほぼゼロ設計（幾何平均の性質）
#
# 正規化:
#   H1: ADX 10→0, 40→100 でクリップ（週次と同一）
#   H4: ADX 15→0, 40→100 でクリップ
#       ※H4 ADX(46)は平滑化強く週次でも閾値25採用、日次も低めの15スタートが実態に合う
#
# 合成:
#   sqrt(H1_norm * H4_norm) × 0.85
#   → 強度合成のみ。bonus 項は週次の「H4_Pct_Above25」が日次にないので削除
def calc_daily_score(h1_adx, h4_adx, d1_adx=None, d1_di_dir=None, h4_di_dir=None):
    """日次 H1×H4(+D1) 合成スコア (0-100)

    v0.9: あろさん感覚に合わせた重み付き加算式
      H1単発(ADX35)         → 50点
      H1 + H4伸び           → 80点
      + D1大局と同方向     → 100点

    Returns:
        float (0.0-100.0) or None（データ欠損時）
    """
    if h1_adx is None or h4_adx is None:
        return None
    # 各時間軸の正規化（0-1）
    H1_norm = max(0.0, min(1.0, (h1_adx - 10.0) / 25.0))  # ADX 10=0, 35=1
    H4_norm = max(0.0, min(1.0, (h4_adx - 15.0) / 20.0))  # ADX 15=0, 35=1
    D1_norm = 0.0
    if d1_adx is not None:
        D1_norm = max(0.0, min(1.0, (d1_adx - 18.0) / 15.0))  # ADX 18=0, 33=1
    # D1 alignment: 大局と H4 が同方向なら適用
    D1_aligned = 1 if (d1_di_dir == h4_di_dir and d1_di_dir in ("UP", "DOWN")) else 0
    # 重み付き加算: 50 + 30 + 20 = 100
    score = H1_norm * 50.0 + H4_norm * 30.0 + D1_aligned * D1_norm * 20.0
    return round(min(100.0, score), 1)

# スコア段階化テーブル（H4_STEPS と整合させた閾値）
# ADX 段階と1対1ではなく、合成スコアの実測レンジで再分配
SCORE_STEPS = [
    # (lo, lightness, saturation, step_name, glow_strength)
    # v0.9: グロウ選別化（高スコアの日だけ浮き上がる、中位は沈める）
    (80, 56, 100, "s5", 3),  # 強グロウ・浮き上がる
    (60, 40, 85,  "s4", 1),  # 軽グロウ
    (40, 28, 68,  "s3", 0),  # 背景のみ
    (20, 18, 50,  "s2", 0),  # 沈める
    (10, 12, 38,  "s1", 0),  # 極薄
]
SCORE_NAGI_MAX = 15  # スコア 15 未満は凪扱い

def score_step(score):
    """スコア値 → (lightness%, saturation%, step_name, glow_strength)。凪なら None。"""
    if score is None or score < SCORE_NAGI_MAX:
        return None
    for lo, light, sat, name, glow in SCORE_STEPS:
        if score >= lo:
            return (light, sat, name, glow)
    return None

# --- 旧 adx_normalize (連続線形マップ) は撤去 ---
# DI spread → 色相の彩度マッピングはそのまま（DI方向の認識は連続でOK）
# あろさん指摘は「ADX強度」が対象。DI spread の連続性はキープ。

# --- DI 方向 → 色相 ---
# DI spread を [-30, +30] を [赤, 灰, 青] にマッピング
# 凪（ADX低）は灰色固定
def di_to_hue(di_spread, adx_val):
    """戻り値: (hue, saturation_modifier)"""
    if adx_val is None or adx_val < 15:
        # 凪はグレー固定（あろさん指摘）
        return None, None  # → グレー扱い
    if di_spread is None:
        return 220, 0.3  # 中立青系
    # spread を [-30, 30] にクランプして 0-1 に変換
    norm = max(-1.0, min(1.0, di_spread / 30.0))
    # +1=青(220) / 0=灰中立(220→sat下げ) / -1=赤(0)
    if norm > 0:
        hue = 220  # 青系
        sat = 0.3 + 0.5 * norm  # 0.3〜0.8
    else:
        hue = 0    # 赤系
        sat = 0.3 + 0.5 * abs(norm)
    return hue, sat

def h4_bg_style(rec):
    """H4 主役セル背景: 色相(DI) + 段階明度+彩度(スコア) → HSL文字列を返す。

    v0.4 変更点: ADX強度を 5段階の階段明度に変更（連続グラデ → 閾値ベース）
    v0.7 変更点: ADX 25+ で saturation/lightness を大幅UP + box-shadow グロウ
    v0.8 変更点: ADX 単点 → H1×H4 合成スコアベースに置換
                 → 1日の偏りと強度を1つの数値で読める設計
    """
    if not rec:
        return {
            "bg": "#0a0a12",
            "border": "#1a1a22",
            "label": "—",
            "is_nagi": True,
            "glow": "",
            "score": None,
        }
    h4_adx = rec.get("h4_adx46")  # 背景濃淡用 (mean)
    h1_adx = rec.get("h1_avg_adx")  # 背景濃淡用 (mean)
    di_spread = rec.get("h4_di_spread")
    # v0.9: 大局 D1 と H4 の方向整合をスコアに反映
    d1_adx = rec.get("d1_adx22")
    d1_di_dir = rec.get("d1_di_dir")
    h4_di_dir = rec.get("h4_di_dir")
    # v1.2: スコア計算は max ベース（「伸びた瞬間」哲学、ADX素地の事実情報）
    #       max キーが無い場合（週次フォールバック時）は mean を使用
    h1_adx_for_score = rec.get("h1_adx_max") or h1_adx
    h4_adx_for_score = rec.get("h4_adx_max") or h4_adx
    score = calc_daily_score(h1_adx_for_score, h4_adx_for_score, d1_adx, d1_di_dir, h4_di_dir)
    if score is None and h4_adx is None:
        return {
            "bg": "#0a0a12",
            "border": "#1a1a22",
            "label": "—",
            "is_nagi": True,
            "glow": "",
            "score": None,
        }
    # v0.8: 凪判定はスコアベース（fallback で H4 ADX < 15 も凪扱い維持）
    is_nagi_score = score is None or score < SCORE_NAGI_MAX
    is_nagi_adx = h4_adx is not None and h4_adx < H4_NAGI_MAX
    if is_nagi_score or is_nagi_adx:
        # 凪は2段: スコア<10 or h4_adx<10 = 極淡 / それ以外 = 淡
        if (score is not None and score < 10) or (h4_adx is not None and h4_adx < 10):
            gray, gray_b = 18, 22
        else:
            gray, gray_b = 30, 34
        return {
            "bg": f"rgb({gray},{gray},{gray_b})",
            "border": f"rgb({gray+12},{gray+12},{gray_b+12})",
            "label": "凪",
            "is_nagi": True,
            "glow": "",
            "score": score,
        }
    # 段階明度取得（スコアベース）
    step = score_step(score)
    if step is None:
        return {
            "bg": "#0a0a12",
            "border": "#1a1a22",
            "label": "—",
            "is_nagi": True,
            "glow": "",
            "score": score,
        }
    lightness, step_sat, step_name, glow_strength = step
    # 色相は DI 方向で固定（青/赤の2択、di_to_hue は ADX が必要なので h4_adx を使用）
    hue, di_sat = di_to_hue(di_spread, h4_adx)
    if hue is None:
        return {
            "bg": "#0a0a12",
            "border": "#1a1a22",
            "label": "凪",
            "is_nagi": True,
            "glow": "",
            "score": score,
        }
    # 合成彩度: スコア段階テーブル × DI spread強度
    di_factor = 0.6 + 0.5 * (di_sat - 0.3)  # 0.6〜1.0
    sat_pct = int(min(100, step_sat * di_factor))
    bg = f"hsl({hue}, {sat_pct}%, {lightness}%)"
    # 枠線
    if glow_strength >= 1:
        border_l = min(lightness + 22, 75)
        border_sat = min(100, sat_pct + 5)
    else:
        border_l = min(lightness + 12, 60)
        border_sat = sat_pct
    border = f"hsl({hue}, {border_sat}%, {border_l}%)"
    # グロウ（スコアベース、SCORE_STEPS の glow_strength に従う）
    if glow_strength == 3:
        glow = f"box-shadow: 0 0 10px hsla({hue},{sat_pct}%,60%,0.55), inset 0 0 14px hsla({hue},{sat_pct}%,55%,0.35);"
    elif glow_strength == 2:
        glow = f"box-shadow: 0 0 7px hsla({hue},{sat_pct}%,55%,0.45), inset 0 0 10px hsla({hue},{sat_pct}%,50%,0.28);"
    elif glow_strength == 1:
        glow = f"box-shadow: 0 0 5px hsla({hue},{sat_pct}%,50%,0.35), inset 0 0 7px hsla({hue},{sat_pct}%,45%,0.20);"
    else:
        glow = ""
    label = "UP" if (di_spread or 0) > 5 else ("DOWN" if (di_spread or 0) < -5 else "拮抗")
    return {
        "bg": bg,
        "border": border,
        "label": label,
        "is_nagi": False,
        "glow": glow,
        "score": score,
    }

def h1_bg_style(rec):
    """H1 補助セル背景: 段階明度のみ（DI は表示しない、v0.3 仕様継続）

    v0.4 変更点:
    - 連続グラデ → 4段階の階段明度
    - 補助なので刻みは H4 より少なめ
    """
    if not rec:
        return {"bg": "transparent", "label": "—"}
    h1_adx = rec.get("h1_avg_adx")
    if h1_adx is None:
        # 暫定: h4 から H1 ADX を近似（後工程で日次粒度化）
        h4_adx = rec.get("h4_adx46")
        if h4_adx is None:
            return {"bg": "transparent", "label": "—"}
        h1_adx = h4_adx
    # 凪判定 (H1)
    if h1_adx < H1_NAGI_MAX:
        # 凪: 極淡グレー単色
        return {
            "bg": "hsl(210, 15%, 6%)",
            "label": f"H1:{h1_adx:.0f}",
            "value": h1_adx,
        }
    step = h1_step(h1_adx)
    if step is None:
        return {"bg": "transparent", "label": f"H1:{h1_adx:.0f}", "value": h1_adx}
    lightness, step_name = step
    bg = f"hsl(210, 30%, {lightness}%)"
    return {
        "bg": bg,
        "label": f"H1:{h1_adx:.0f}",
        "value": h1_adx,
    }

def d1_band_color(rec):
    """D1 帯色: ATR Phase を色相の主役にした色マッピング（v0.9 / 2026-06-22 あろさん要望）

    あろさん指摘（v0.9 で深化）:
      「ATRは値幅情報。BU/PD は赤青(DI/ADX=方向)と役割が違う。
       BU/PD を赤青以外で独立して色分けせよ（ADXと被る・役割が違う）」
      [[atr-is-band-not-direction]]

    色設計（v0.9 — Phase を色相の主役に昇格 / 旧v0.8「色相=DI方向・濃淡=Phase」から転換）:
      - 色相 = ATR Phase（BU=琥珀 / PD=紫 / RANGE=灰）   ← 値幅局面（帯の主役）
      - DI 方向（UP/DOWN）は色から分離し label テキストで保持 ← 赤青はDI/ADX(セル内)方向専用に解放

      | ATR Phase | 色        | 意味                   |
      |-----------|-----------|------------------------|
      | BU        | 琥珀(鮮)  | 拡張（値幅エネルギー） |
      | PD        | 紫        | 収縮（値幅収束）       |
      | RANGE     | グレー    | D1 ADX<18 トレンド不在 |

      ※方向情報は捨てず label に "/ UP" "/ DOWN" として残す。色では赤青を一切使わない。
    """
    if not rec:
        return None
    pattern = rec.get("d1_pattern", "—")
    adx = rec.get("d1_adx22")
    di_dir = rec.get("d1_di_dir", "—")
    adx_txt = f"ADX{adx:.0f}" if adx is not None else "ADX—"

    # RANGE判定（D1 ADX < 18）— v0.7 リネーム継続
    if adx is not None and adx < 18:
        return {
            "color": "rgba(120,120,135,0.28)",
            "label": f"D1 RANGE",
            "pattern": "RANGE",
            "adx_txt": adx_txt,
        }

    # v0.9: 色相=ATR Phase（BU琥珀 / PD紫）。方向は色から分離し label テキストへ
    if pattern == "BU":
        col = "rgba(235,175,55,0.45)"   # 琥珀＝拡張（値幅エネルギー）
        sub = " / UP (拡張×上昇)" if di_dir == "UP" else " / DOWN (拡張×下落)" if di_dir == "DOWN" else " / —"
        return {"color": col, "label": f"D1 BU{sub}", "pattern": "BU", "adx_txt": adx_txt}

    if pattern == "PD":
        col = "rgba(150,110,205,0.40)"  # 紫＝収縮（値幅収束）
        sub = " / UP (縮小×上昇)" if di_dir == "UP" else " / DOWN (縮小×下落)" if di_dir == "DOWN" else " / —"
        return {"color": col, "label": f"D1 PD{sub}", "pattern": "PD", "adx_txt": adx_txt}

    return {"color": "rgba(100,100,120,0.20)", "label": f"D1 {pattern}", "pattern": pattern, "adx_txt": adx_txt}

# ============================================================
# H4 Phase Auto バッジ
# ============================================================
PHASE_BADGE = {
    "BU":     ("ph-bu",     "BU"),
    "PD":     ("ph-pd",     "PD"),
    "凪":     ("ph-nagi",   "凪"),
    "凪離脱": ("ph-leave",  "離脱"),
    "収束底": ("ph-bottom", "底"),
}

# ============================================================
# 月ループユーティリティ（土日省略）
# ============================================================
def month_iter(s, e):
    cur = s
    while cur < e:
        yield cur
        cur = cur.replace(year=cur.year+1, month=1) if cur.month == 12 else cur.replace(month=cur.month+1)

def month_weekdays(year, month):
    """月内の月〜金のみを週グループでyield"""
    first = date(year, month, 1)
    # 月の最初の月曜まで遡る
    start_d = first - timedelta(days=first.weekday())
    last_day = (date(year+1, 1, 1) - timedelta(days=1)) if month == 12 else (date(year, month+1, 1) - timedelta(days=1))
    end_d = last_day + timedelta(days=(6 - last_day.weekday()))
    cur = start_d
    weeks_list = []
    cur_week = []
    while cur <= end_d:
        if cur.weekday() < 5:  # 月〜金のみ
            cur_week.append(cur)
        if cur.weekday() == 4:  # 金曜で区切り
            if cur_week:
                weeks_list.append(cur_week)
            cur_week = []
        cur += timedelta(days=1)
    if cur_week:
        weeks_list.append(cur_week)
    return weeks_list

# ============================================================
# HTML 生成
# ============================================================
html = []
html.append("""<!DOCTYPE html>
<html lang="ja"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>Daily Research Calendar — マニ v3 (v2ベース+シグナル統合)</title>
<style>
* { box-sizing: border-box; }
body {
  margin: 0; background: #05090f; color: #8abaee;
  font-family: -apple-system, BlinkMacSystemFont, 'Hiragino Sans', sans-serif;
  font-size: 12px; padding: 20px;
}
h1 { font-size: 14px; color: #5a9adf; margin: 0 0 4px; letter-spacing: .08em; }

/* ===== v2.0 タブUI ===== */
.tabs {
  display: flex; gap: 4px; margin-bottom: 18px;
  border-bottom: 1px solid #162844;
  padding-bottom: 0;
}
.tab-btn {
  background: transparent;
  color: #4a6a8a;
  border: 1px solid transparent;
  border-bottom: none;
  padding: 8px 18px;
  font-size: 12px;
  cursor: pointer;
  letter-spacing: .04em;
  font-family: inherit;
  border-radius: 4px 4px 0 0;
  transition: background 0.15s, color 0.15s;
  margin-bottom: -1px;
}
.tab-btn:hover { color: #6a8aaa; background: rgba(20,40,68,0.3); }
.tab-btn.active {
  color: #5a9adf;
  background: #080d16;
  border-color: #162844;
  border-bottom: 1px solid #080d16;
  font-weight: 700;
}
.tab-pane { display: none; }
.tab-pane.active { display: block; }

/* ===== v2.0 全体像タブ ===== */
.overview-summary {
  margin-bottom: 18px;
  padding: 14px 16px;
  background: #080d16;
  border: 1px solid #162844;
  border-radius: 6px;
  display: flex; flex-wrap: wrap; gap: 22px;
  font-size: 11px;
}
.overview-summary .stat-blk {
  display: flex; flex-direction: column; gap: 2px;
}
.overview-summary .stat-k { font-size: 9.5px; color: #4a6a8a; letter-spacing: .05em; }
.overview-summary .stat-v {
  font-size: 16px; color: #8abaee; font-weight: 700;
  font-variant-numeric: tabular-nums;
}
.overview-summary .stat-v.pos { color: #5ab8ff; }
.overview-summary .stat-v.neg { color: #ef6060; }

.overview-warning {
  margin-bottom: 18px;
  padding: 10px 14px;
  background: rgba(200,180,80,0.08);
  border: 1px solid rgba(200,180,80,0.25);
  border-radius: 6px;
  font-size: 10.5px;
  color: rgba(220,200,140,0.85);
  line-height: 1.6;
}
.overview-warning b { color: rgba(240,220,160,1); }

/* 円グラフグリッド */
.pie-grid {
  display: grid;
  grid-template-columns: repeat(2, 1fr);
  gap: 14px;
  margin-bottom: 18px;
}
.pie-card {
  background: #080d16;
  border: 1px solid #162844;
  border-radius: 6px;
  padding: 14px;
  display: flex; flex-direction: column;
}
.pie-card-title {
  font-size: 12px; color: #5a9adf; font-weight: 600;
  letter-spacing: .04em; margin-bottom: 4px;
}
.pie-card-sub {
  font-size: 9.5px; color: #4a6a8a;
  margin-bottom: 12px; line-height: 1.5;
}
.pie-card-body {
  display: grid;
  grid-template-columns: 140px 1fr;
  gap: 14px;
  align-items: center;
}
.pie-svg-wrap {
  display: flex; align-items: center; justify-content: center;
}
.pie-svg { display: block; }
/* v0.2: 扇形クリッカブル化（フィルタトリガー） */
.pie-slice {
  cursor: pointer;
  transition: opacity 0.15s, filter 0.15s, transform 0.15s;
}
.pie-svg .pie-slice:hover {
  filter: brightness(1.18) saturate(1.1);
}
.pie-svg .pie-slice.pie-slice-active {
  filter: brightness(1.25) drop-shadow(0 0 4px rgba(160,200,255,0.55));
}
.pie-legend-row.pie-slice { padding: 1px 4px; border-radius: 2px; }
.pie-legend-row.pie-slice:hover { background: rgba(40,70,110,0.20); }
.pie-legend-row.pie-slice.pie-slice-active {
  background: rgba(74,144,226,0.18);
  outline: 1px solid rgba(120,170,230,0.45);
}
/* 凡例 */
.pie-legend {
  display: flex; flex-direction: column; gap: 4px;
  font-size: 10px;
  font-variant-numeric: tabular-nums;
}
.pie-legend-row {
  display: grid;
  grid-template-columns: 12px 1fr auto auto;
  gap: 6px;
  align-items: center;
}
.pie-legend-sw {
  width: 12px; height: 12px; border-radius: 2px;
  border: 1px solid rgba(255,255,255,0.08);
}
.pie-legend-k { color: #c8d8e8; }
.pie-legend-n {
  color: #6a8aaa; font-weight: 600;
  text-align: right;
}
.pie-legend-pct {
  color: #4a6a8a; font-size: 9px;
  text-align: right; min-width: 32px;
}
/* データ無し */
.pie-empty {
  font-size: 10px; color: #3a5a7a;
  padding: 30px 0;
  text-align: center;
}

/* 詳細分析タブ（プレースホルダ） */
.detail-placeholder {
  padding: 30px;
  background: #080d16;
  border: 1px solid #162844;
  border-radius: 6px;
  text-align: center;
  color: #4a6a8a;
  font-size: 11px;
  line-height: 1.8;
}
.detail-placeholder b { color: #6a8aaa; }

.sub { font-size: 10px; color: #2a4a6a; margin-bottom: 18px; }

/* ===== 凡例 ===== */
.legend {
  display: flex; gap: 16px; margin-bottom: 22px; flex-wrap: wrap;
  font-size: 10px; color: #6a8aaa;
  padding: 12px 14px;
  background: #080d16;
  border: 1px solid #162844;
  border-radius: 6px;
}
.legend .grp { display: flex; gap: 8px; align-items: center; }
.legend .grp .ttl { color: #4a7aaa; font-weight: 600; margin-right: 4px; }
.legend .sw {
  width: 22px; height: 14px; border-radius: 2px; display: inline-block;
  border: 1px solid rgba(255,255,255,0.08);
}
.legend .ph {
  display: inline-block; padding: 1px 5px; border-radius: 3px; font-size: 9px; font-weight: 600;
}
.legend .d1band {
  display: inline-block; width: 30px; height: 8px; border-radius: 1px;
}

/* ===== 月コンテナ ===== */
.month {
  margin-bottom: 28px;
  border: 1px solid #162844;
  border-radius: 6px;
  background: #080d16;
  padding: 12px;
}
.month-title { font-size: 13px; color: #5a9adf; margin-bottom: 4px; font-weight: 600; letter-spacing: .05em; }
.month-stats { font-size: 10px; color: #4a7aaa; margin-bottom: 10px; }

/* ===== 週グループ（D1帯 + セル群） ===== */
.week-group {
  margin-bottom: 6px;
}
.d1-band {
  height: 22px;
  border-radius: 4px 4px 0 0;
  display: flex; align-items: center; justify-content: space-between;
  padding: 0 10px;
  font-size: 10px;
  letter-spacing: .05em;
  color: #d8e8f8;
  font-weight: 700;
  border: 1px solid rgba(255,255,255,0.08);
  border-bottom: none;
  text-shadow: 0 1px 1px rgba(0,0,0,0.4);
}
.d1-band .d1-adx {
  font-size: 9px;
  opacity: 0.75;
  font-weight: 500;
}
.d1-band.empty {
  background: rgba(60,60,80,0.08);
  color: #4a6a8a;
}

/* ===== 週内 5日セル ===== */
.week-cells {
  display: grid; grid-template-columns: repeat(5, 1fr); gap: 3px;
  background: rgba(0,0,0,0.2);
  padding: 3px;
  border-radius: 0 0 3px 3px;
}
.dow-row {
  display: grid; grid-template-columns: repeat(5, 1fr); gap: 3px;
  padding: 0 3px;
  margin-bottom: 2px;
}
.dow {
  text-align: center; font-size: 10px; color: #2a4a6a; font-weight: 600;
  padding: 3px 0; letter-spacing: .08em;
}

/* ===== セル本体 ===== */
/* v0.3 階層化: H4=主役46% / H1=補助16% / 残り = 日付8% + シグナル8% + 結果14% + 区切り */
/* v3-A1: 最下部にシグナルドット行 13px を追加（min-height も +13px して既存行の比率を保持） */
.cell {
  border-radius: 4px;
  display: grid;
  grid-template-rows: 16px 1fr 22px 4px 20px 28px 13px;  /* 日付 / H4主役 / H1補助 / 区切り / シグナル / 結果 / 発火ドット行 */
  min-height: 173px;
  position: relative;
  background: #05090f;
  border: 1px solid #0b1825;
  font-size: 10px;
  overflow: hidden;
}
.cell.outside { opacity: 0.15; }
/* v3 fix (2026-07-01): 未来日=まだ来ていない日。欠損(暗い空セル)と区別して
   「これから」を淡色で示す。当月に入った直後の 7/2,7/3 等がこれに該当。 */
.cell.future { opacity: 0.32; filter: saturate(0.45); }
.cell.future .day-hdr span { color: #4a6a8a; }

/* 日付ヘッダ */
.cell .day-hdr {
  display: flex; justify-content: space-between; align-items: center;
  padding: 2px 4px;
  font-size: 10px; font-weight: 600; color: #6a8aaa;
  background: rgba(0,0,0,0.3);
}
.cell .day-hdr .ph-badge {
  font-size: 8px; font-weight: 700; padding: 1px 4px; border-radius: 3px;
  letter-spacing: .03em;
}

/* H4 主役レーン (面積46%、ドンと真ん中) */
.cell .h4-main {
  position: relative;
  display: flex; align-items: center; justify-content: center;
  font-size: 28px; font-weight: 800;
  letter-spacing: .02em;
  text-shadow: 0 1px 3px rgba(0,0,0,0.7);
}
.cell .h4-main .adx-val {
  color: rgba(255,255,255,0.95);
  z-index: 2;
}
.cell .h4-main .adx-val.nagi {
  color: rgba(180,180,200,0.55);
  font-weight: 500;
  font-size: 20px;
}
.cell .h4-main .di-mark {
  position: absolute; top: 4px; left: 6px;
  font-size: 10px; opacity: 0.85;
  letter-spacing: .04em;
  font-weight: 700;
}
/* ADX値の補足表示（右上、小フォント、トレード日に降格） */
.cell .h4-main .adx-tiny {
  position: absolute; top: 4px; right: 6px;
  font-size: 9px; opacity: 0.7;
  letter-spacing: .03em;
  font-weight: 600;
  color: rgba(255,255,255,0.7);
  text-shadow: 0 1px 1px rgba(0,0,0,0.6);
}
/* v0.5 MAE/MFE 中央主役表示（トレード日のみ） */
.cell .h4-main .mfe-mae-box {
  position: relative;
  z-index: 2;
  display: flex; flex-direction: column;
  align-items: center; justify-content: center;
  gap: 4px;
  width: 100%;
  padding: 0 6px;
}
.cell .h4-main .mfe-mae-nums {
  display: flex; gap: 8px; align-items: baseline;
  font-size: 14px; font-weight: 700;
  letter-spacing: 0;
}
.cell .h4-main .mfe-num { color: #5ab8ff; text-shadow: 0 1px 2px rgba(0,0,0,0.8); }
.cell .h4-main .mae-num { color: #ef6060; text-shadow: 0 1px 2px rgba(0,0,0,0.8); }
.cell .h4-main .mfe-mae-lbl {
  font-size: 8px; font-weight: 600; opacity: 0.65;
  margin-right: 2px;
  text-shadow: 0 1px 1px rgba(0,0,0,0.6);
}
/* MAE/MFE 細バー（中央下、左右に伸びる） */
.cell .h4-main .mfe-mae-bar {
  width: 92%; height: 4px;
  display: flex;
  align-items: center;
  position: relative;
  background: rgba(0,0,0,0.35);
  border-radius: 1px;
}
.cell .h4-main .mfe-mae-bar .center-tick {
  position: absolute; left: 50%; top: -1px; bottom: -1px;
  width: 1px; background: rgba(255,255,255,0.4);
  z-index: 2;
}
.cell .h4-main .mfe-mae-bar .bar-mfe {
  position: absolute; left: 50%; top: 0; bottom: 0;
  background: linear-gradient(90deg, rgba(90,184,255,0.6), rgba(90,184,255,0.95));
  border-radius: 0 1px 1px 0;
}
.cell .h4-main .mfe-mae-bar .bar-mae {
  position: absolute; right: 50%; top: 0; bottom: 0;
  background: linear-gradient(90deg, rgba(239,96,96,0.95), rgba(239,96,96,0.6));
  border-radius: 1px 0 0 1px;
}

/* v1.3 値動きレンジバー（非トレード日の中央）
 * あろさんフィードバック（2026-06-10）:
 *   - 旧 BUY/SELL 2本バーは同じ情報の二重表示（BUY MFE = SELL MAE 等）
 *   - 1本の「値動きレンジバー」に統合 → 上下方向の最大伸び
 *   - BUY/SELL 矢印は廃止（方向は背景の色相で既に表現済み）
 * 構造:
 *   - 「仮」マーク左上
 *   - 1本バー: 右=上方向の最大伸び (max High - entry) / 左=下方向の最大伸び (entry - min Low)
 *   - 中央 tick = entry 価格
 *   - 数値表示: ↑上=N / ↓下=N（方向中立）
 *   - 全体的に opacity 0.72 で仮想感維持（景色が主役、レンジは補助）
 * 番人観点: 「BUY 視点で利益/損失」のような立場依存ラベル化なし、純粋な値動き事実情報
 */
.cell .h4-main .virtual-mark {
  position: absolute; top: 4px; left: 6px;
  font-size: 8px; opacity: 0.55;
  letter-spacing: .04em;
  font-weight: 600;
  color: rgba(200,210,230,0.7);
  text-shadow: 0 1px 1px rgba(0,0,0,0.5);
}
.cell .h4-main .range-box {
  position: relative; z-index: 2;
  display: flex; flex-direction: column;
  align-items: center; justify-content: center;
  gap: 4px;
  width: 100%;
  padding: 0 6px;
  opacity: 0.78;  /* 控えめ（仮想感維持） */
}
.cell .h4-main .range-nums {
  display: flex; gap: 10px; align-items: baseline;
  font-size: 11px; font-weight: 700;
  letter-spacing: 0;
  justify-content: center;
}
.cell .h4-main .range-nums .rn-lbl {
  font-size: 8px; font-weight: 600;
  opacity: 0.65;
  margin-right: 2px;
  color: rgba(200,210,230,0.85);
  text-shadow: 0 1px 1px rgba(0,0,0,0.5);
}
.cell .h4-main .range-nums .rn-up   { color: rgba(140,200,240,0.92); text-shadow: 0 1px 1px rgba(0,0,0,0.55); }
.cell .h4-main .range-nums .rn-down { color: rgba(230,140,140,0.88); text-shadow: 0 1px 1px rgba(0,0,0,0.55); }

/* バー本体（1本、中央 tick から左右に伸びる） */
.cell .h4-main .range-bar {
  width: 92%; height: 4px;
  display: flex;
  align-items: center;
  position: relative;
  background: rgba(0,0,0,0.35);
  border-radius: 1px;
}
.cell .h4-main .range-bar .rb-center-tick {
  position: absolute; left: 50%; top: -2px; bottom: -2px;
  width: 1px; background: rgba(255,255,255,0.42);
  z-index: 2;
}
.cell .h4-main .range-bar .rb-up {
  position: absolute; left: 50%; top: 0; bottom: 0;
  background: linear-gradient(90deg, rgba(110,180,230,0.5), rgba(110,180,230,0.85));
  border-radius: 0 1px 1px 0;
}
.cell .h4-main .range-bar .rb-down {
  position: absolute; right: 50%; top: 0; bottom: 0;
  background: linear-gradient(90deg, rgba(220,120,120,0.85), rgba(220,120,120,0.5));
  border-radius: 1px 0 0 1px;
}

/* H1 補助レーン (面積16%、H4の約1/3) */
.cell .h1-aux {
  display: flex; align-items: center; padding: 0 6px;
  font-size: 10px;
  color: #c8d8e8;
  border-top: 1px solid rgba(0,0,0,0.5);
  position: relative;
}
.cell .h1-aux .h1-bar {
  position: absolute; top: 0; left: 0; right: 0; bottom: 0;
  z-index: 0;
}
.cell .h1-aux .h1-txt {
  position: relative; z-index: 1;
  font-weight: 600;
  text-shadow: 0 1px 1px rgba(0,0,0,0.5);
}

/* 区切り */
.cell .divider {
  background: rgba(0,0,0,0.4);
}

/* シグナル */
.cell .signal {
  display: flex; align-items: center; justify-content: center;
  gap: 5px;
  font-size: 10px;
  color: #6a8aaa;
  background: rgba(0,0,0,0.3);
  padding: 0 4px;
}
.cell .signal.fired { color: #ffd060; font-weight: 700; }
/* v1.3 トレード日タグ表示（pattern / ATR Ratio）
 * 番人観点: 色フラット、評価ラベルなし。事実情報のみ。
 * パターン別色分け（PatA=青等）は BT 知見の UI 焼き付けで NG。
 */
.cell .signal .tag {
  display: inline-block;
  font-size: 8px; font-weight: 600;
  padding: 1px 4px;
  border-radius: 2px;
  background: rgba(255,255,255,0.08);
  color: rgba(220,228,240,0.78);
  letter-spacing: .02em;
  text-shadow: 0 1px 1px rgba(0,0,0,0.4);
}
.cell .signal .tag.atr {
  background: rgba(255,255,255,0.05);
  color: rgba(200,210,225,0.7);
  font-weight: 500;
}
/* v1.4 「その他」タグは控えめ表示（意思決定として残るが構造化ではない） */
.cell .signal .tag.other {
  background: rgba(255,255,255,0.04);
  color: rgba(180,188,200,0.55);
  font-weight: 400;
  opacity: 0.75;
}

/* 結果 — v0.6: 背景=ポジション方向(BUY青/SELL赤) / 文字色=損益(勝/負) */
.cell .result {
  display: flex; align-items: center; justify-content: center;
  gap: 4px;
  font-size: 11px; font-weight: 700;
  padding: 1px 6px 1px 5px;
  position: relative;
}
/* 背景: ポジション方向 (D1帯の半透明と区別するため飽和強め+左border) */
.cell .result.tr-buy   { background: #0e2a5a; border-top: 1px solid #1a4a8a; border-left: 3px solid #4a90e2; }
.cell .result.tr-sell  { background: #3a0a18; border-top: 1px solid #6a1a2a; border-left: 3px solid #d8506a; }
/* v0.7: 建値はさらに目立たなく（背景・枠ともに極端に薄く） */
.cell .result.tr-zero  { background: rgba(20,20,28,0.5); border-top: 1px solid rgba(40,40,50,0.4); border-left: 3px solid rgba(80,80,90,0.5); font-size: 9px; }
.cell .result.tr-empty { background: rgba(0,0,0,0.2); color: #2a4a6a; border-left: 3px solid transparent; }
/* v0.7: 非トレード日の環境メモ表示（事実情報のみ、捏造禁止） */
.cell .result.tr-empty.env-memo {
  display: flex; flex-direction: column;
  justify-content: center; align-items: center;
  gap: 1px;
  padding: 2px 4px;
  font-size: 8px;
  color: #3a5a7a;
  background: rgba(0,0,0,0.25);
  letter-spacing: .02em;
  font-weight: 500;
}
.cell .result.tr-empty.env-memo .env-row {
  display: flex; gap: 6px; align-items: center;
  white-space: nowrap;
}
.cell .result.tr-empty.env-memo .env-k {
  opacity: 0.55; font-size: 7px;
}
.cell .result.tr-empty.env-memo .env-v {
  color: #5a7a9a;
}
/* 文字色: 損益 (勝=明るいクリーム / 負=くすんだグレー = 主張させない) */
.cell .result .pl-win  { color: #ffe080; }
.cell .result .pl-loss { color: #8090a0; }
/* v0.7: 建値の文字をさらにくすませる */
.cell .result .pl-zero { color: #5a5a65; font-weight: 500; }
.cell .result .zero-lbl { font-size: 7px; opacity: 0.5; color: #5a5a65; margin-right: 2px; letter-spacing: .02em; }
.cell .result .lot-info { font-size: 8px; opacity: 0.55; font-weight: 400; color: #c8d8e8; }
.cell .result.tr-zero .lot-info { opacity: 0.35; font-size: 7px; }
/* ポジション数バッジ (複数トレード日のみ右端) */
.cell .result .pos-cnt {
  font-size: 8px; opacity: 0.7; font-weight: 600;
  color: rgba(255,255,255,0.7);
  margin-left: auto;
  padding-left: 4px;
}

/* 凪離脱の警告枠（v0.2 継続） */
.cell.leave-warn {
  box-shadow: inset 0 0 0 1px rgba(255,204,0,0.55);
}

/* フェーズバッジ色 */
.ph-bu     { background: rgba(0,80,40,0.55);   color: #4dffa0; }
.ph-pd     { background: rgba(40,8,80,0.55);   color: #b07af8; }
.ph-nagi   { background: rgba(40,40,55,0.55);  color: #999; }
.ph-leave  { background: #ffcc00;              color: #1a1000; box-shadow: 0 0 4px rgba(255,204,0,0.5); }
.ph-bottom { background: rgba(0,60,80,0.55);   color: #4dccff; }

/* ===== サマリ ===== */
.totals {
  margin-top: 18px; padding: 14px;
  background: #080d16; border: 1px solid #162844; border-radius: 6px;
  font-size: 11px;
}
.totals .k { color: #6a8aaa; }
.totals .v { color: #8abaee; font-weight: 600; margin-right: 18px; }

.notes {
  margin-top: 10px; font-size: 10px; color: #4a6a8a;
  line-height: 1.6;
}
.notes b { color: #6a8aaa; }

/* ===== 軸1: シグナル別統計テーブル (v1.5) =====
 * 番人観点: 色フラット、評価ラベルなし。
 * パターン別色分け禁止（PAT-A=青 等は BT 知見の UI 焼き付け NG）
 */
.sig-stats {
  margin-top: 18px;
  padding: 14px;
  background: #080d16;
  border: 1px solid #162844;
  border-radius: 6px;
}
.sig-stats-title {
  font-size: 13px; color: #5a9adf; font-weight: 600;
  letter-spacing: .05em; margin-bottom: 4px;
}
.sig-stats-sub {
  font-size: 10px; color: #4a6a8a; line-height: 1.6;
  margin-bottom: 12px;
}
.sig-stats-sub b { color: #6a8aaa; }
.sig-table {
  width: 100%; border-collapse: collapse;
  font-size: 10px; color: #8abaee;
  background: rgba(0,0,0,0.2);
}
.sig-table th {
  text-align: center;
  padding: 6px 8px;
  background: rgba(20,40,68,0.6);
  color: #6a8aaa;
  border-bottom: 1px solid #1a3454;
  font-weight: 600;
  white-space: nowrap;
}
.sig-table td {
  padding: 5px 8px;
  text-align: right;
  border-bottom: 1px solid rgba(20,40,68,0.4);
  font-variant-numeric: tabular-nums;
}
.sig-table td.sig-name {
  text-align: left;
  font-weight: 600;
  color: #c8d8e8;
  white-space: nowrap;
}
.sig-table tbody tr:hover {
  background: rgba(40,70,110,0.15);
}
.sig-table .na {
  color: #3a5a7a; opacity: 0.5;
}
.sig-table .sample-low {
  display: inline-block;
  margin-left: 6px;
  font-size: 8px; font-weight: 600;
  padding: 1px 4px;
  border-radius: 2px;
  background: rgba(200,180,80,0.18);
  color: rgba(220,200,100,0.85);
  letter-spacing: .03em;
}
.sig-stats-notes {
  margin-top: 10px;
  font-size: 9.5px;
  color: #4a6a8a;
  line-height: 1.65;
}
.sig-stats-notes b { color: #6a8aaa; }

/* ===== 共通 ===== */
.cell .tooltip-tgt { cursor: help; }

/* ===== v2.2 同ページドリルダウン (全体像タブ) ===== */
.sig-table tbody tr[data-pattern] { transition: background 0.15s; }
.sig-table tbody tr[data-pattern].drill-active {
  background: #1a3a6a !important;
  box-shadow: inset 3px 0 0 #4a90e2;
}
.drilldown-wrap {
  margin-top: 14px; padding: 14px;
  background: #08111c; border: 1px solid #1a2a44;
  border-radius: 6px;
}
.drilldown-head { margin-bottom: 10px; }
.drilldown-title {
  font-size: 13px; color: #b0c8e8; font-weight: 600;
  letter-spacing: .04em; margin-bottom: 4px;
}
.drilldown-summary {
  padding: 8px 12px; background: #0a1525;
  border-left: 3px solid #4a90e2; border-radius: 3px;
  font-size: 11px; color: #b8d0ee; margin-bottom: 6px;
}
.drilldown-summary b { color: #8aa8ce; font-weight: 500; margin-right: 4px; }
.drilldown-hint {
  font-size: 10px; color: #6a8aaa; opacity: 0.85;
  display: flex; align-items: center; gap: 10px;
}
.drill-clear-btn {
  background: #0e1a2a; color: #b8d0ee;
  border: 1px solid #1a3454; border-radius: 3px;
  padding: 3px 9px; font-size: 10px; cursor: pointer;
  font-family: inherit;
  transition: background 0.15s, border-color 0.15s;
}
.drill-clear-btn:hover { background: #142844; border-color: #2a4a74; }
.drill-table th[data-sort="asc"]::after { content: " ▲"; color: #4a90e2; font-size: 9px; }
.drill-table th[data-sort="desc"]::after { content: " ▼"; color: #4a90e2; font-size: 9px; }
.detail-table th[data-sort="asc"]::after { content: " ▲"; color: #4a90e2; font-size: 9px; }
.detail-table th[data-sort="desc"]::after { content: " ▼"; color: #4a90e2; font-size: 9px; }
.pivot-hint {
  font-size: 10px; color: #6a8aaa; opacity: 0.85;
  margin-top: 6px; padding: 0 4px;
}

/* ===== v2.0 Step2 詳細分析タブ ===== */
.detail-head { padding: 0 4px 12px; }
.detail-title {
  font-size: 14px; color: #b0c8e8; font-weight: 600;
  letter-spacing: .05em; margin-bottom: 4px;
}
.detail-sub { font-size: 11px; color: #6a8aaa; line-height: 1.5; }
.detail-sub b { color: #d0a060; }

.filter-bar {
  display: flex; flex-wrap: wrap; gap: 10px 14px;
  padding: 12px 14px; background: #08111c;
  border: 1px solid #1a2a44; border-radius: 6px;
  margin-bottom: 10px; align-items: center;
}
.filter-bar label {
  font-size: 10px; color: #7a9ac0;
  display: flex; align-items: center; gap: 5px;
  letter-spacing: .03em;
}
.filter-bar select {
  background: #0e1a2a; color: #b8d0ee;
  border: 1px solid #2a4060; padding: 3px 8px;
  border-radius: 4px; font-size: 11px;
  font-family: inherit; cursor: pointer;
}
.filter-bar select:hover { border-color: #4a6090; }
.filter-bar input.f-date {
  background: #0a1320; color: #c8d8e8; border: 1px solid #1a3454;
  border-radius: 4px; padding: 4px 6px; font-size: 11px; font-family: inherit;
}
.filter-bar input.f-date:hover { border-color: #4a6090; }
.filter-bar .f-date-sep { color: #4a6a8a; margin: 0 3px; }
.f-reset {
  background: #2a3050; color: #b0c0d8; border: 1px solid #4a5070;
  padding: 4px 12px; border-radius: 4px; font-size: 10px;
  cursor: pointer; font-family: inherit;
}
.f-reset:hover { background: #3a4060; }

.pivot-bar {
  padding: 8px 14px; background: #0a1320;
  border: 1px solid #1a2a44; border-radius: 6px;
  margin-bottom: 10px;
}
.pivot-bar label {
  font-size: 10px; color: #7a9ac0;
  display: inline-flex; align-items: center; gap: 6px;
  letter-spacing: .03em;
}
.pivot-bar select {
  background: #0e1a2a; color: #b8d0ee;
  border: 1px solid #2a4060; padding: 3px 8px;
  border-radius: 4px; font-size: 11px; cursor: pointer;
}

.result-summary {
  padding: 10px 14px; background: #08121f;
  border-left: 3px solid #4a90e2; border-radius: 3px;
  margin-bottom: 10px; font-size: 12px; color: #b8d0ee;
  letter-spacing: .02em;
}
.result-summary b { color: #8aa8ce; font-weight: 500; margin-right: 4px; }

.pivot-table, .detail-table {
  width: 100%; border-collapse: collapse;
  margin-bottom: 10px; font-size: 11px;
}
.pivot-table th, .detail-table th {
  background: #0e1a2a; color: #a8c0e0; padding: 7px 10px;
  text-align: left; border-bottom: 1px solid #2a4060;
  font-weight: 500; letter-spacing: .03em;
}
.pivot-table td, .detail-table td {
  padding: 5px 10px; border-bottom: 1px solid #0e1828;
  color: #b8d0ee;
}
.pivot-table tr:hover, .detail-table tr:hover { background: #0a1525; }

.detail-table td.pos { color: #ffe080; font-weight: 500; }
.detail-table td.neg { color: #8090a0; }
.detail-table td.zero { color: #5a5a65; }

.trade-detail summary {
  cursor: pointer; padding: 8px 14px;
  background: #0a1320; border: 1px solid #1a2a44;
  border-radius: 4px; font-size: 11px; color: #8aa8ce;
  margin-bottom: 8px; letter-spacing: .03em;
}
.trade-detail summary:hover { background: #0e1a2a; }
.trade-detail[open] summary { background: #0e1a2a; }

/* ============================================================
 * v3-A1: シグナルドット行（セル最下部の細い行）
 * 視覚言語は signals_calendar v2 と完全同一:
 *   色 = パターン（v4矢印色） / 形 = 方向（▲BUY ▼SELL） / pass_all=FALSE は opacity 0.3
 * ============================================================ */
.cell .fires-row {
  display: flex; flex-wrap: wrap; align-content: flex-start;
  gap: 0 2px; padding: 1px 4px;
  background: rgba(0,0,0,0.35);
  overflow: hidden;
}
.fire-dot {
  font-size: 10px; line-height: 1.1;
  text-shadow: 0 1px 2px rgba(0,0,0,0.7);
}
.fire-dot.suppressed { opacity: 0.3; }   /* pass_all=FALSE: 実機なら見えなかった発火 */
.fire-dot.satfold { text-decoration: underline dotted rgba(200,210,230,0.45); } /* JST土曜分（金曜セル併載） */

/* v3-Step2 B2: 9本フィルター デフォルトON（pass_all=TRUE のみ表示、トグルで全発火） */
#tab-calendar:not(.show-all-fires) .fire-dot.suppressed { display: none; }
#tab-calendar:not(.show-all-fires) .fires-row.all-suppressed { display: none; }
.fires-filter-bar {
  display: flex; align-items: center; gap: 12px; flex-wrap: wrap;
  margin: 0 0 12px; padding: 7px 12px;
  background: #0a1320; border: 1px solid #1a2a44; border-radius: 4px;
  font-size: 11px; color: #8aa8ce;
}
.fires-filter-bar label { cursor: pointer; user-select: none; display: flex; align-items: center; gap: 6px; }
.fires-filter-bar input { cursor: pointer; }
.fires-filter-bar .ff-note { font-size: 9px; color: #4a6a8a; }

/* v3-Step2 B3: 過去月（トレードログ開始前・発火のみの期間）の折りたたみ */
details.past-months { margin-bottom: 20px; }
details.past-months > summary {
  cursor: pointer; list-style: none; user-select: none;
  padding: 9px 14px; background: #0a1320; border: 1px solid #1a2a44;
  border-radius: 4px; font-size: 11px; color: #8aa8ce; letter-spacing: .04em;
}
details.past-months > summary::-webkit-details-marker { display: none; }
details.past-months > summary:hover { background: #0e1a2a; }
details.past-months[open] > summary { background: #0e1a2a; color: #b0c8e8; margin-bottom: 14px; }
details.past-months > summary .pm-open { display: none; }
details.past-months[open] > summary .pm-open { display: inline; }
details.past-months[open] > summary .pm-closed { display: none; }

/* v3-A2: セルクリック → ドロワー（カレンダータブのみ） */
#tab-calendar .cell.has-fires, #tab-calendar .cell.has-trade { cursor: pointer; }
#tab-calendar .cell.has-fires:hover, #tab-calendar .cell.has-trade:hover { border-color: #2a5a9a; }
#tab-calendar .cell.drill-open { border-color: #4a90e2; box-shadow: inset 0 0 0 1px #4a90e2; }

/* ===== v3-A2 ドリルダウンドロワー（signals_calendar v2 流用） ===== */
#drill {
  position: fixed; top: 0; right: 0; bottom: 0; width: 400px;
  background: #08111c; border-left: 1px solid #1a3454;
  box-shadow: -6px 0 18px rgba(0,0,0,0.55);
  z-index: 100; display: none; flex-direction: column;
}
#drill.open { display: flex; }
#drill .drill-head {
  display: flex; justify-content: space-between; align-items: center;
  padding: 12px 14px; border-bottom: 1px solid #1a2a44;
}
#drill .drill-title { font-size: 13px; color: #b0c8e8; font-weight: 600; letter-spacing: .04em; }
#drill .drill-close {
  background: #0e1a2a; color: #b8d0ee; border: 1px solid #1a3454;
  border-radius: 3px; padding: 3px 10px; font-size: 11px; cursor: pointer; font-family: inherit;
}
#drill .drill-close:hover { background: #142844; }
#drill .drill-note { font-size: 9px; color: #4a6a8a; padding: 6px 14px 0; line-height: 1.5; }
#drill .drill-body { flex: 1; overflow-y: auto; padding: 10px 14px 20px; }

/* 発火カード */
.fire-card {
  border: 1px solid #1a2a44; border-radius: 6px;
  background: #0a1320; margin-bottom: 10px; padding: 10px 12px;
}
.fire-card.suppressed { opacity: 0.55; border-style: dashed; }
.fire-card .fc-head {
  display: flex; align-items: center; gap: 8px; margin-bottom: 6px;
  font-size: 12px; font-weight: 700;
}
.fire-card .fc-pat {
  padding: 1px 7px; border-radius: 3px; font-size: 11px;
  color: #05090f; letter-spacing: .03em;
}
.fire-card .fc-time { color: #c8d8e8; font-weight: 600; }
.fire-card .fc-server { color: #4a6a8a; font-size: 9.5px; font-weight: 400; }
.fire-card .fc-pass { margin-left: auto; font-size: 10px; font-weight: 700; }
.fire-card .fc-pass.ok { color: #5ad88a; }
.fire-card .fc-pass.ng { color: #c87a4a; }
.fire-card .fc-row { font-size: 10.5px; color: #8abaee; line-height: 1.7; }
.fire-card .fc-row .k { color: #4a6a8a; margin-right: 3px; }
.fire-card .fc-row .v { color: #c8d8e8; margin-right: 9px; }
.fire-card .fc-row .raw { color: #4a6a8a; font-size: 9px; }
.fire-card .fc-filters { font-size: 10px; margin-top: 4px; }
.fire-card .fc-filters.hit { color: #e0a060; }
.fire-card .fc-filters.nohit { color: #4a8a6a; }
/* MFE/MAE ステップバー（シグナルカード/トレードカード共用） */
.mm-steps { margin-top: 7px; }
.mm-steps .mm-ttl { font-size: 9px; color: #4a6a8a; margin-bottom: 3px; letter-spacing: .04em; }
.mm-row { display: grid; grid-template-columns: 26px 1fr 1fr; gap: 0 6px; align-items: center; margin-bottom: 2px; }
.mm-row .mm-h { font-size: 9px; color: #4a6a8a; text-align: right; font-variant-numeric: tabular-nums; }
.mm-bar-wrap { position: relative; height: 10px; background: rgba(0,0,0,0.35); border-radius: 1px; }
.mm-bar { position: absolute; top: 1px; bottom: 1px; border-radius: 1px; }
.mm-bar.mae { right: 0; background: linear-gradient(90deg, rgba(239,96,96,0.85), rgba(239,96,96,0.5)); }
.mm-bar.mfe { left: 0; background: linear-gradient(90deg, rgba(90,184,255,0.5), rgba(90,184,255,0.85)); }
.mm-num { position: absolute; top: -1px; font-size: 8.5px; font-variant-numeric: tabular-nums; }
.mm-bar-wrap.w-mae .mm-num { left: 3px; color: #ef9090; }
.mm-bar-wrap.w-mfe .mm-num { right: 3px; color: #8ac8ff; }
.mm-legend { display: flex; gap: 10px; font-size: 8.5px; color: #4a6a8a; margin-top: 2px; }
.mm-legend .mfe-k { color: #8ac8ff; }
.mm-legend .mae-k { color: #ef9090; }

/* 実トレードカード（シグナルカードの下、トレード日のみ） */
.trade-sec-hdr {
  display: flex; align-items: center; gap: 8px;
  margin: 16px 0 8px; font-size: 10px; font-weight: 700;
  color: #d8b060; letter-spacing: .08em;
}
.trade-sec-hdr::before, .trade-sec-hdr::after {
  content: ""; flex: 1; height: 1px; background: #4a3c1a;
}
.trade-card {
  border: 1px solid #4a3c1a; border-radius: 6px;
  background: #0e0c07; margin-bottom: 10px; padding: 10px 12px;
}
.trade-card .tc-head {
  display: flex; align-items: center; gap: 8px; margin-bottom: 6px;
  font-size: 12px; font-weight: 700;
}
.trade-card .tc-dir {
  padding: 1px 7px; border-radius: 3px; font-size: 11px;
  color: #ffd060; background: rgba(255,208,96,0.10);
  border: 1px solid #6a5a2a; letter-spacing: .03em;
}
.trade-card .tc-time { color: #c8d8e8; font-weight: 600; }
.trade-card .tc-pips {
  margin-left: auto; font-size: 12px; font-weight: 700;
  font-variant-numeric: tabular-nums;
}
.trade-card .tc-pips.pos { color: #5ab8ff; }
.trade-card .tc-pips.neg { color: #ef6060; }
.trade-card .tc-pips.flat { color: #8a9ab0; }
.trade-card .tc-meta { font-size: 10.5px; color: #c8d8e8; display: flex; gap: 12px; flex-wrap: wrap; }
.trade-card .tc-meta .k { color: #6a5a3a; margin-right: 3px; }
.trade-card .tc-tag { color: #d8c890; }
.trade-card .tc-tag.other { color: #5a6a7a; }
.trade-card .tc-reason { margin-top: 8px; font-size: 10px; }
.trade-card .tc-reason summary {
  cursor: pointer; color: #6a5a3a; user-select: none; letter-spacing: .04em;
}
.trade-card .tc-reason summary:hover { color: #a89060; }
.trade-card .tc-reason[open] summary { color: #c8a860; }
.trade-card .tc-reason-body {
  margin-top: 6px; color: #a8b8cc; line-height: 1.7;
  white-space: pre-wrap; background: rgba(0,0,0,0.35);
  padding: 8px 10px; border-radius: 4px;
}

/* ===== v3-mobile: iPhone縦持ち 最小限レスポンシブ（2026-06-22 あろさん要望・v2） ===== */
@media (max-width: 640px) {
  body { padding: 6px; }
  /* ① タップ窓（ドリルドロワー）全画面化：右400px固定だとiPhone幅で読めない問題の解消 */
  #drill { width: 100%; left: 0; right: 0; }
  #drill .drill-head { position: sticky; top: 0; background: #08111c; z-index: 3; }
  /* ② 5列を画面幅にフィット（横スクロール廃止＝見切れ解消 / padding・gap詰めでセル幅を確保） */
  .month { padding: 6px; }
  .week-cells { gap: 2px; }
  /* ③ 円グラフ 2列→1列 */
  .pie-grid { grid-template-columns: 1fr; }
  .filter-bar { flex-wrap: wrap; }
  /* ④ 凡例(legend)をカレンダーの下へ：DOMは動かさずCSS orderで最後尾に送る（PCは従来どおり上）。
        .active 付きで詳細度を効かせ、タブ非表示(display:none)を壊さない */
  #tab-calendar.active { display: flex; flex-direction: column; }
  #tab-calendar.active .legend { order: 10; }
  /* ⑤ セル内テキストの窮屈さ緩和（5列フィットで狭くなった分フォントを詰める） */
  .cell { font-size: 9px; }
  /* ⑥ MAE/MFE・値動きレンジの数値をセル幅に収める（はみ出し＝見切れ解消） */
  .cell .h4-main .mfe-mae-nums { font-size: 10px; gap: 5px; }
  .cell .h4-main .range-nums { font-size: 9px; gap: 6px; }
  .cell .h4-main .mfe-mae-box, .cell .h4-main .range-box { padding: 0 3px; }
  /* ⑦ シグナル行・結果(トレード)行を1行に収める（はみ出し防止・枠内に収める） */
  .cell .signal, .cell .result { overflow: hidden; white-space: nowrap; }
  .cell .signal .tag { font-size: 7px; padding: 1px 3px; }
  .cell .result { font-size: 9px; gap: 3px; padding: 1px 4px; }
  .cell .result .lot-info { font-size: 7px; }
}
</style></head><body>
""")

html.append(f'<h1>DAILY RESEARCH CALENDAR — マニ v3 (v2ベース+シグナル統合)</h1>')
virtual_count = len(daily_mfe_mae_map)
daily_agg_count = len(daily_agg_map)
html.append(f'<div class="sub">入力: {src.name} / 日次集計: {daily_agg_count}日 / 仮想MFE/MAE: {virtual_count}日 / 期間: {all_dates[0]:%Y-%m-%d} 〜 {all_dates[-1]:%Y-%m-%d} / 生成: {datetime.now():%Y-%m-%d %H:%M} / 全体比正規化基準(p95): {BAR_NORM_BASE:.0f} USD / 最大観測値: {BAR_MAX_OBS:.0f} USD'
            f' / <span id="v3-fire-summary" data-pass="{n_fires_pass}" data-supp="{n_fires_supp}" data-total="{n_fires_total}">'
            f'シグナル発火: {n_fires_pass}件 (pass_all のみ表示 / 抑制 {n_fires_supp}件 非表示)</span>'
            f' {all_fire_cell_dates[0]:%Y-%m-%d}〜{all_fire_cell_dates[-1]:%Y-%m-%d}</div>')

# ===== v2.0 タブナビゲーション =====
html.append('<div class="tabs">')
html.append('<button class="tab-btn" data-tab="calendar">カレンダー</button>')
html.append('<button class="tab-btn" data-tab="overview">全体像</button>')
html.append('<button class="tab-btn" data-tab="detail">詳細分析</button>')
html.append('</div>')

# ===== カレンダータブ開始 =====
html.append('<div class="tab-pane" id="tab-calendar">')

# ===== 凡例 =====
html.append('<div class="legend">')
# v0.8: H4 主役の凡例を「合成スコア段階」に更新
html.append('<div class="grp"><span class="ttl">主役 H4 (色相=DI方向 / 明度+彩度+グロウ=H1×H4 合成スコア):</span>')
html.append('<span class="sw" style="background:rgb(30,30,34);"></span>凪 (&lt;15)')
html.append('<span class="sw" style="background:hsl(220,55%,14%);"></span>15+')
html.append('<span class="sw" style="background:hsl(220,65%,22%);"></span>25+')
html.append('<span class="sw" style="background:hsl(220,80%,38%);box-shadow:0 0 5px hsla(220,80%,50%,0.35);"></span>40+')
html.append('<span class="sw" style="background:hsl(220,88%,44%);box-shadow:0 0 7px hsla(220,88%,55%,0.45);"></span>55+')
html.append('<span class="sw" style="background:hsl(220,95%,50%);box-shadow:0 0 10px hsla(220,95%,60%,0.55);"></span>70+')
html.append('<span class="sw" style="background:hsl(0,80%,38%);box-shadow:0 0 5px hsla(0,80%,50%,0.35);margin-left:8px;"></span>DI- 40+ (赤系)')
html.append('</div>')
html.append('<div class="grp"><span class="ttl">構造ラベル:</span>')
for phase, (cls, lbl) in PHASE_BADGE.items():
    html.append(f'<span class="ph {cls}">{lbl}</span>')
html.append('</div>')
# v0.8: D1 帯凡例を概念整理後の4パターン表示に
html.append('<div class="grp"><span class="ttl">D1 帯 (色=ATR Phase / 方向はラベル文字):</span>')
html.append('<span class="d1band" style="background:rgba(235,175,55,0.45);"></span>BU 拡張(琥珀) ')
html.append('<span class="d1band" style="background:rgba(150,110,205,0.40);"></span>PD 収縮(紫) ')
html.append('<span class="d1band" style="background:rgba(120,120,135,0.28);"></span>RANGE (灰/ADX&lt;18) ')
html.append('<span style="opacity:0.55;font-size:9px;display:block;margin-top:4px;">※色=値幅局面(BU/PD)。方向(UP/DOWN)はラベル文字で表示。赤青はDI/ADX(方向)専用に分離。</span>')
html.append('</div>')
# v1.1: トレード日 中央 MFE/MAE バー凡例（全体比正規化に統一）
html.append('<div class="grp"><span class="ttl">トレード日 中央 (H4 48h固定):</span>')
html.append('<span style="color:#5ab8ff;font-weight:700;">伸 MFE</span>')
html.append('<span style="color:#ef6060;font-weight:700;">踏 MAE</span>')
html.append(f'<span style="opacity:0.6;font-size:9px;">USD建て / バー長=全期間p95 {BAR_NORM_BASE:.0f}USD で正規化(満タン=規模大)</span>')
html.append('</div>')
# v1.3: 非トレード日 値動きレンジバー凡例（1本バー、方向中立）
html.append('<div class="grp"><span class="ttl">非トレード日 中央 (値動きレンジ 48h, JST14:00基準):</span>')
html.append('<span style="font-size:9px;font-weight:700;opacity:0.7;">仮</span>')
html.append('<span style="font-size:10px;color:rgba(140,200,240,0.92);font-weight:700;">↑上 N</span>')
html.append('<span style="font-size:10px;color:rgba(230,140,140,0.88);font-weight:700;">↓下 N</span>')
html.append('<span style="font-size:9px;opacity:0.7;">中央tickから左右に伸びる1本バー</span>')
html.append('<span style="opacity:0.55;font-size:9px;display:block;margin-top:4px;">※「上方向の最大伸び / 下方向の最大伸び」の事実。BUY/SELLの立場依存ではない値動きレンジ表示。トレード日のバーと同じ全体比正規化基準。</span>')
html.append('</div>')
# v1.4: トレード日タグ凡例（意思決定タグ + ATR Ratio）
html.append('<div class="grp"><span class="ttl">トレード日タグ (シグナル行):</span>')
html.append('<span class="ph" style="background:rgba(255,255,255,0.08);color:rgba(220,228,240,0.78);font-weight:600;">PAT-A</span>')
html.append('<span style="font-size:9px;opacity:0.7;">意思決定タグ（反省列：PAT-A/B/C/D/ATR収束底）</span>')
html.append('<span class="ph" style="background:rgba(255,255,255,0.04);color:rgba(180,188,200,0.55);font-weight:400;opacity:0.75;">その他</span>')
html.append('<span style="font-size:9px;opacity:0.7;">構造化外の判断（控えめ表示）</span>')
html.append('<span class="ph" style="background:rgba(255,255,255,0.05);color:rgba(200,210,225,0.7);font-weight:500;">ATR 1.4</span>')
html.append('<span style="font-size:9px;opacity:0.7;">H1 ATR16/32 比率（計算値）</span>')
html.append('<span style="opacity:0.55;font-size:9px;display:block;margin-top:4px;">※意思決定タグはトレードログ「反省」列から取得（あろさんが入った時の判断の正本）。事実情報のみ、色フラット、評価ラベル化なし。</span>')
html.append('</div>')
# v3-A1: シグナルドット行の凡例（視覚言語は signals_calendar v2 と同一）
html.append('<div class="grp"><span class="ttl">シグナル発火 (セル最下行 / 色=パターン=v4矢印色 / 形=方向):</span>')
for p in PATTERNS:
    html.append(f'<span style="font-size:11px;"><span style="color:{PATTERN_COLORS[p]["BUY"]};">▲</span>'
                f'<span style="color:{PATTERN_COLORS[p]["SELL"]};">▼</span> {p}</span>')
html.append('<span style="font-size:11px;opacity:0.3;color:#FFD700;">▲</span>'
            '<span style="font-size:9px;">pass_all=FALSE（フィルター抑制 = 実機では見えなかった発火。デフォルト非表示・「全発火表示」トグルで薄表示）</span>')
html.append('<span style="font-size:11px;color:#FFD700;text-decoration:underline dotted rgba(200,210,230,0.45);">▲</span>'
            '<span style="font-size:9px;">JST土曜発火（=サーバー金曜深夜、金曜セルに併載）</span>')
html.append('<span style="opacity:0.55;font-size:9px;display:block;margin-top:4px;">※発火/トレードのある日はセルクリックで詳細ドロワー（シグナルカード + 実トレードカード、MFE/MAE 12/24/36/48h）。</span>')
html.append('</div>')
html.append('</div>')

# ===== v3-Step2 B2: 9本フィルタートグル（デフォルト = pass_all のみ表示） =====
html.append('<div class="fires-filter-bar">'
            '<label><input type="checkbox" id="v3-show-suppressed">'
            f' 全発火表示（抑制 {n_fires_supp} 件を薄表示で追加）</label>'
            f'<span class="ff-note">デフォルト = pass_all のみ {n_fires_pass} 件（v4 実機チャートで見えた発火）。ドット・ドロワー両方に連動。</span>'
            '</div>')

# ===== v3-Step2 B3: 期間のトレードログ基準化 =====
# デフォルト表示 = トレード記録開始月（2026-03）以降 かつ 直近6ヶ月上限。
# それ以前（発火のみの期間）は <details> 折りたたみ（展開で発火全件、DOM には常に存在）
_last_month = end_d.replace(day=1)
_six_floor_idx = _last_month.year * 12 + (_last_month.month - 1) - 5  # 直近6ヶ月の下限
_six_floor = date(_six_floor_idx // 12, _six_floor_idx % 12 + 1, 1)
_trade_first_month = all_dates[0].replace(day=1)
default_start_month = max(_trade_first_month, _six_floor)
past_months = [m for m in month_iter(start, end) if m < default_start_month]

# ===== 月ループ =====
# v3-A1 検証用カウンタ（389全件描画・欠落ゼロ・重複ゼロの検証）
emitted_dot_count = 0
emitted_dot_fids = []
emitted_fold_count = 0
emitted_supp_dot_count = 0  # v3-Step2 B2 検証用
_in_past_fold = False  # v3-Step2 B3: 過去月 <details> ラッパー状態
for m_start in reversed(list(month_iter(start, end))):  # v3: 最新月を先頭に（降順表示・あろさん要望 2026-06-22）
    # v3-Step2 B3: 過去月の折りたたみ開始/終了（降順では過去月が末尾に連続→ループ後の閉じ 2343-2345 が機能）
    if m_start < default_start_month and not _in_past_fold:
        html.append('<details class="past-months"><summary>'
                    '<span class="pm-closed">過去を表示 ▸</span><span class="pm-open">過去を隠す ▾</span>'
                    f' {past_months[0]:%Y-%m}〜{past_months[-1]:%Y-%m}'
                    f'（トレードログ開始前・発火のみの期間 / {len(past_months)}ヶ月）</summary>')
        _in_past_fold = True
    elif m_start >= default_start_month and _in_past_fold:
        html.append('</details>')
        _in_past_fold = False
    weeks_list = month_weekdays(m_start.year, m_start.month)
    # v3 fix (2026-07-01): 未来の週は描画しない。当月に入った直後、まだ来ていない週
    #   （例: 7/6〜7/31）を空セルで並べると「バーが出ていない＝壊れている」ように見える
    #   （あろさん指摘: 枠は3日まであるのに今日はまだ1日）。週頭(月曜)が今日以前の週だけ残す。
    #   過去月は全週が該当するため無影響。当月のみ現在週で打ち切られる。
    _today = date.today()
    weeks_list = [w for w in weeks_list if w and w[0] <= _today]
    month_trades = [t for d, ts in trade_by_date.items() if d.year==m_start.year and d.month==m_start.month for t in ts]
    pl_sum = sum(t["pl"] for t in month_trades)
    n_win = sum(1 for t in month_trades if t["pl"]>0)
    n_loss = sum(1 for t in month_trades if t["pl"]<0)

    html.append('<div class="month">')
    html.append(f'<div class="month-title">{m_start.year}年 {m_start.month}月</div>')
    html.append(f'<div class="month-stats">トレード {len(month_trades)}件 (勝{n_win} / 負{n_loss}) — 損益 ¥{pl_sum:+,.0f}</div>')

    # 曜日ヘッダ
    html.append('<div class="dow-row">')
    for dow in ["月","火","水","木","金"]:
        html.append(f'<div class="dow">{dow}</div>')
    html.append('</div>')

    for week_days in weeks_list:
        # ----- D1 帯（週内代表値で帯色決定。同週内は基本同じ） -----
        first_in_month_day = next((d for d in week_days if d.month == m_start.month), None)
        if first_in_month_day:
            d1_rec = get_rec(first_in_month_day)
            d1_band = d1_band_color(d1_rec)
        else:
            d1_band = None

        html.append('<div class="week-group">')
        if d1_band:
            html.append(f'<div class="d1-band" style="background:{d1_band["color"]};">'
                       f'<span>{d1_band["label"]}</span>'
                       f'<span class="d1-adx">{d1_band["adx_txt"]}</span>'
                       f'</div>')
        else:
            html.append('<div class="d1-band empty"><span>D1 —</span></div>')

        # ----- セル群 -----
        html.append('<div class="week-cells">')
        for d in week_days:
            is_outside = d.month != m_start.month
            is_future = d > date.today()  # v3 fix (2026-07-01): 今日より先＝未来（まだ来てない）
            rec = get_rec(d)
            h4 = h4_bg_style(rec)
            h1 = h1_bg_style(rec)
            phase = (rec or {}).get("h4_phase_auto", "—")
            ph_tuple = PHASE_BADGE.get(phase)

            classes = ["cell"]
            if is_outside: classes.append("outside")
            if is_future: classes.append("future")  # 未来日=淡色（欠損ではなく「これから」）
            if phase == "凪離脱": classes.append("leave-warn")

            trades = trade_by_date.get(d, [])

            # v3-A1: シグナル発火（outside セルには描画しない = 隣月との二重描画防止 → 389件保証）
            day_fires = fires_by_cell.get(d, []) if not is_outside else []
            if day_fires:
                classes.append("has-fires")
            if trades and not is_outside:
                classes.append("has-trade")

            # ツールチップ
            tip_parts = [f"{d:%Y-%m-%d} ({['月','火','水','木','金','土','日'][d.weekday()]})"]
            if rec:
                # v0.8: 合成スコアを最初に（検証用にADX生値も併記）
                if h4.get("score") is not None:
                    tip_parts.append(f"スコア={h4['score']:.1f}")
                # v1.2: H1/H4 の mean(背景) と max(スコア) を分離表示
                if rec.get("h1_avg_adx") is not None:
                    h1_max = rec.get("h1_adx_max")
                    if h1_max is not None:
                        tip_parts.append(f"H1 ADX mean/max={rec['h1_avg_adx']:.1f}/{h1_max:.1f}")
                    else:
                        tip_parts.append(f"H1 ADX={rec['h1_avg_adx']:.1f}")
                if rec.get("h4_adx46") is not None:
                    h4_max = rec.get("h4_adx_max")
                    if h4_max is not None:
                        tip_parts.append(f"H4 ADX46 mean/max={rec['h4_adx46']:.1f}/{h4_max:.1f}")
                    else:
                        tip_parts.append(f"H4 ADX46={rec['h4_adx46']:.1f}")
                if rec.get("h4_di_spread") is not None:
                    tip_parts.append(f"H4 DI spread={rec['h4_di_spread']:+.1f}")
                if rec.get("d1_pattern"):
                    tip_parts.append(f"D1 pattern={rec['d1_pattern']}")
                if rec.get("d1_adx22") is not None:
                    tip_parts.append(f"D1 ADX22={rec['d1_adx22']:.1f}")
                if phase and phase != "—":
                    tip_parts.append(f"H4 Phase={phase}")
                # 日次データソース表記（デバッグ用）
                if rec.get("_source") == "daily_agg":
                    tip_parts.append("src=日次CSV")
            # v0.5: MAE/MFE をツールチップに追記（48h固定/H4）
            if trades:
                mfes = [t["h4_mfe_48h"] for t in trades if t.get("h4_mfe_48h") is not None]
                maes = [t["h4_mae_48h"] for t in trades if t.get("h4_mae_48h") is not None]
                if mfes:
                    tip_parts.append(f"H4 MFE 48h={max(mfes):.1f} USD")
                if maes:
                    tip_parts.append(f"H4 MAE 48h={max(maes):.1f} USD")
            # v1.0: 仮想 48h MFE/MAE をツールチップに追記（非トレード日のみ、トレード日は実測優先）
            if not trades:
                virtual_tip = daily_mfe_mae_map.get(d)
                if virtual_tip:
                    if virtual_tip["entry_price"] is not None:
                        tip_parts.append(f"仮想エントリー(JST14:00) {virtual_tip['entry_price']:.2f}")
                    if virtual_tip["buy_mfe"] is not None:
                        tip_parts.append(f"BUY 48h MFE/MAE={virtual_tip['buy_mfe']:.1f}/{virtual_tip['buy_mae']:.1f}")
                    if virtual_tip["sell_mfe"] is not None:
                        tip_parts.append(f"SELL 48h MFE/MAE={virtual_tip['sell_mfe']:.1f}/{virtual_tip['sell_mae']:.1f}")
                    if virtual_tip["bars_traced"] is not None and virtual_tip["bars_traced"] < 48:
                        tip_parts.append(f"追跡バー={virtual_tip['bars_traced']:.0f}/48 (期間中)")
            # v3-A1: シグナル発火サマリをツールチップに追記（詳細はドロワー）
            if day_fires:
                _n_pass_d = sum(1 for fr in day_fires if fr["pass_all"])
                tip_parts.append(f"シグナル発火 {len(day_fires)}件 (pass {_n_pass_d}/抑制 {len(day_fires)-_n_pass_d}) → クリックで詳細")
            title = " | ".join(tip_parts)

            html.append(f'<div class="{" ".join(classes)}" data-date="{d:%Y-%m-%d}" title="{title}">')

            # 日付ヘッダ + フェーズバッジ
            html.append('<div class="day-hdr">')
            html.append(f'<span>{d.day}</span>')
            if ph_tuple:
                ph_cls, ph_lbl = ph_tuple
                html.append(f'<span class="ph-badge {ph_cls}">{ph_lbl}</span>')
            html.append('</div>')

            # H4 主役レーン
            # v0.5: トレード日は MAE/MFE 中央主役、スコアは右上小フォントに降格
            # 非トレード日は中央にスコア大表示
            # v0.8: ADX値 → H1×H4 合成スコアに置換、DI spread 数値表示を削除
            adx_val = rec.get("h4_adx46") if rec else None
            score = h4.get("score")
            score_txt = f"{score:.0f}" if score is not None else "—"
            h4_glow = h4.get("glow", "")
            html.append(f'<div class="h4-main" style="background:{h4["bg"]}; border:1px solid {h4["border"]};{h4_glow}">')
            # v0.8: di-mark（DI spread数値）削除。色相で既に方向情報を表現済み

            if trades:
                # トレード日: MAE/MFE を中央主役、スコアは右上に小さく降格
                # 複数トレード日は最大 MFE と最大 MAE を集約（規模感は保守的に max を取る）
                mfes = [t["h4_mfe_48h"] for t in trades if t.get("h4_mfe_48h") is not None]
                maes = [t["h4_mae_48h"] for t in trades if t.get("h4_mae_48h") is not None]
                mfe_v = max(mfes) if mfes else None
                mae_v = max(maes) if maes else None

                # v3-A3: 右上の SC スコア数値テキストは削除（あろさん明言「ほとんど見ない」）
                #        スコア値はホバー title 内に残存（tip_parts の「スコア=」）

                if mfe_v is not None or mae_v is not None:
                    # v1.1: 全期間 p95 基準で全体比正規化（仮想と実の並列読み統一）
                    # 旧: 固定 BAR_MAX=300 / 新: BAR_NORM_BASE (CSV 全期間 p95)
                    mfe_pct = min(100, (mfe_v or 0) / BAR_NORM_BASE * 100) * 0.5  # 半分の幅で左右配分
                    mae_pct = min(100, (mae_v or 0) / BAR_NORM_BASE * 100) * 0.5
                    mfe_txt = f"{mfe_v:.0f}" if mfe_v is not None else "—"
                    mae_txt = f"{mae_v:.0f}" if mae_v is not None else "—"
                    html.append('<div class="mfe-mae-box">')
                    html.append('<div class="mfe-mae-nums">')
                    html.append(f'<span><span class="mfe-mae-lbl">伸</span><span class="mfe-num">{mfe_txt}</span></span>')
                    html.append(f'<span><span class="mfe-mae-lbl">踏</span><span class="mae-num">{mae_txt}</span></span>')
                    html.append('</div>')
                    html.append('<div class="mfe-mae-bar">')
                    html.append(f'<div class="bar-mae" style="width:{mae_pct:.1f}%;"></div>')
                    html.append(f'<div class="bar-mfe" style="width:{mfe_pct:.1f}%;"></div>')
                    html.append('<div class="center-tick"></div>')
                    html.append('</div>')
                    html.append('</div>')
                else:
                    # enriched 未マッチのトレード日（48h追跡欠損）
                    html.append('<span class="adx-val" style="font-size:14px;opacity:0.5;">追跡欠損</span>')
            else:
                # 非トレード日 v1.3: 値動きレンジバー（あろさんフィードバック 2026-06-10）
                # データ源: daily_mfe_mae_48h.csv (JST 14:00 仮想エントリー)
                # 設計:
                #   - 旧 BUY/SELL 2本バー → 1本の値動きレンジバーに統合
                #   - BUY MFE = SELL MAE（上方向の伸び）/ BUY MAE = SELL MFE（下方向の伸び）→ 同じ情報の二重表示を解消
                #   - 1本バー: 右=上方向の最大伸び / 左=下方向の最大伸び / 中央 tick=entry
                #   - 数値表示: ↑上 N / ↓下 N（方向中立）
                # 番人観点: 「BUY 視点で利益/損失」のような立場依存ラベル化なし、純粋な値動き事実情報
                # 景色（背景濃淡+色相）が主役のまま、レンジは opacity 0.78 で補助情報感
                virtual = daily_mfe_mae_map.get(d) if not is_outside else None
                if virtual and (virtual["buy_mfe"] is not None or virtual["sell_mfe"] is not None):
                    # v3-A3: 右上 SC スコア数値テキスト削除（title 内に残存）
                    # 左上「仮」マーク（仮想エントリーの明示）
                    html.append('<span class="virtual-mark">仮</span>')
                    # 値動きレンジ計算:
                    #   上方向の最大伸び = buy_mfe（= sell_mae、同値のはず）
                    #   下方向の最大伸び = buy_mae（= sell_mfe、同値のはず）
                    # 厳密には浮動小数誤差で微差あり得るので max() で安全側に取る
                    up_vals = [v for v in (virtual["buy_mfe"], virtual["sell_mae"]) if v is not None]
                    dn_vals = [v for v in (virtual["buy_mae"], virtual["sell_mfe"]) if v is not None]
                    up_v = max(up_vals) if up_vals else None
                    dn_v = max(dn_vals) if dn_vals else None
                    # 全体比正規化（トレード日と同じ BAR_NORM_BASE、左右合計で 100%）
                    up_pct = min(100, (up_v or 0) / BAR_NORM_BASE * 100) * 0.5
                    dn_pct = min(100, (dn_v or 0) / BAR_NORM_BASE * 100) * 0.5
                    up_txt = f"{up_v:.0f}" if up_v is not None else "—"
                    dn_txt = f"{dn_v:.0f}" if dn_v is not None else "—"

                    html.append('<div class="range-box">')
                    html.append('<div class="range-nums">')
                    html.append(f'<span><span class="rn-lbl">↑上</span><span class="rn-up">{up_txt}</span></span>')
                    html.append(f'<span><span class="rn-lbl">↓下</span><span class="rn-down">{dn_txt}</span></span>')
                    html.append('</div>')
                    html.append('<div class="range-bar">')
                    html.append(f'<div class="rb-down" style="width:{dn_pct:.1f}%;"></div>')
                    html.append(f'<div class="rb-up" style="width:{up_pct:.1f}%;"></div>')
                    html.append('<div class="rb-center-tick"></div>')
                    html.append('</div>')
                    html.append('</div>')
                else:
                    # データ欠損日（CSV期間外、休場日、データ未取得）は中央クリーン
                    # v3-A3: 右上 SC スコア数値テキスト削除（title 内に残存）
                    pass

            html.append('</div>')

            # H1 補助レーン
            html.append('<div class="h1-aux">')
            html.append(f'<div class="h1-bar" style="background:{h1["bg"]};"></div>')
            html.append(f'<span class="h1-txt">{h1["label"]}</span>')
            html.append('</div>')

            # 区切り
            html.append('<div class="divider"></div>')

            # シグナル（暫定: トレードがあった日は ▲ マーク、無ければ ·）
            # 真のシグナル発火データは v4 mq5 ログ整備待ち
            # v1.4: 意思決定タグを「反省」列から取得（あろさんフィードバック 2026-06-10）
            #   - 構造化タグ (PAT-A/B/C/D/ATR収束底) → 通常表示
            #   - 「その他」 → 控えめ表示（事実情報として残す、評価ラベル化なし）
            #   - 空欄 → タグなし
            #   - 複数トレード日で複数タグあれば ',' 区切り
            #   - 番人観点: 色フラット、PAT別色分け禁止、評価ラベルなし
            if trades:
                sig_mark = '▲'
                sig_cls = "signal fired"
                # 構造化タグ vs その他 を分けて収集（順序は出現順を保つため list で重複排除）
                structured = []
                others = []
                seen = set()
                for t in trades:
                    tg = t.get("decision_tag")
                    if not tg or tg in seen:
                        continue
                    seen.add(tg)
                    if tg == "その他":
                        others.append(tg)
                    else:
                        structured.append(tg)
                atrs = [t.get("h1_atr_ratio") for t in trades if t.get("h1_atr_ratio") is not None]
                atr_v = sum(atrs) / len(atrs) if atrs else None
                atr_txt = f"ATR{atr_v:.2f}" if atr_v is not None else ""
                tag_html = ""
                if structured:
                    tag_html += f'<span class="tag">{",".join(structured)}</span>'
                if others:
                    tag_html += f'<span class="tag other">{",".join(others)}</span>'
                if atr_txt:
                    tag_html += f'<span class="tag atr">{atr_txt}</span>'
                html.append(f'<div class="{sig_cls}">{sig_mark}{tag_html}</div>')
            else:
                sig_mark = '·'
                sig_cls = "signal"
                html.append(f'<div class="{sig_cls}">{sig_mark}</div>')

            # 結果 — v0.6: 背景=ポジション方向 / 文字色=損益
            if trades:
                total_pl = sum(t["pl"] for t in trades)
                lots = sum(t["lot"] for t in trades)
                stars = ",".join(sorted(set(t["star"] for t in trades if t["star"])))
                # ポジション方向決定: 全BUY/全SELL/混在(ロット加重多数派)
                buy_lots = sum(t["lot"] for t in trades if t["order"] == "買い")
                sell_lots = sum(t["lot"] for t in trades if t["order"] == "売り")
                # v0.7: 建値(損益0)は方向背景より「建値専用の薄背景」を優先
                # → 建値の存在をより目立たなくする
                if total_pl == 0:
                    dir_cls = "tr-zero"
                elif buy_lots > sell_lots:
                    dir_cls = "tr-buy"
                elif sell_lots > buy_lots:
                    dir_cls = "tr-sell"
                else:
                    dir_cls = "tr-zero"  # ロット完全拮抗 (稀)
                # 損益 → 文字色クラス
                if total_pl > 0:
                    pl_cls = "pl-win"
                elif total_pl < 0:
                    pl_cls = "pl-loss"
                else:
                    pl_cls = "pl-zero"
                sign = "+" if total_pl > 0 else ""
                star_txt = f" ★{stars}" if stars else ""
                pos_cnt = f'<span class="pos-cnt">×{len(trades)}</span>' if len(trades) > 1 else ""
                # v0.7: 建値は「建」ラベル + 0表示で目立たなく
                if total_pl == 0:
                    html.append(
                        f'<div class="result tr-zero">'
                        f'<span class="zero-lbl">建値</span>'
                        f'<span class="{pl_cls}">0</span>'
                        f'<span class="lot-info">lot{lots:.2f}{star_txt}</span>'
                        f'{pos_cnt}'
                        f'</div>'
                    )
                else:
                    html.append(
                        f'<div class="result {dir_cls}">'
                        f'<span class="{pl_cls}">{sign}{int(total_pl/1000):+d}k</span>'
                        f'<span class="lot-info">lot{lots:.2f}{star_txt}</span>'
                        f'{pos_cnt}'
                        f'</div>'
                    )
            else:
                # v0.7: 非トレード日も環境メモを薄く表示
                # 「捏造禁止」原則維持 — 既存環境データの事実情報のみ
                # 本格的な「もし入ってたら」MAE/MFE は MT5 全営業日 48h 集計が必要 (コー案件)
                if rec and not is_outside:
                    d1p = rec.get("d1_pattern") or "—"
                    d1_di = rec.get("d1_di_dir") or "—"
                    h4z = rec.get("h4_atr_zone3") or "—"
                    h4p_auto = rec.get("h4_phase_auto") or "—"
                    # D1 RANGE 判定 (v0.7 リネーム)
                    d1_adx = rec.get("d1_adx22")
                    if d1_adx is not None and d1_adx < 18:
                        d1_lbl = "RANGE"
                    else:
                        d1_lbl = f"{d1p}{'/' + d1_di if d1_di != '—' else ''}"
                    html.append(
                        f'<div class="result tr-empty env-memo">'
                        f'<div class="env-row">'
                        f'<span class="env-k">D1</span><span class="env-v">{d1_lbl}</span>'
                        f'<span class="env-k">ATR</span><span class="env-v">{h4z}</span>'
                        f'</div>'
                        f'</div>'
                    )
                else:
                    html.append('<div class="result tr-empty">·</div>')

            # v3-A1: シグナルドット行（セル最下部の細い行 / 全件描画、+n 集約なし）
            # v3-Step2 B2: 全ドット抑制の行はデフォルト時 CSS で行ごと非表示
            _row_cls = " all-suppressed" if day_fires and not any(fr["pass_all"] for fr in day_fires) else ""
            html.append(f'<div class="fires-row{_row_cls}">')
            for fr in day_fires:
                _col = PATTERN_COLORS[fr["pattern"]][fr["direction"]]
                _glyph = "▲" if fr["direction"] == "BUY" else "▼"
                _supp_cls = "" if fr["pass_all"] else " suppressed"
                _fold_cls = " satfold" if fr["fold"] else ""
                _state = "pass" if fr["pass_all"] else "抑制"
                _fold_note = "（JST土曜分・金曜セル併載）" if fr["fold"] else ""
                html.append(f'<span class="fire-dot{_supp_cls}{_fold_cls}" data-fid="{fr["fid"]}" '
                            f'title="{fr["date"]} {fr["time_jst"]} JST {fr["pattern"]} {fr["direction"]} {_state}{_fold_note}" '
                            f'style="color:{_col};">{_glyph}</span>')
                emitted_dot_count += 1
                emitted_dot_fids.append(fr["fid"])
                if fr["fold"]:
                    emitted_fold_count += 1
                if not fr["pass_all"]:
                    emitted_supp_dot_count += 1
            html.append('</div>')

            html.append('</div>')  # cell

        html.append('</div>')  # week-cells
        html.append('</div>')  # week-group

    html.append('</div>')  # month

# v3-Step2 B3: 全月が過去だった場合の閉じ漏れ防止（通常は到達しない）
if _in_past_fold:
    html.append('</details>')

# ===== サマリ =====
all_trades = [t for ts in trade_by_date.values() for t in ts]
total_pl = sum(t["pl"] for t in all_trades)
n_win = sum(1 for t in all_trades if t["pl"]>0)
n_loss = sum(1 for t in all_trades if t["pl"]<0)
html.append('<div class="totals">')
html.append(f'<span class="k">全期間</span> <span class="v">{all_dates[0]:%Y-%m-%d} 〜 {all_dates[-1]:%Y-%m-%d}</span>')
html.append(f'<span class="k">トレード</span> <span class="v">{len(all_trades)}件</span>')
html.append(f'<span class="k">勝/負</span> <span class="v">{n_win} / {n_loss}</span>')
html.append(f'<span class="k">総損益</span> <span class="v">¥{total_pl:+,.0f}</span>')
html.append('</div>')

# ===== カレンダータブ閉じ =====
html.append('</div>')  # tab-pane calendar

# ============================================================
# v2.0 全体像タブ
# ============================================================
# 番人観点:
#   - 円グラフは「割合の可視化」で事実情報のみ
#   - パターン別色分けは「視認のための分類色」(BT知見の焼き付けではない)
#     → 任意の固定パレットを与え、評価ラベル化しない
#   - N<30 規模では統計的有意性なしを明記
# ============================================================
html.append('<div class="tab-pane" id="tab-overview">')

# --- 上部サマリ ---
total_mfe = sum((t.get("h4_mfe_48h") or 0) for t in all_trades)
total_mae = sum((t.get("h4_mae_48h") or 0) for t in all_trades)
# 勝率（建値除外、シグナル評価としてOK）
decided_all = n_win + n_loss
wr_all = (n_win / decided_all * 100) if decided_all > 0 else None
wr_txt = f"{wr_all:.1f}%" if wr_all is not None else "—"
pl_cls = "pos" if total_pl > 0 else ("neg" if total_pl < 0 else "")

html.append('<div class="overview-summary">')
html.append(f'<div class="stat-blk"><span class="stat-k">期間</span><span class="stat-v" style="font-size:11px;">{all_dates[0]:%Y-%m-%d} 〜 {all_dates[-1]:%Y-%m-%d}</span></div>')
html.append(f'<div class="stat-blk"><span class="stat-k">件数</span><span class="stat-v">{len(all_trades)}</span></div>')
html.append(f'<div class="stat-blk"><span class="stat-k">勝/負/建値</span><span class="stat-v" style="font-size:13px;">{n_win}/{n_loss}/{len(all_trades)-decided_all}</span></div>')
html.append(f'<div class="stat-blk"><span class="stat-k">勝率(建値除外)</span><span class="stat-v">{wr_txt}</span></div>')
html.append(f'<div class="stat-blk"><span class="stat-k">損益合計</span><span class="stat-v {pl_cls}">¥{total_pl:+,.0f}</span></div>')
html.append(f'<div class="stat-blk"><span class="stat-k">MFE合計</span><span class="stat-v">{total_mfe:,.0f} USD</span></div>')
html.append(f'<div class="stat-blk"><span class="stat-k">MAE合計</span><span class="stat-v">{total_mae:,.0f} USD</span></div>')
html.append('</div>')

# --- データ注釈 ---
html.append('<div class="overview-warning">')
html.append(f'<b>サンプル N={len(all_trades)}</b> — 方向性として参考程度、<b>統計的有意性なし</b>。')
html.append(' シグナル評価・クロス分析の事実情報として読む（戦略修正のためではない）。')
html.append(' [[research-purpose-and-rules]] 準拠。')
html.append('</div>')

# --- 円グラフ用ユーティリティ ---
# 集計1: 反省タグ別
PIE_CATEGORIES_DECISION = ["PAT-A", "PAT-B", "PAT-C", "PAT-D", "ATR収束底", "その他", "未分類"]
PIE_COLORS_DECISION = {
    "PAT-A":     "#5a9adf",
    "PAT-B":     "#7ab8e8",
    "PAT-C":     "#a8c8e8",
    "PAT-D":     "#d8a878",
    "ATR収束底": "#c878a8",
    "その他":    "#8a8a9a",
    "未分類":    "#4a4a5a",
}
decision_counts = {k: 0 for k in PIE_CATEGORIES_DECISION}
for t in all_trades:
    tag = (t.get("decision_tag") or "").strip()
    if not tag:
        decision_counts["未分類"] += 1
    elif tag in decision_counts:
        decision_counts[tag] += 1
    else:
        decision_counts["未分類"] += 1

# 集計2: 勝敗別
result_counts = {"勝ち": n_win, "負け": n_loss, "建値": len(all_trades) - decided_all}
PIE_COLORS_RESULT = {
    "勝ち": "#ffe080",
    "負け": "#8090a0",
    "建値": "#5a5a65",
}

# 集計3: D1フェーズ別（環境メモから）
# get_rec(d) の d1_pattern + d1_adx22 で RANGE 判定
phase_counts = {"BU": 0, "PD": 0, "RANGE": 0, "その他": 0}
PIE_COLORS_PHASE = {
    "BU":     "#ebaf37",
    "PD":     "#966ecd",
    "RANGE":  "#7878a0",
    "その他": "#4a4a5a",
}
for d, ts in trade_by_date.items():
    rec = get_rec(d)
    if not rec:
        for _ in ts:
            phase_counts["その他"] += 1
        continue
    d1_adx = rec.get("d1_adx22")
    d1p = rec.get("d1_pattern") or "—"
    if d1_adx is not None and d1_adx < 18:
        lbl = "RANGE"
    elif d1p in ("BU", "PD"):
        lbl = d1p
    else:
        lbl = "その他"
    for _ in ts:
        phase_counts[lbl] += 1

# 集計4: 曜日別
DOW_LABELS = ["月", "火", "水", "木", "金"]
PIE_COLORS_DOW = {
    "月": "#5a9adf",
    "火": "#7ab8e8",
    "水": "#a8c8e8",
    "木": "#d8a878",
    "金": "#c878a8",
}
dow_counts = {k: 0 for k in DOW_LABELS}
for d, ts in trade_by_date.items():
    if d.weekday() < 5:
        dow_counts[DOW_LABELS[d.weekday()]] += len(ts)

def render_pie(counts_dict, colors_dict, order=None, size=140, pie_key=""):
    """SVG 円グラフを生成。counts_dict のキー順 or order 指定順で配置。
    全件0なら空表示HTMLを返す。

    v0.2 変更: 各扇形 (path/circle) に data-pie-key, data-pie-value 属性を付与し、
    凡例行にも同属性を付与してクリッカブル化。JS 側で円グラフ起点フィルタリング。
    """
    keys = order if order else list(counts_dict.keys())
    total = sum(counts_dict.get(k, 0) for k in keys)
    if total == 0:
        return '<div class="pie-empty">データなし</div>', ''
    # SVG 描画
    cx, cy, r = size / 2, size / 2, size / 2 - 2
    svg = [f'<svg class="pie-svg" width="{size}" height="{size}" viewBox="0 0 {size} {size}">']
    # 単一カテゴリ100%対応（パスではなく円で描画）
    nonzero = [(k, counts_dict.get(k, 0)) for k in keys if counts_dict.get(k, 0) > 0]
    if len(nonzero) == 1:
        k, _ = nonzero[0]
        svg.append(
            f'<circle class="pie-slice" cx="{cx}" cy="{cy}" r="{r}" '
            f'fill="{colors_dict.get(k, "#888")}" stroke="#05090f" stroke-width="1" '
            f'data-pie-key="{pie_key}" data-pie-value="{k}">'
            f'<title>{k}: {counts_dict.get(k, 0)}件 (100%)</title>'
            f'</circle>'
        )
    else:
        start_ang = -math.pi / 2  # 12時方向開始
        for k in keys:
            v = counts_dict.get(k, 0)
            if v == 0:
                continue
            frac = v / total
            end_ang = start_ang + frac * 2 * math.pi
            x1 = cx + r * math.cos(start_ang)
            y1 = cy + r * math.sin(start_ang)
            x2 = cx + r * math.cos(end_ang)
            y2 = cy + r * math.sin(end_ang)
            large_arc = 1 if frac > 0.5 else 0
            color = colors_dict.get(k, "#888")
            pct = frac * 100
            svg.append(
                f'<path class="pie-slice" d="M {cx} {cy} L {x1:.2f} {y1:.2f} A {r} {r} 0 {large_arc} 1 {x2:.2f} {y2:.2f} Z" '
                f'fill="{color}" stroke="#05090f" stroke-width="1" '
                f'data-pie-key="{pie_key}" data-pie-value="{k}">'
                f'<title>{k}: {v}件 ({pct:.0f}%)</title>'
                f'</path>'
            )
            start_ang = end_ang
    svg.append('</svg>')
    # 凡例（こちらもクリック対象に。SVG 扇形と同じ data 属性を持たせる）
    legend = ['<div class="pie-legend">']
    for k in keys:
        v = counts_dict.get(k, 0)
        if v == 0:
            continue
        pct = v / total * 100
        color = colors_dict.get(k, "#888")
        legend.append(
            f'<div class="pie-legend-row pie-slice" data-pie-key="{pie_key}" data-pie-value="{k}">'
        )
        legend.append(f'<span class="pie-legend-sw" style="background:{color};"></span>')
        legend.append(f'<span class="pie-legend-k">{k}</span>')
        legend.append(f'<span class="pie-legend-n">{v}</span>')
        legend.append(f'<span class="pie-legend-pct">{pct:.0f}%</span>')
        legend.append('</div>')
    legend.append('</div>')
    return ''.join(svg), ''.join(legend)

# --- 円グラフ 2x2 ---
html.append('<div class="pie-grid">')

# v0.2: 各円グラフに pie_key を割り当て（JS フィルタ識別用 / 内部キー、UI 表示語ではない）
# - pattern : 反省タグ別 (TRADES[*].pattern)
# - won     : 勝敗別     (TRADES[*].won = win/loss/zero)
# - d1_phase: D1フェーズ別 (TRADES[*].d1_phase ※ render 用に後で付与)
# - dow     : 曜日別     (TRADES[*].dow / 0=月 〜 4=金)
pies_def = [
    ("反省タグ別", "あろさんの意思決定タグ（反省列）の分布。扇形クリックで下のテーブルが切り替わります。",
     decision_counts, PIE_COLORS_DECISION, PIE_CATEGORIES_DECISION, "pattern"),
    ("勝敗別", "勝ち / 負け / 建値の件数分布。扇形クリックで下のテーブルが切り替わります。",
     result_counts, PIE_COLORS_RESULT, ["勝ち", "負け", "建値"], "won"),
    ("D1フェーズ別", "トレード発生時の大局フェーズ分布（D1 ADX&lt;18=RANGE）。扇形クリックで下のテーブルが切り替わります。",
     phase_counts, PIE_COLORS_PHASE, ["BU", "PD", "RANGE", "その他"], "d1_phase"),
    ("曜日別", "トレード発生曜日の分布（土日除外）。扇形クリックで下のテーブルが切り替わります。",
     dow_counts, PIE_COLORS_DOW, DOW_LABELS, "dow"),
]

for title, sub, counts, colors, order, pie_key in pies_def:
    html.append('<div class="pie-card">')
    html.append(f'<div class="pie-card-title">{title}</div>')
    html.append(f'<div class="pie-card-sub">{sub}</div>')
    svg_html, legend_html = render_pie(counts, colors, order=order, pie_key=pie_key)
    html.append('<div class="pie-card-body">')
    html.append(f'<div class="pie-svg-wrap">{svg_html}</div>')
    html.append(legend_html if legend_html else '<div></div>')
    html.append('</div>')  # pie-card-body
    html.append('</div>')  # pie-card

html.append('</div>')  # pie-grid

# ============================================================
# v0.2: 軸1「シグナル別統計テーブル」廃止
# ============================================================
# 廃止理由（あろさん 2026-06-10）:
#   - 入口はグラフから（視覚から掘る使い方）
#   - テーブル入口は冗長 → 円グラフを直接フィルタトリガーに
# 旧 sig-table / SIGNAL_ORDER / sig_groups / _stats() / _h4_atr_ratio_for_trade() は削除
# drilldown-wrap だけ残して、入口を円グラフへ張り替え（下記）
# ============================================================

# ============================================================
# v0.2 同ページドリルダウン (円グラフ起点)
# ============================================================
# 円グラフ扇形クリック → ここに該当データのトレード一覧が再描画される
# タブ遷移せず、視線を切らない設計
# 列ヘッダクリックで全数値列を昇降ソート（None は末尾固定）
# ATR 絶対値は連続値そのまま表示 → どの帯から MFE/勝敗が変化するか直接探索
# ============================================================
html.append('<div id="drilldown-wrap" class="drilldown-wrap">')
html.append('<div class="drilldown-head">')
html.append('<div id="drilldown-title" class="drilldown-title">—</div>')
html.append('<div id="drilldown-summary" class="drilldown-summary"></div>')
html.append('<div class="drilldown-hint">'
            'ヒント: 列ヘッダ（H1 ATR / H4 ATR / MFE / MAE / 損益 / H1 ATR比）クリックで昇降ソート。'
            ' <button id="drilldown-clear" class="drill-clear-btn" type="button">全件表示に戻す</button>'
            '</div>')
html.append('</div>')
html.append('<table class="detail-table drill-table">')
html.append('<thead><tr><th>日付</th><th>方向</th><th>損益</th><th>MFE</th><th>MAE</th>'
            '<th>反省</th><th>D1</th><th>H1 ATR</th><th>H4 ATR</th><th>H1 ATR比</th><th>★</th></tr></thead>')
html.append('<tbody id="drilldown-tbody"></tbody>')
html.append('</table>')
html.append('</div>')  # drilldown-wrap

html.append('<div class="notes">')
html.append('<b>v0.2 変更点 — 円グラフ起点ドリルダウン</b>:')
html.append('<br>　　　・<b>円グラフ4つ全てクリッカブル化</b>: 扇形/凡例タップ → 下の詳細テーブルが該当データに切り替わる')
html.append('<br>　　　・<b>1グラフ1フィルタ</b>: 別グラフを押すと前のフィルタは解除（最後にクリックしたものだけ有効）')
html.append('<br>　　　・<b>同じ扇形を再クリック</b>または<b>「全件表示に戻す」ボタン</b>で解除')
html.append('<br>　　　・<b>軸1「シグナル別統計テーブル」廃止</b>: グラフ→詳細の一本化（テーブル入口は冗長のため）')
html.append('<br>　　　・<b>H1 ATR / H4 ATR 列バグ修正</b>: enriched キー誤参照を解消、絶対値が実値表示')
html.append('<br>　　　・<b>全数値列の昇降ソート</b>: 損益/MFE/MAE/H1 ATR/H4 ATR/H1 ATR比、None は末尾固定')
html.append('<br>　　　・<b>探索目的</b>: 「H1 ATR 7.1 → 7.8 → ... → 18.4」で並べて、どの帯から MFE/勝敗が変化するか直接観察')
html.append('<br><b>v1.3 変更点 — 値動きレンジバー & トレードタグ</b>:')
html.append('<br>　　　・<b>非トレード日バー統合</b>: BUY/SELL 2本 → 1本の値動きレンジ（同情報の二重表示を解消）')
html.append('<br>　　　・右=上方向の最大伸び (max High - entry) / 左=下方向の最大伸び (entry - min Low) / 中央 tick=entry')
html.append('<br>　　　・数値表示: <span style="color:rgba(140,200,240,0.92);font-weight:700;">↑上 N</span> / <span style="color:rgba(230,140,140,0.88);font-weight:700;">↓下 N</span> — 方向中立、立場依存ラベル化なし')
html.append('<br>　　　・<b>トレード日タグ追加</b>: シグナル行に pattern + H1 ATR Ratio を表示（色フラット、評価ラベル化なし）')
html.append('<br>　　　・トレード日のバー（実 MFE/MAE）は方向確定済みなので現状維持')
html.append('<br><b>v1.1 階層化原則</b>: H4(主役 / 背景=スコア段階明度+DI色相, 中央=結果バー)。背景=環境、中央=結果の<b>並列読み</b>。')
html.append('<br><b>v1.1 変更点 — 非トレード日もバースタイル統一 & 全体比正規化</b>:')
html.append('<br>　　　・非トレード日の中央: 数値テキスト → <b>BUY/SELL の2本バー（縦並列）</b>')
html.append('<br>　　　・各バーは中央 tick から左右に伸びる（左=MAE / 右=MFE）— トレード日と同構造')
html.append(f'<br>　　　・<b>全体比正規化</b>: CSV 全期間 MFE/MAE の p95 値（{BAR_NORM_BASE:.0f} USD）を 100% 基準')
html.append(f'<br>　　　・最大観測値: {BAR_MAX_OBS:.0f} USD（p95超は満タンクリップ、外れ値で他が潰れない設計）')
html.append('<br>　　　・<b>トレード日のバーも全体比に統一</b>（旧固定 300USD → 全体比 p95）→ 仮想と実の並列読みが正確に')
html.append('<br>　　　・「ボリューム感」が一目で伝わるバースタイル維持、数値は補助で小さく')
html.append('<br><b>v1.1 設計原則（番人観点）</b>: 仮想エントリーは「もし JST 14:00 に入っていたら」の<b>事実情報拡張</b>。')
html.append('<br>　　　・「機会損失」「取り逃がし」「いいトレード/悪いトレード」等の<b>判断ラベル化禁止</b>')
html.append('<br>　　　・BUY/SELL の優劣付け禁止 — 両方とも「もしの事実」として並列表示のみ')
html.append('<br>　　　・景色（背景濃淡+色相）が主役、仮想バーは opacity 0.72 で補助情報感')
html.append('<br><b>v0.8 継続</b>: DI 色相 / H1×H4 合成スコア / D1 帯の色相=DI × 鮮やかさ=ATR Phase / スコア 40+ で派手グロウ')
html.append('<br><b>v0.6 設計意図継続</b>: 「方向の事実」と「結果の規模」を視覚軸で完全分離。負け色を抑えて「負けを直視しすぎない構造」（番人観点）。')
html.append('<br><b>研究視点</b>: 環境が良いのに MAE 大 = エントリーミス疑い / 環境弱いのに MFE 大 = 行けた局面の検証材料 / 背景濃 + MFE 小 = フェイクに遭った可能性。')
html.append('<br><b>段階化の意図</b>: ADX 22 と 23 の差で判断しないため、閾値ベースの階段明度で表現。評価語(HOT/強/弱)は出さない。')
html.append('<br><b>v1.2 変更点 — 日次粒度本格化</b>:')
html.append('<br>　　　・環境データソース: <b>daily_aggregate.csv (C2出力)</b> 優先 + weekly_waves.json フォールバック')
html.append('<br>　　　・H4/H1 の 3軸 (max/close/mean) を役割で使い分け（ハイブリッド）:')
html.append('<br>　　　　　- <b>背景濃淡 = mean</b>（1日全体の温度感、近似的代表値）')
html.append('<br>　　　　　- <b>スコア計算 = max</b>（「伸びた瞬間」哲学、ADX素地の事実情報）')
html.append('<br>　　　　　- <b>DI 方向 = close</b>（確定情報、既存仕様維持）')
html.append('<br>　　　・同週内同値問題を解消 — 月〜金で H4 セル色・濃淡が日次変化、D1帯も日単位遷移')
html.append('<br>　　　・ツールチップに <b>H4/H1 mean/max</b> 併記（軸の動きを目視確認可能）')
html.append('<br><b>注意1</b>: 日次CSV 期間外は週次フォールバック（同週内同値の旧挙動）。CSV 期間拡張は MT5 集計実行で対応。')
html.append('<br><b>注意2</b>: 仮想 MFE/MAE は <b>規模</b>を示すだけで「良い判断/悪い判断」の判定ではない。★評価(判断質)と混同しない。')
html.append('<br><b>注意3</b>: 複数トレード日は max(MFE)/max(MAE) で集約、方向はロット加重多数派で決定。詳細は trades_enriched_full.csv を直接参照。')
html.append('<br><b>シグナル列</b>: 現状トレード発生日のみマーク (▲)。本来は v4 mq5 シグナル発火ログから取得 (整備待ち)。')
html.append('</div>')

# ===== 全体像タブ閉じ =====
html.append('</div>')  # tab-pane overview

# ============================================================
# v2.0 Step2 詳細分析タブ — フィルター + クロス集計
# ============================================================
# 番人観点:
#   - シグナル評価のための勝率・クロス分析は OK (research-purpose-and-rules)
#   - パターン別色分け禁止
#   - 「PAT-A 勝率高い → エントリーフィルタに」は結果フィッティング NG
#   - データ少 (N=30) を強調
# ============================================================

# トレードフラット化 (JS用)
import json as _json
_detail_trades = []
# v0.2 バグ修正(U3):
# enriched CSV のキーは「約定日」(日本語 / "YYYY/MM/DD HH:MM" 形式)。
# 旧コードは "trade_date" (英字キー) を参照して常に空文字列 → ATR 絶対値が全行 None になっていた。
# 正しいキーで再構築し、日付 (YYYY-MM-DD) + direction (BUY/SELL) でマップ化。
_enr_by_key = {}
for _er in enriched_map.values():
    try:
        # 「約定日」は "2026/03/17 13:00" 形式 → 先頭10文字 "2026/03/17" → "2026-03-17"
        _src = (_er.get("約定日") or "").strip()
        _td = _src[:10].replace("/", "-") if _src else ""
        _dir = (_er.get("direction") or "").strip().upper()
        if _td and _dir:
            _enr_by_key.setdefault((_td, _dir), []).append(_er)
    except Exception:
        pass

def _atr_band_abs(v, lo, hi):
    if v is None: return "none"
    if v < lo: return "low"
    if v < hi: return "mid"
    return "high"

def _di_dir(plus, minus):
    if plus is None or minus is None: return "—"
    diff = plus - minus
    if diff > 2: return "UP"
    if diff < -2: return "DOWN"
    return "FLAT"

for _d, _ts in trade_by_date.items():
    _rec = get_rec(_d)
    _date_str = str(_d)
    _date_us = _date_str  # YYYY-MM-DD
    for _t in _ts:
        _pl = _t.get("pl", 0) or 0
        _won = "win" if _pl > 0 else ("loss" if _pl < 0 else "zero")
        _order = _t.get("order", "")
        _entry_dir = "UP" if _order == "買い" else ("DOWN" if _order == "売り" else "FLAT")
        # enriched から ATR 生値・DI 詳細を拾う
        _direction_en = "BUY" if _order == "買い" else "SELL"
        _enrs = _enr_by_key.get((_date_us, _direction_en), [])
        _enr = _enrs[0] if _enrs else {}
        def _ef(key):
            try:
                v = _enr.get(key)
                return float(v) if v not in (None, "", "—") else None
            except Exception:
                return None
        _h1_atr_abs = _ef("h1_atr32")
        _h4_atr_abs = _ef("h4_atr46")
        _h1_di_plus = _ef("h1_di_plus"); _h1_di_minus = _ef("h1_di_minus")
        _h4_di_plus = _ef("h4_di_plus"); _h4_di_minus = _ef("h4_di_minus")
        _d1_di_plus = _ef("d1_di_plus"); _d1_di_minus = _ef("d1_di_minus")
        _h1_dir = _di_dir(_h1_di_plus, _h1_di_minus)
        _h4_dir = _di_dir(_h4_di_plus, _h4_di_minus)
        _d1_dir = _di_dir(_d1_di_plus, _d1_di_minus)
        # 方向整合: D1, H4, エントリーが全て揃ったか
        _dirs = [_d1_dir, _h4_dir, _entry_dir]
        _ups = sum(1 for x in _dirs if x == "UP")
        _dns = sum(1 for x in _dirs if x == "DOWN")
        if _ups == 3 or _dns == 3:
            _align = "3揃"
        elif _ups == 2 or _dns == 2:
            _align = "2揃"
        else:
            _align = "不揃"
        # v0.2: 円グラフ起点フィルタ用キー追加（事実情報の写像、評価ラベル化なし）
        # 勝敗別の表示語（円グラフ凡例と完全一致）
        _won_label = "勝ち" if _won == "win" else ("負け" if _won == "loss" else "建値")
        # D1フェーズ別（phase_counts と同ロジック / d1_adx<18=RANGE / その他）
        _d1_adx_val = (_rec or {}).get("d1_adx22") if _rec else None
        _d1p_val = (_rec or {}).get("d1_pattern") or "—" if _rec else "—"
        if _rec is None:
            _d1_phase = "その他"
        elif _d1_adx_val is not None and _d1_adx_val < 18:
            _d1_phase = "RANGE"
        elif _d1p_val in ("BU", "PD"):
            _d1_phase = _d1p_val
        else:
            _d1_phase = "その他"
        # 曜日別の表示語（円グラフ凡例と完全一致 / 土日は計算上発生し得ない）
        _dow_label = DOW_LABELS[_d.weekday()] if _d.weekday() < 5 else ""
        _detail_trades.append({
            "date": str(_d),
            "dow": _d.weekday(),
            "dow_label": _dow_label,
            "order": _order,
            "pl": _pl,
            "lot": _t.get("lot", 0),
            "star": _t.get("star", ""),
            "pattern": (_t.get("decision_tag") or "").strip() or "未分類",
            "mfe": _t.get("h4_mfe_48h"),
            "mae": _t.get("h4_mae_48h"),
            "h1_atr_ratio": _t.get("h1_atr_ratio"),
            "h1_atr_abs": _h1_atr_abs,
            "h4_atr_abs": _h4_atr_abs,
            "h1_dir": _h1_dir,
            "h4_dir": _h4_dir,
            "d1_dir": _d1_dir,
            "entry_dir": _entry_dir,
            "align": _align,
            "d1_pattern": (_rec or {}).get("d1_pattern") or "—",
            "d1_phase": _d1_phase,  # 円グラフ起点フィルタ用（BU/PD/RANGE/その他）
            "h4_phase": (_rec or {}).get("h4_phase_auto") or "—",
            "won": _won,
            "won_label": _won_label,  # 円グラフ起点フィルタ用（勝ち/負け/建値）
        })

html.append('<div class="tab-pane" id="tab-detail">')

html.append('<div class="detail-head">')
html.append('<div class="detail-title">詳細分析 — フィルター × クロス集計</div>')
html.append('<div class="detail-sub">フィルターで絞り込み → ピボット軸で集計 → クロス分析。'
            '<b>N=30 規模、方向性として統計的有意性なし</b>。'
            '<b>シグナル評価のため</b>表示（戦略修正のためではない）。</div>')
html.append('</div>')

# フィルター UI
html.append('<div class="filter-bar">')
html.append('<label>期間 <input type="date" id="f-date-from" class="f-date">'
            '<span class="f-date-sep">〜</span>'
            '<input type="date" id="f-date-to" class="f-date"></label>')
html.append('<label>反省タグ <select id="f-pattern">'
            '<option value="all">全て</option>'
            '<option>PAT-A</option><option>PAT-B</option><option>PAT-C</option>'
            '<option>PAT-D</option><option>ATR収束底</option><option>その他</option><option>未分類</option>'
            '</select></label>')
html.append('<label>D1パターン <select id="f-d1">'
            '<option value="all">全て</option>'
            '<option>BU</option><option>PD</option>'
            '</select></label>')
html.append('<label>勝敗 <select id="f-won">'
            '<option value="all">全て</option>'
            '<option value="win">勝</option><option value="loss">負</option><option value="zero">建値</option>'
            '</select></label>')
html.append('<label>H1 ATR比 <select id="f-atr">'
            '<option value="all">全て</option>'
            '<option value="lt07">&lt;0.7</option>'
            '<option value="07-10">0.7-1.0</option>'
            '<option value="10-14">1.0-1.4</option>'
            '<option value="ge14">≥1.4</option>'
            '</select></label>')
html.append('<label>方向整合 <select id="f-align">'
            '<option value="all">全て</option>'
            '<option value="3揃">3揃 (D1×H4×エントリ)</option>'
            '<option value="2揃">2揃</option>'
            '<option value="不揃">不揃</option>'
            '</select></label>')
html.append('<label>方向 <select id="f-order">'
            '<option value="all">全て</option>'
            '<option value="買い">買い</option><option value="売り">売り</option>'
            '</select></label>')
html.append('<label>曜日 <select id="f-dow">'
            '<option value="all">全て</option>'
            '<option value="0">月</option><option value="1">火</option><option value="2">水</option>'
            '<option value="3">木</option><option value="4">金</option>'
            '</select></label>')
html.append('<button id="f-reset" class="f-reset">リセット</button>')
html.append('</div>')

# ピボット軸選択
html.append('<div class="pivot-bar">')
html.append('<label>ピボット軸 <select id="p-axis">'
            '<option value="pattern">反省タグ</option>'
            '<option value="d1_pattern">D1パターン</option>'
            '<option value="won">勝敗</option>'
            '<option value="atr_band">H1 ATR比 帯</option>'
            '<option value="align">方向整合</option>'
            '<option value="dow">曜日</option>'
            '<option value="order">方向</option>'
            '</select></label>')
html.append('<div class="pivot-hint">※ ATR 絶対値はカテゴリ化せず、下の詳細テーブルで列ヘッダクリック → 昇降ソートで「どのATR帯から変化するか」を直接探索する設計。</div>')
html.append('</div>')

# 結果サマリ + ピボットテーブル + 詳細
html.append('<div class="result-summary" id="result-summary"></div>')

html.append('<table class="pivot-table">')
html.append('<thead><tr id="pivot-thead"></tr></thead>')
html.append('<tbody id="pivot-tbody"></tbody>')
html.append('</table>')

html.append('<details class="trade-detail" open>')
html.append('<summary>マッチしたトレード詳細</summary>')
html.append('<table class="detail-table" data-table="detail">')
html.append('<thead><tr><th>日付</th><th>方向</th><th>損益</th><th>MFE</th><th>MAE</th>'
            '<th>反省</th><th>D1</th><th>H1 ATR</th><th>H4 ATR</th><th>H1 ATR比</th><th>★</th></tr></thead>')
html.append('<tbody id="detail-tbody"></tbody>')
html.append('</table>')
html.append('</details>')

# データエンベッド (JS から参照)
html.append('<script>const TRADES = ' + _json.dumps(_detail_trades, ensure_ascii=False) + ';</script>')

html.append('</div>')  # tab-pane detail

# ============================================================
# v2.0 タブ切替 JS
# ============================================================
# URL ?tab=overview / ?tab=detail で状態保持
# デフォルト: calendar
html.append("""<script>
(function(){
  function activate(name){
    document.querySelectorAll('.tab-btn').forEach(b => {
      b.classList.toggle('active', b.dataset.tab === name);
    });
    document.querySelectorAll('.tab-pane').forEach(p => {
      p.classList.toggle('active', p.id === 'tab-' + name);
    });
  }
  // URL クエリから初期タブ取得
  var params = new URLSearchParams(window.location.search);
  var initial = params.get('tab') || 'calendar';
  if (!['calendar', 'overview', 'detail'].includes(initial)) initial = 'calendar';
  activate(initial);
  // クリックでタブ切替 + URL 更新
  document.querySelectorAll('.tab-btn').forEach(b => {
    b.addEventListener('click', function(){
      var name = this.dataset.tab;
      activate(name);
      var url = new URL(window.location.href);
      url.searchParams.set('tab', name);
      window.history.replaceState({}, '', url.toString());
    });
  });
})();
</script>""")

# ============================================================
# v2.0 Step2 詳細分析タブ JS — フィルター + ピボット + 詳細レンダリング
# ============================================================
html.append(r"""<script>
(function(){
  if (typeof TRADES === 'undefined') return;

  const ATR_BANDS = [
    {key: 'lt07',   min: -Infinity, max: 0.7,      label: '<0.7'},
    {key: '07-10',  min: 0.7,       max: 1.0,      label: '0.7-1.0'},
    {key: '10-14',  min: 1.0,       max: 1.4,      label: '1.0-1.4'},
    {key: 'ge14',   min: 1.4,       max: Infinity, label: '≥1.4'}
  ];
  function atrBand(r) {
    if (r == null) return 'none';
    for (const b of ATR_BANDS) {
      if (r >= b.min && r < b.max) return b.key;
    }
    return 'none';
  }
  function atrAbsBand(v, lo, hi) {
    if (v == null) return 'none';
    if (v < lo) return 'low';
    if (v < hi) return 'mid';
    return 'high';
  }
  TRADES.forEach(t => {
    t.atr_band = atrBand(t.h1_atr_ratio);
  });

  const DOW_LBL = ['月','火','水','木','金','土','日'];
  const WON_LBL = {win:'勝', loss:'負', zero:'建値'};
  const ATR_LBL = {lt07:'<0.7','07-10':'0.7-1.0','10-14':'1.0-1.4',ge14:'≥1.4',none:'欠損'};

  function $(id){ return document.getElementById(id); }
  function median(arr) {
    const s = arr.filter(x => x != null && !isNaN(x)).slice().sort((a,b)=>a-b);
    if (!s.length) return null;
    const m = Math.floor(s.length / 2);
    return s.length % 2 ? s[m] : (s[m-1] + s[m]) / 2;
  }
  function fmt(v, d) {
    d = d == null ? 1 : d;
    return (v == null || isNaN(v)) ? '—' : v.toFixed(d);
  }
  function yen(v) {
    const sign = v > 0 ? '+' : (v < 0 ? '−' : '');
    return sign + '¥' + Math.abs(v).toLocaleString('ja-JP');
  }
  function applyFilters() {
    const dFrom = $('f-date-from').value;  // "" or "YYYY-MM-DD"
    const dTo   = $('f-date-to').value;
    const pat = $('f-pattern').value;
    const d1  = $('f-d1').value;
    const won = $('f-won').value;
    const atr = $('f-atr').value;
    const align = ($('f-align') || {value:'all'}).value;
    const ord = $('f-order').value;
    const dow = $('f-dow').value;
    return TRADES.filter(t => {
      if (dFrom && t.date < dFrom) return false;
      if (dTo   && t.date > dTo)   return false;
      if (pat !== 'all' && t.pattern !== pat) return false;
      if (d1  !== 'all' && t.d1_pattern !== d1) return false;
      if (won !== 'all' && t.won !== won) return false;
      if (atr !== 'all' && t.atr_band !== atr) return false;
      if (align !== 'all' && t.align !== align) return false;
      if (ord !== 'all' && t.order !== ord) return false;
      if (dow !== 'all' && String(t.dow) !== dow) return false;
      return true;
    });
  }
  function pivotKeyLabel(axisKey, k) {
    if (axisKey === 'dow') return DOW_LBL[parseInt(k)] || k;
    if (axisKey === 'won') return WON_LBL[k] || k;
    if (axisKey === 'atr_band') return ATR_LBL[k] || k;
    return k;
  }
  function pivot(trades, axisKey) {
    const groups = {};
    for (const t of trades) {
      const v = t[axisKey];
      const k = (v == null || v === '') ? '—' : String(v);
      if (!groups[k]) groups[k] = [];
      groups[k].push(t);
    }
    return Object.entries(groups).map(([k, ts]) => {
      const wins   = ts.filter(t => t.won === 'win').length;
      const losses = ts.filter(t => t.won === 'loss').length;
      const decided = wins + losses;
      return {
        key: k,
        n: ts.length,
        wins, losses,
        wr: decided > 0 ? wins / decided * 100 : null,
        mfe_med: median(ts.map(t => t.mfe)),
        mae_med: median(ts.map(t => t.mae)),
        pl_sum: ts.reduce((s, t) => s + (t.pl || 0), 0),
      };
    }).sort((a, b) => b.n - a.n);
  }
  function refresh() {
    const filtered = applyFilters();
    const axisKey = $('p-axis').value;

    // 結果サマリ
    const wins = filtered.filter(t => t.won === 'win').length;
    const losses = filtered.filter(t => t.won === 'loss').length;
    const zeros = filtered.filter(t => t.won === 'zero').length;
    const pl = filtered.reduce((s, t) => s + (t.pl || 0), 0);
    const decided = wins + losses;
    const wr = decided > 0 ? (wins / decided * 100).toFixed(1) + '%' : '—';
    $('result-summary').innerHTML =
      '<b>件数</b>' + filtered.length + ' ｜ ' +
      '<b>勝</b>' + wins + ' ｜ <b>負</b>' + losses + ' ｜ <b>建値</b>' + zeros + ' ｜ ' +
      '<b>勝率</b>' + wr + ' ｜ <b>損益</b>' + yen(pl);

    // ピボット
    const pivoted = pivot(filtered, axisKey);
    $('pivot-thead').innerHTML =
      '<th>' + ($('p-axis').selectedOptions[0].text) + '</th>' +
      '<th>N</th><th>勝率</th><th>MFE中央</th><th>MAE中央</th><th>損益合計</th>';
    $('pivot-tbody').innerHTML = pivoted.map(r => {
      const lbl = pivotKeyLabel(axisKey, r.key);
      const wrTxt = r.wr != null ? r.wr.toFixed(1) + '%' : '—';
      const lowMark = r.n < 5 ? ' <span style="color:#d0a060;font-size:9px;">少</span>' : '';
      return '<tr><td>' + lbl + lowMark + '</td><td>' + r.n + '</td><td>' + wrTxt + '</td>' +
             '<td>' + fmt(r.mfe_med) + '</td><td>' + fmt(r.mae_med) + '</td>' +
             '<td>' + yen(r.pl_sum) + '</td></tr>';
    }).join('') || '<tr><td colspan="6" style="text-align:center;color:#5a6a8a;padding:14px;">該当データなし</td></tr>';

    // 詳細トレード一覧
    $('detail-tbody').innerHTML = filtered.map(t => {
      const cls = t.won === 'win' ? 'pos' : (t.won === 'loss' ? 'neg' : 'zero');
      return '<tr>' +
        '<td>' + t.date + '</td>' +
        '<td>' + t.order + '</td>' +
        '<td class="' + cls + '">' + yen(t.pl || 0) + '</td>' +
        '<td>' + fmt(t.mfe) + '</td>' +
        '<td>' + fmt(t.mae) + '</td>' +
        '<td>' + t.pattern + '</td>' +
        '<td>' + t.d1_pattern + '</td>' +
        '<td>' + fmt(t.h1_atr_abs, 2) + '</td>' +
        '<td>' + fmt(t.h4_atr_abs, 2) + '</td>' +
        '<td>' + fmt(t.h1_atr_ratio, 2) + '</td>' +
        '<td>' + (t.star || '') + '</td>' +
      '</tr>';
    }).join('') || '<tr><td colspan="11" style="text-align:center;color:#5a6a8a;padding:14px;">該当トレードなし</td></tr>';
  }
  // Listener
  ['f-date-from','f-date-to','f-pattern','f-d1','f-won','f-atr','f-align','f-order','f-dow','p-axis'].forEach(id => {
    const el = $(id);
    if (el) el.addEventListener('change', refresh);
  });
  const resetBtn = $('f-reset');
  if (resetBtn) {
    resetBtn.addEventListener('click', function(){
      ['f-pattern','f-d1','f-won','f-atr','f-align','f-order','f-dow'].forEach(id => {
        const el = $(id);
        if (el) el.value = 'all';
      });
      ['f-date-from','f-date-to'].forEach(id => {
        const el = $(id);
        if (el) el.value = '';
      });
      refresh();
    });
  }

  // 詳細テーブル ソート機能 (列ヘッダクリック)
  // v0.2: 全数値列で「絶対値で並べる」探索を可能に。None は末尾固定（昇降どちらでも）。
  // 「ATR 7.1 → 7.8 → 8.3 → ... → 18.4」で並べて、どの帯から MFE/勝敗が変化するか観察。
  const SORT_KEYS = ['date','order','pl','mfe','mae','pattern','d1_pattern','h1_atr_abs','h4_atr_abs','h1_atr_ratio','star'];
  const NUMERIC_DETAIL_KEYS = new Set(['pl','mfe','mae','h1_atr_abs','h4_atr_abs','h1_atr_ratio']);
  let _sortKey = null, _sortDir = 1;
  function attachSort() {
    // 詳細分析タブのテーブルのみ対象（drill-table は別ハンドラ）
    const ths = document.querySelectorAll('.detail-table:not(.drill-table) thead th');
    ths.forEach((th, idx) => {
      if (idx >= SORT_KEYS.length) return;
      th.style.cursor = 'pointer';
      th.title = 'クリックでソート（昇/降切替）';
      th.addEventListener('click', () => {
        const key = SORT_KEYS[idx];
        if (_sortKey === key) _sortDir = -_sortDir;
        else { _sortKey = key; _sortDir = 1; }
        ths.forEach(t => t.dataset.sort = '');
        th.dataset.sort = _sortDir > 0 ? 'asc' : 'desc';
        refresh();
      });
    });
  }
  attachSort();

  // refresh 内で sort を適用するため、refresh をラップ
  const _origRefresh = refresh;
  refresh = function() {
    _origRefresh();
    if (!_sortKey) return;
    const tbody = $('detail-tbody');
    if (!tbody) return;
    // 既に描画済みのテーブルから再ソート → 再描画
    const isNumeric = NUMERIC_DETAIL_KEYS.has(_sortKey);
    const filtered = applyFilters().slice().sort((a, b) => {
      const va = a[_sortKey], vb = b[_sortKey];
      const aNil = (va == null || (isNumeric && isNaN(va)));
      const bNil = (vb == null || (isNumeric && isNaN(vb)));
      if (aNil && bNil) return 0;
      if (aNil) return 1;   // None は常に末尾
      if (bNil) return -1;
      if (isNumeric) return (Number(va) - Number(vb)) * _sortDir;
      if (typeof va === 'number' && typeof vb === 'number') return (va - vb) * _sortDir;
      return String(va).localeCompare(String(vb)) * _sortDir;
    });
    tbody.innerHTML = filtered.map(t => {
      const cls = t.won === 'win' ? 'pos' : (t.won === 'loss' ? 'neg' : 'zero');
      return '<tr>' +
        '<td>' + t.date + '</td>' +
        '<td>' + t.order + '</td>' +
        '<td class="' + cls + '">' + yen(t.pl || 0) + '</td>' +
        '<td>' + fmt(t.mfe) + '</td>' +
        '<td>' + fmt(t.mae) + '</td>' +
        '<td>' + t.pattern + '</td>' +
        '<td>' + t.d1_pattern + '</td>' +
        '<td>' + fmt(t.h1_atr_abs, 2) + '</td>' +
        '<td>' + fmt(t.h4_atr_abs, 2) + '</td>' +
        '<td>' + fmt(t.h1_atr_ratio, 2) + '</td>' +
        '<td>' + (t.star || '') + '</td>' +
      '</tr>';
    }).join('');
  };

  // ============================================================
  // v0.2 同ページドリルダウン (円グラフ起点)
  // ============================================================
  // 円グラフ扇形クリック → 同ページ下部の drilldown-wrap が該当データで再描画
  // タブ遷移なし、分析の視線を切らない
  // 全数値列で列ヘッダクリック昇降ソート、None は末尾固定
  // ATR 絶対値は連続値そのまま、カテゴリ化禁止（探索目的）
  // ============================================================
  // ソート対象列キー（数値列は NUMERIC_DRILL_KEYS で判定し、None 末尾固定）
  const DRILL_SORT_KEYS = ['date','order','pl','mfe','mae','pattern','d1_pattern','h1_atr_abs','h4_atr_abs','h1_atr_ratio','star'];
  const NUMERIC_DRILL_KEYS = new Set(['pl','mfe','mae','h1_atr_abs','h4_atr_abs','h1_atr_ratio']);
  // 現在のフィルタ状態（pie_key -> value）。1グラフ1フィルタ、最後にクリックされたものだけ有効。
  let _drillFilter = null;   // {key: 'pattern'|'won_label'|'d1_phase'|'dow_label', value: '...'}
  let _drillSortKey = null, _drillSortDir = 1;

  // フィルタキー(pie_key) → TRADES の属性名 マッピング
  const PIE_KEY_TO_FIELD = {
    'pattern':  'pattern',
    'won':      'won_label',
    'd1_phase': 'd1_phase',
    'dow':      'dow_label',
  };
  // フィルタキー(pie_key) → 見出し用ラベル
  const PIE_KEY_TO_TITLE = {
    'pattern':  '反省タグ別',
    'won':      '勝敗別',
    'd1_phase': 'D1フェーズ別',
    'dow':      '曜日別',
  };

  function renderDrilldown() {
    const wrap = document.getElementById('drilldown-wrap');
    if (!wrap) return;
    const title = document.getElementById('drilldown-title');
    const tbody = document.getElementById('drilldown-tbody');
    const summary = document.getElementById('drilldown-summary');

    // 対象トレード抽出
    let trades;
    let titleText;
    if (_drillFilter) {
      const field = PIE_KEY_TO_FIELD[_drillFilter.key];
      trades = TRADES.filter(t => String(t[field]) === String(_drillFilter.value));
      titleText = (PIE_KEY_TO_TITLE[_drillFilter.key] || _drillFilter.key) +
                  ': ' + _drillFilter.value + ' (' + trades.length + '件)';
    } else {
      trades = TRADES.slice();
      titleText = '全件表示 (' + trades.length + '件)';
    }

    // ソート（数値列は None 末尾固定）
    if (_drillSortKey) {
      const isNumeric = NUMERIC_DRILL_KEYS.has(_drillSortKey);
      trades = trades.slice().sort((a, b) => {
        const va = a[_drillSortKey], vb = b[_drillSortKey];
        const aNil = (va == null || (isNumeric && (isNaN(va))));
        const bNil = (vb == null || (isNumeric && (isNaN(vb))));
        if (aNil && bNil) return 0;
        if (aNil) return 1;   // None は常に末尾
        if (bNil) return -1;
        if (isNumeric) return (Number(va) - Number(vb)) * _drillSortDir;
        if (typeof va === 'number' && typeof vb === 'number') return (va - vb) * _drillSortDir;
        return String(va).localeCompare(String(vb)) * _drillSortDir;
      });
    }

    if (title) title.textContent = titleText;
    if (summary) {
      const wins = trades.filter(t => t.won === 'win').length;
      const losses = trades.filter(t => t.won === 'loss').length;
      const zeros = trades.filter(t => t.won === 'zero').length;
      const pl = trades.reduce((s, t) => s + (t.pl || 0), 0);
      const decided = wins + losses;
      const wr = decided > 0 ? (wins / decided * 100).toFixed(1) + '%' : '—';
      summary.innerHTML = '<b>勝</b>' + wins + ' ｜ <b>負</b>' + losses + ' ｜ <b>建値</b>' + zeros +
                         ' ｜ <b>勝率</b>' + wr + ' ｜ <b>損益</b>' + yen(pl);
    }
    if (tbody) {
      tbody.innerHTML = trades.map(t => {
        const cls = t.won === 'win' ? 'pos' : (t.won === 'loss' ? 'neg' : 'zero');
        return '<tr>' +
          '<td>' + t.date + '</td>' +
          '<td>' + t.order + '</td>' +
          '<td class="' + cls + '">' + yen(t.pl || 0) + '</td>' +
          '<td>' + fmt(t.mfe) + '</td>' +
          '<td>' + fmt(t.mae) + '</td>' +
          '<td>' + t.pattern + '</td>' +
          '<td>' + t.d1_pattern + '</td>' +
          '<td>' + fmt(t.h1_atr_abs, 2) + '</td>' +
          '<td>' + fmt(t.h4_atr_abs, 2) + '</td>' +
          '<td>' + fmt(t.h1_atr_ratio, 2) + '</td>' +
          '<td>' + (t.star || '') + '</td>' +
        '</tr>';
      }).join('') || '<tr><td colspan="11" style="text-align:center;color:#5a6a8a;padding:14px;">該当トレードなし</td></tr>';
    }
    wrap.style.display = 'block';
  }

  // ドリルダウンソート (列ヘッダ)
  function attachDrillSort() {
    const ths = document.querySelectorAll('#drilldown-wrap thead th');
    ths.forEach((th, idx) => {
      if (idx >= DRILL_SORT_KEYS.length) return;
      th.style.cursor = 'pointer';
      th.title = 'クリックでソート（昇/降切替）';
      th.addEventListener('click', () => {
        const key = DRILL_SORT_KEYS[idx];
        if (_drillSortKey === key) _drillSortDir = -_drillSortDir;
        else { _drillSortKey = key; _drillSortDir = 1; }
        ths.forEach(t => t.dataset.sort = '');
        th.dataset.sort = _drillSortDir > 0 ? 'asc' : 'desc';
        renderDrilldown();
      });
    });
  }
  attachDrillSort();

  // 円グラフ扇形クリック → 同ページドリルダウン
  // 全グラフ統一: 1グラフ1フィルタ、最後にクリックされたものだけ有効
  // 同じ扇形 (key+value 完全一致) を再クリックすると解除 → 全件表示
  function attachPieClicks() {
    const slices = document.querySelectorAll('.pie-slice[data-pie-key][data-pie-value]');
    slices.forEach(el => {
      el.style.cursor = 'pointer';
      el.addEventListener('click', () => {
        const k = el.dataset.pieKey;
        const v = el.dataset.pieValue;
        // 同じ扇形を再クリック → 解除
        if (_drillFilter && _drillFilter.key === k && _drillFilter.value === v) {
          _drillFilter = null;
        } else {
          _drillFilter = {key: k, value: v};
        }
        // ハイライト：同 key+value の SVG/凡例 を active 化、他は解除
        document.querySelectorAll('.pie-slice').forEach(s => s.classList.remove('pie-slice-active'));
        if (_drillFilter) {
          document.querySelectorAll(
            '.pie-slice[data-pie-key="' + k + '"][data-pie-value="' + v + '"]'
          ).forEach(s => s.classList.add('pie-slice-active'));
        }
        _drillSortKey = null; _drillSortDir = 1;
        document.querySelectorAll('#drilldown-wrap thead th').forEach(t => t.dataset.sort = '');
        renderDrilldown();
      });
    });
  }
  attachPieClicks();

  // 「全件表示に戻す」ボタン
  const clearBtn = document.getElementById('drilldown-clear');
  if (clearBtn) {
    clearBtn.addEventListener('click', () => {
      _drillFilter = null;
      _drillSortKey = null; _drillSortDir = 1;
      document.querySelectorAll('.pie-slice').forEach(s => s.classList.remove('pie-slice-active'));
      document.querySelectorAll('#drilldown-wrap thead th').forEach(t => t.dataset.sort = '');
      renderDrilldown();
    });
  }

  // 初期表示：全件
  renderDrilldown();

  refresh();
})();
</script>""")

# ============================================================
# v3-A2: ドリルダウンドロワー（signals_calendar v2 流用）
# - シグナルカード + 実トレードカード（MFE/MAE 12/24/36/48h 同一フォーマット = mmSteps 共用）
# - server時間併記 / 新規理由はデフォルト閉の <details>
# - JS 名は V3_ 接頭辞 + IIFE で v2 既存 JS（TRADES 等）と衝突回避
# ============================================================
_v3_fires_json = [{k: v for k, v in fr.items() if k != "_cell_d"} for fr in fires]
_v3_fires_blob = json.dumps(_v3_fires_json, ensure_ascii=False).replace("</", "<\\/")
_v3_colors_blob = json.dumps(PATTERN_COLORS)
_v3_trades_json = [{k: v for k, v in t.items() if k != "_d"} for t in drill_trades]
_v3_trades_blob = json.dumps(_v3_trades_json, ensure_ascii=False).replace("</", "<\\/")

html.append('<div id="drill">'
            '<div class="drill-head"><span class="drill-title" id="drill-title"></span>'
            '<button class="drill-close" id="drill-close">閉じる ✕</button></div>'
            '<div class="drill-note">サーバー時間 = チャート表示時間（照合用）。'
            '薄カード = pass_all=FALSE（実機チャート非表示の発火、「全発火表示」トグル時のみ）。バー長 = カード内の最大値基準（伸び方の形を見る用）。'
            '「土」= JST土曜発火（サーバー金曜深夜、金曜セルに併載）。'
            'トレードカードの pips は価格幅（USD、MFE/MAE と同スケール）。</div>'
            '<div class="drill-body" id="drill-body"></div></div>')

html.append("<script>")
html.append(f"const V3_FIRES = {_v3_fires_blob};")
html.append(f"const V3_PAT_COLORS = {_v3_colors_blob};")
html.append(f"const V3_TRADES = {_v3_trades_blob};")
html.append(r"""
(function(){
  // ============ インデックス ============
  // 発火はセル配置日（JST土曜分は金曜）で引く / トレードは JST 約定日
  const byCell = {};
  for (const f of V3_FIRES) {
    (byCell[f.cell_date] = byCell[f.cell_date] || []).push(f);
  }
  const tByDate = {};
  for (const t of V3_TRADES) {
    (tByDate[t.date] = tByDate[t.date] || []).push(t);
  }

  let openDate = null;
  const drill = document.getElementById("drill");

  function fmt(v, digits) {
    return (v === null || v === undefined) ? "—" : v.toFixed(digits === undefined ? 1 : digits);
  }
  function esc(s) {
    return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  }

  // MFE/MAE ステップバー（シグナル/トレードカード共用 — 同じ言語での対比が核心）
  function mmSteps(f) {
    const vals = [...f.mfe, ...f.mae].filter(v => v !== null);
    const mx = Math.max(...vals, 1);
    const hs = ["12h", "24h", "36h", "48h"];
    let rows = "";
    for (let i = 0; i < 4; i++) {
      const mfeW = f.mfe[i] === null ? 0 : (f.mfe[i] / mx * 100);
      const maeW = f.mae[i] === null ? 0 : (f.mae[i] / mx * 100);
      rows += `<div class="mm-row"><span class="mm-h">${hs[i]}</span>` +
        `<div class="mm-bar-wrap w-mae"><div class="mm-bar mae" style="width:${maeW.toFixed(1)}%;"></div>` +
        `<span class="mm-num">${fmt(f.mae[i])}</span></div>` +
        `<div class="mm-bar-wrap w-mfe"><div class="mm-bar mfe" style="width:${mfeW.toFixed(1)}%;"></div>` +
        `<span class="mm-num">${fmt(f.mfe[i])}</span></div></div>`;
    }
    let traced = "";
    if (f.bars_traced !== null && f.bars_traced < 48) {
      traced = `<div class="mm-legend">追跡 ${f.bars_traced}/48 本（期間端）</div>`;
    }
    return `<div class="mm-steps"><div class="mm-ttl">MFE/MAE 推移 (USD, 48h固定追跡)</div>${rows}` +
      `<div class="mm-legend"><span class="mae-k">◀ MAE (踏)</span><span class="mfe-k">MFE (伸) ▶</span></div>${traced}</div>`;
  }

  function fireCard(f) {
    const col = V3_PAT_COLORS[f.pattern][f.direction];
    const glyph = f.direction === "BUY" ? "▲" : "▼";
    const passHtml = f.pass_all
      ? '<span class="fc-pass ok">pass_all ✅</span>'
      : '<span class="fc-pass ng">抑制 ⛔</span>';
    const filt = f.filter_hits.length
      ? `<div class="fc-filters hit">フィルター: ${f.filter_hits.join(", ")} にヒット → 実機非表示</div>`
      : '<div class="fc-filters nohit">フィルター: 9本中ヒットなし</div>';
    const foldMark = f.fold ? "土 " : "";
    return `<div class="fire-card${f.pass_all ? "" : " suppressed"}">` +
      `<div class="fc-head"><span class="fc-pat" style="background:${col};">${f.pattern} ${glyph}${f.direction}</span>` +
      `<span class="fc-time">${foldMark}${f.time_jst} JST</span>` +
      `<span class="fc-server">(server ${f.time_server})</span>${passHtml}</div>` +
      `<div class="fc-row"><span class="k">@</span><span class="v">${fmt(f.entry_price, 2)}</span></div>` +
      `<div class="fc-row">` +
      `<span class="k">ATR Zone</span><span class="v">${f.atr_zone} <span class="raw">(ratio ${fmt(f.h1_atr_ratio, 2)})</span></span>` +
      `<span class="k">H1 ADX</span><span class="v">${f.h1_adx_zone} <span class="raw">(${fmt(f.h1_adx32)})</span></span>` +
      `<span class="k">H1 pat</span><span class="v">${f.h1_pattern}</span></div>` +
      `<div class="fc-row">` +
      `<span class="k">D1 cross</span><span class="v">${f.cross_dir} <span class="raw">(${f.d1_cross_bars}本)</span></span>` +
      `<span class="k">D1 DI</span><span class="v">${f.d1_di_dir} <span class="raw">(ADX ${fmt(f.d1_adx22, 0)})</span></span>` +
      `<span class="k">H4 cross</span><span class="v">${f.h4_cross_dir} <span class="raw">(${f.h4_cross_bars}本)</span></span>` +
      `<span class="k">H4 ADX</span><span class="v">${f.h4_adx_zone} <span class="raw">(${fmt(f.h4_adx46)})</span></span></div>` +
      // v3-Step2 B1 fix: 閉じ </div> が無く後続カードが全部 .suppressed の中に
      // 入れ子になり opacity 0.55 が実トレードカードまで継承されていた
      filt + mmSteps(f) + `</div>`;
  }

  function tradeCard(t) {
    const glyph = t.direction === "BUY" ? "▲" : "▼";
    let pipsCls = "flat", pipsTxt = "±0.0";
    if (t.pips !== null && t.pips > 0) { pipsCls = "pos"; pipsTxt = "+" + t.pips.toFixed(1); }
    else if (t.pips !== null && t.pips < 0) { pipsCls = "neg"; pipsTxt = t.pips.toFixed(1); }
    const meta = [];
    if (t.style) meta.push(`<span>${esc(t.style)}</span>`);
    if (t.star) meta.push(`<span>★${esc(t.star)}</span>`);
    if (t.tag) {
      const otherCls = t.tag === "その他" ? " other" : "";
      meta.push(`<span class="tc-tag${otherCls}">#${esc(t.tag)}</span>`);
    }
    const reason = t.reason
      ? `<details class="tc-reason"><summary>新規理由 ▸</summary>` +
        `<div class="tc-reason-body">${esc(t.reason)}</div></details>`
      : "";
    return `<div class="trade-card">` +
      `<div class="tc-head"><span class="tc-dir">${glyph} ${t.direction}</span>` +
      `<span class="tc-time">${t.entry_time} → ${t.exit_disp} JST</span>` +
      `<span class="tc-pips ${pipsCls}">${pipsTxt} pips</span></div>` +
      (meta.length ? `<div class="tc-meta">${meta.join("")}</div>` : "") +
      mmSteps(t) + reason + `</div>`;
  }

  // v3-Step2 B2: フィルタートグル（デフォルト = pass_all のみ。ドット側は CSS 連動）
  const calTab = document.getElementById("tab-calendar");
  const supChk = document.getElementById("v3-show-suppressed");
  function showAllFires() { return !!(supChk && supChk.checked); }

  function renderDrill(dateStr) {
    openDate = dateStr;
    const allFires = byCell[dateStr] || [];
    const dayFires = showAllFires() ? allFires : allFires.filter(f => f.pass_all);
    const nHidden = allFires.length - dayFires.length;
    const dayTrades = tByDate[dateStr] || [];
    document.getElementById("drill-title").textContent =
      `${dateStr} — 発火 ${dayFires.length}件` +
      (nHidden > 0 ? `（抑制 ${nHidden}件 非表示）` : "") +
      (dayTrades.length ? ` / 実トレード ${dayTrades.length}件` : "");
    let body;
    if (dayFires.length) {
      body = dayFires.map(fireCard).join("");
    } else if (nHidden > 0) {
      body = `<div style="color:#4a6a8a;font-size:11px;padding:20px 0;text-align:center;">pass_all の発火なし（抑制 ${nHidden}件 — 「全発火表示」トグルで確認）</div>`;
    } else {
      body = '<div style="color:#4a6a8a;font-size:11px;padding:20px 0;text-align:center;">この日のシグナル発火はありません</div>';
    }
    if (dayTrades.length) {
      body += `<div class="trade-sec-hdr">実トレード ${dayTrades.length}件</div>` +
        dayTrades.map(tradeCard).join("");
    }
    document.getElementById("drill-body").innerHTML = body;
    drill.classList.add("open");
    document.querySelectorAll("#tab-calendar .cell.drill-open").forEach(c => c.classList.remove("drill-open"));
    const cell = document.querySelector(`#tab-calendar .cell[data-date="${dateStr}"]:not(.outside)`);
    if (cell) cell.classList.add("drill-open");
  }

  // セルクリック（カレンダータブ内、発火 or トレードのある in-month セルのみ）
  document.querySelectorAll("#tab-calendar .cell.has-fires, #tab-calendar .cell.has-trade").forEach(cell => {
    cell.addEventListener("click", () => renderDrill(cell.dataset.date));
  });
  document.getElementById("drill-close").addEventListener("click", () => {
    drill.classList.remove("open");
    openDate = null;
    document.querySelectorAll("#tab-calendar .cell.drill-open").forEach(c => c.classList.remove("drill-open"));
  });

  // v3-Step2 B2: トグル変更 → ドット(CSSクラス) / ヘッダー集計 / 開いてるドロワー を連動更新
  if (supChk) {
    supChk.addEventListener("change", () => {
      calTab.classList.toggle("show-all-fires", supChk.checked);
      const summ = document.getElementById("v3-fire-summary");
      if (summ) {
        const p = summ.dataset.pass, s = summ.dataset.supp, t = summ.dataset.total;
        summ.textContent = supChk.checked
          ? `シグナル発火: ${t}件 (pass ${p} / 抑制 ${s} 薄表示)`
          : `シグナル発火: ${p}件 (pass_all のみ表示 / 抑制 ${s}件 非表示)`;
      }
      if (openDate) renderDrill(openDate);
    });
  }
})();
""")
html.append("</script>")

html.append('</body></html>')

out_path = OUT / "daily_calendar_v3.html"
out_path.write_text("\n".join(html), encoding="utf-8")
print(f"OK 出力: {out_path}")
print(f"   トレード日数: {len(trade_by_date)}")
print(f"   期間: {all_dates[0]} 〜 {all_dates[-1]}")

# サニティ
missing = [d for d in all_dates if get_rec(d) is None or get_rec(d).get("h4_adx46") is None]
if missing:
    print(f"   WARN ADXデータ未取得日: {len(missing)} (例: {missing[:3]})")
else:
    print(f"   OK 全トレード日のADX取得OK")

# v1.2: 日次データソース分布
n_daily_in_trades = sum(1 for d in all_dates if daily_agg_map.get(d) is not None)
n_weekly_fallback = len(all_dates) - n_daily_in_trades
print(f"   日次CSV(daily_aggregate): {daily_agg_count}日収録 / トレード日のうち日次={n_daily_in_trades} 週次fallback={n_weekly_fallback}")
if daily_agg_count > 0:
    sample_dates = sorted(daily_agg_map.keys())
    print(f"   日次CSV期間: {sample_dates[0]} 〜 {sample_dates[-1]}")

# ============================================================
# v3 セルフチェック（指示書 §4 完了条件の検証出力）
# ============================================================
print()
print("=" * 60)
print("v3 移植版 セルフチェック（指示書 §4）")
print("=" * 60)
print(f"[A1-1] signal_fires.csv 読込   : {n_fires_total} 件")
print(f"[A1-2] HTML描画 fire-dot 数    : {emitted_dot_count} 件（CSV件数と一致すべき）")
_missing_fids = set(fr["fid"] for fr in fires) - set(emitted_dot_fids)
print(f"[A1-3] 欠落 fire_id            : {sorted(_missing_fids, key=int) if _missing_fids else 'なし（欠落ゼロ）'}")
_dup = len(emitted_dot_fids) - len(set(emitted_dot_fids))
print(f"[A1-4] 重複描画                : {_dup} 件（期待 0）")
print(f"[A1-5] pass_all 集計           : TRUE {n_fires_pass} / FALSE {n_fires_supp}（合計 {n_fires_total}）")
print(f"[A1-6] JST土曜発火の金曜セル併載: {emitted_fold_count} 件（=サーバー金曜深夜、5列レイアウト維持の設計判断）")
print(f"[A2-1] ドロワー用トレード      : {n_drill_trades} 件 / {n_drill_trade_days} 日（成績側・Mac専管）")
_fire_days_in_cells = set(fires_by_cell.keys())
_trade_only_days = sorted(str(d) for d in drill_trades_by_date if d not in _fire_days_in_cells)
print(f"[A2-2] 発火ゼロのトレード日    : {len(_trade_only_days)} 日 {_trade_only_days}（クリック可・ドロワー対応）")
_html_text = "\n".join(html)
print(f"[A3-1] SC表記の削除            : セル内 'adx-tiny' 出現 {_html_text.count('adx-tiny" style=') + _html_text.count('class=\"adx-tiny\">')} 箇所（期待 0、CSS定義は残置）")
print(f"[A3-2] title内スコア残存       : 'スコア=' 出現 {_html_text.count('スコア=')} 箇所（>0 で残存OK）")

# ===== Step 2 検証 =====
print()
print(f"[B1-1] fireCard 閉じタグ修正    : {'OK（mmSteps(f) + `</div>` 出力済み）' if 'mmSteps(f) + `</div>`' in _html_text else 'NG'}")
print(f"[B2-1] デフォルト表示ドット数  : {emitted_dot_count - emitted_supp_dot_count} 件（= pass_all のみ {n_fires_pass}）")
print(f"[B2-2] 全発火表示時ドット数    : {emitted_dot_count} 件（全 {n_fires_total} 件、抑制 {emitted_supp_dot_count} 件は薄表示）")
print(f"[B2-3] フィルタートグルUI      : {'OK' if 'v3-show-suppressed' in _html_text else 'NG'} / ヘッダー連動 {'OK' if 'v3-fire-summary' in _html_text else 'NG'}")
print(f"[B3-1] デフォルト表示開始月    : {default_start_month:%Y-%m}（期待 2026-03 = トレードログ基準 / 直近6ヶ月上限）")
print(f"[B3-2] 折りたたみ過去月        : {past_months[0]:%Y-%m}〜{past_months[-1]:%Y-%m} の {len(past_months)} ヶ月（details 出現 {_html_text.count('class=\"past-months\"')} 箇所、期待 1）")

assert "mmSteps(f) + `</div>`" in _html_text, "B1: fireCard 閉じタグ修正が反映されていない"
assert emitted_dot_count - emitted_supp_dot_count == n_fires_pass, "B2: デフォルト表示ドット数が pass_all 件数と不一致"
assert _html_text.count('class="past-months"') == 1, "B3: 過去月 details ラッパーが1個ではない"
assert default_start_month == date(2026, 3, 1), "B3: デフォルト表示開始月が 2026-03 ではない"

assert n_fires_total > 0, "CSV件数がゼロ（signal_fires.csv 未受信?）"
assert emitted_dot_count == n_fires_total, "HTML描画 fire-dot 数がCSV件数と不一致（描画漏れ）"
assert not _missing_fids and _dup == 0, "fire_id の欠落または重複あり"
assert n_fires_pass + n_fires_supp == n_fires_total, "pass_all 集計がCSV件数と不整合"
assert n_drill_trade_days <= n_drill_trades, "トレード日数が件数を超過（不整合）"
assert "adx-tiny\">" not in _html_text and "adx-tiny\" style=" not in _html_text, "SC表記が残っている"
assert "スコア=" in _html_text, "title内スコアまで消えている（A3はテキスト削除のみが仕様）"
print()
print("全チェック PASS ✅")
