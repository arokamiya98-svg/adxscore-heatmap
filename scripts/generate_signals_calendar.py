#!/usr/bin/env python3
"""
generate_signals_calendar.py
────────────────────────────
統合評価シート v2.0（v1: シグナル検証カレンダー からの進化）
指示書: data/mani_room/マニ_指示書_統合評価シート_v0.2.md
        （v1 指示書 マニ_指示書_シグナル検証カレンダー_v0.1.md の仕様・禁止事項は継続有効）

目的（v2 更新）:
  シグナル発火 × トレード実行の同時認知。
  「シグナルが出てた日、自分はどう執行したか」が1画面で見える。
  主軸は「認知負荷を下げて戦略実行精度を上げる」— 解析機能の追加ではない。
  - 月別・損益集計の類は作らない（研究ルール準拠、継続）
  - トレードカードに損益額・ロット・累計系は出さない（禁止、指示書 §3.1）

v2.0 変更点:
  (1) ドリルダウン: トレード日はシグナルカードの下に「実トレードカード」追加
      - 表示項目（これだけ）: 方向▲▼ / entry→exit JST時刻 / pips（符号で勝敗）/
        スタイル / ★時間帯ラベル / タグ / h1 MFE/MAE 12/24/36/48h / 新規理由（折りたたみ）
      - 核心: MFE/MAE 推移をシグナルカードと同一フォーマット（mm-steps）で表示
        →「シグナルの伸び方」と「自分の執行の置かれた環境」を同じ言語で対比
      - pips 表示はCSV生値/100（= USD価格幅。MFE/MAE と同スケールに揃える設計判断）
      - タグは「反省」列（意思決定の正本、generate_daily_calendar v1.4 と同じ参照先）
      - 新規理由はデフォルト閉の <details>（認知負荷対策）
  (2) セルのトレード日マーク（枠線+方向）をデフォルト ON に変更（トグルは維持）
  (3) トレードのみの日（発火ゼロ）もセルクリックでドリルダウン可能に

設計判断（マニ）:
  (1) カレンダーは月〜土の6列グリッド
      - signal_fires.csv は JST 日付基準。サーバー金曜深夜 = JST 土曜の発火が
        31件存在する（weekday 分布: 月80/火51/水69/木97/金61/土31）
      - daily_calendar の月〜金 5列を流用すると土曜発火31件が欠落し
        「389件全件表示」の完了条件を満たせない → 6列に拡張
  (2) 日セルのドットは「全件描画」（+n 集約はしない）
      - 最大14件/日。flex-wrap の小グリフで全件入る
      - 集約するとフィルター切替時の表示数管理が複雑化し、
        「欠落ゼロ」の検証可能性も下がるため全件描画を採用
  (3) ドットの言語 = v4 実機と完全一致
      - 色 = パターン（v4矢印色テーブル）、形 = 方向（▲BUY / ▼SELL）
      - 色を方向に使わない（v4と同じ視覚言語、認識の一貫性）
  (4) pass_all=FALSE は opacity 0.3 の薄表示
      - 「実機なら見えなかった発火」の見える化（本ツールの核心）
  (5) ドット描画は in-month セルのみ
      - 週の端で隣月セルが重複描画されると 389 件カウントが壊れるため
        outside セルにはドットを置かない
  (6) ドリルダウンは右サイドの固定ドロワー
      - 16ヶ月分の縦長カレンダーをスクロールしながら日クリックで参照できる

入力:
    mt5_data/signal_fires.csv                       (UTF-8-sig, 64列×389行)
    data/mani_room/enriched/trades_enriched_full.csv (UTF-8-sig, オーバーレイ用)
出力:
    data/trades/processed/signals_calendar.html （自己完結HTML、外部依存なし）
"""
import csv
import json
from collections import defaultdict
from datetime import datetime, timedelta, date
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FIRES_CSV = ROOT / "mt5_data" / "signal_fires.csv"
ENRICHED = ROOT / "data" / "mani_room" / "enriched" / "trades_enriched_full.csv"
OUT = ROOT / "data" / "trades" / "processed"
OUT.mkdir(parents=True, exist_ok=True)
OUT_HTML = OUT / "signals_calendar.html"

# ============================================================
# v4 実機 矢印色テーブル（指示書 §3.2、完全一致・変更禁止）
# ============================================================
PATTERN_COLORS = {
    "PatA": {"BUY": "#FFD700", "SELL": "#DAA520"},  # Gold / Goldenrod
    "PatB": {"BUY": "#00FFFF", "SELL": "#00BFFF"},  # Aqua / DeepSkyBlue
    "PatC": {"BUY": "#32CD32", "SELL": "#2E8B57"},  # LimeGreen / SeaGreen
    "PatD": {"BUY": "#FF00FF", "SELL": "#C71585"},  # Magenta / MediumVioletRed
    "PatE": {"BUY": "#FFA500", "SELL": "#FF8C00"},  # Orange / DarkOrange
}
PATTERNS = ["PatA", "PatB", "PatC", "PatD", "PatE"]

# フィルター列 → 表示名（v4 の F1〜F9）
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

# ============================================================
# ユーティリティ
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
# 入力: signal_fires.csv
# ⚠️ 必ず utf-8-sig。utf-8 だと先頭列キーが "﻿fire_id" になり全マッチ失敗
#    （BOM事件、generate_daily_calendar.py v0.2 bugfix 参照）
# ============================================================
with open(FIRES_CSV, encoding="utf-8-sig") as f:
    raw_rows = list(csv.DictReader(f))

assert "fire_id" in raw_rows[0], f"BOM混入の疑い: 先頭キー={list(raw_rows[0].keys())[0]!r}"

fires = []
for r in raw_rows:
    d = datetime.strptime(r["date"], "%Y-%m-%d").date()
    hits = [label for col, label in FILTER_COLS if r.get(col) == "TRUE"]
    fires.append({
        "fid": r["fire_id"],
        "date": r["date"],
        "_d": d,
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
        "h1_di_spread": _f(r["h1_di_spread"]),
        "h4_adx_zone": r["h4_adx_zone"],
        "h4_adx46": _f(r["h4_adx46"]),
        "h4_di_spread": _f(r["h4_di_spread"]),
        "h4_cross_dir": r["h4_cross_dir"],
        "h4_cross_bars": r["h4_cross_bars"],
        "cross_dir": r["cross_dir"],               # D1 ATRクロス局面 BU/PD/NONE
        "d1_cross_bars": r["d1_cross_bars"],
        "d1_adx22": _f(r["d1_adx22"]),
        "d1_di_dir": r["d1_di_dir"],
        # MFE/MAE 推移（48h固定追跡、研究ルール準拠の固定窓）
        "mfe": [_f(r["mfe_12h"]), _f(r["mfe_24h"]), _f(r["mfe_36h"]), _f(r["mfe_48h"])],
        "mae": [_f(r["mae_12h"]), _f(r["mae_24h"]), _f(r["mae_36h"]), _f(r["mae_48h"])],
        "bars_traced": _f(r["bars_traced"]),
    })

fires.sort(key=lambda x: (x["date"], x["time_jst"], int(x["fid"])))
fires_by_date = defaultdict(list)
for fr in fires:
    fires_by_date[fr["_d"]].append(fr)

n_total = len(fires)
n_pass = sum(1 for fr in fires if fr["pass_all"])
n_supp = n_total - n_pass

# ============================================================
# 入力: trades_enriched_full.csv（v2: トレードカード用フルデータ）
# ⚠️ utf-8-sig 必須（BOM事件再発防止）
#
# 設計判断（マニ v2）:
#   - pips: CSV はポイント値（0.01刻み、例 -4000.0）。/100 で USD 価格幅に変換
#     （検算: T001 entry 5020.00 → exit 4980.00 = -40.0、CSV pips=-4000.0 ✓）
#     → MFE/MAE（USD価格幅）と同スケールになり「同じ言語での対比」が成立する
#   - タグ = 「反省」列（あろさんの意思決定の正本。daily_calendar v1.4 と同じ参照先）
#     「その他」は控えめ表示 / 空欄は非表示
#   - ★ = 「評価」列（時間帯ラベル）。数値をそのまま ★N 表示、優劣解釈しない
#   - 出さないもの: 損益額・ロット・累計系・考察・決済理由（指示書 §3.1 禁止）
# ============================================================
trades = []
trades_by_date = defaultdict(list)
if ENRICHED.exists():
    with open(ENRICHED, encoding="utf-8-sig") as f:
        e_rows = list(csv.DictReader(f))
    assert "trade_id" in e_rows[0], f"BOM混入の疑い: 先頭キー={list(e_rows[0].keys())[0]!r}"
    for r in e_rows:
        ej = (r.get("entry_jst") or "").strip()
        if not ej:
            continue
        try:
            d = datetime.strptime(ej[:10], "%Y-%m-%d").date()
        except ValueError:
            continue
        ex = (r.get("exit_jst") or "").strip()
        if ex:
            # 同日決済は HH:MM、日跨ぎは MM-DD HH:MM（日付跨ぎ明示、シグナルカードと同流儀）
            exit_disp = ex[11:16] if ex[:10] == ej[:10] else ex[5:16]
        else:
            exit_disp = "—"
        pips_raw = _f(r.get("pips"))
        trades.append({
            "tid": r.get("trade_id", "").strip(),
            "date": ej[:10],
            "_d": d,
            "entry_time": ej[11:16],
            "exit_disp": exit_disp,
            "direction": (r.get("direction") or "").upper(),
            "pips": None if pips_raw is None else pips_raw / 100.0,  # USD価格幅（MFE/MAEと同スケール）
            "style": (r.get("スタイル") or "").strip(),
            "star": (r.get("評価") or "").strip(),
            "tag": (r.get("反省") or "").strip(),
            "reason": (r.get("新規理由") or "").strip(),
            # MFE/MAE 推移（シグナルカードと同一フォーマットで表示するための同キー構造）
            "mfe": [_f(r.get("h1_mfe_usd_12h")), _f(r.get("h1_mfe_usd_24h")),
                    _f(r.get("h1_mfe_usd_36h")), _f(r.get("h1_mfe_usd_48h"))],
            "mae": [_f(r.get("h1_mae_usd_12h")), _f(r.get("h1_mae_usd_24h")),
                    _f(r.get("h1_mae_usd_36h")), _f(r.get("h1_mae_usd_48h"))],
            "bars_traced": _f(r.get("h1_bars_traced_48h")),
        })
trades.sort(key=lambda t: (t["date"], t["entry_time"]))
for t in trades:
    trades_by_date[t["_d"]].append(t)
n_trades = len(trades)
n_trade_days = len(trades_by_date)

# ============================================================
# カレンダー期間（CSVから自動: 月初〜最終月の翌月頭）
# ============================================================
all_fire_dates = sorted(fires_by_date.keys())
start = all_fire_dates[0].replace(day=1)
end_d = all_fire_dates[-1]
end = (end_d.replace(day=28) + timedelta(days=4)).replace(day=1)

def month_iter(s, e):
    cur = s
    while cur < e:
        yield cur
        cur = cur.replace(year=cur.year + 1, month=1) if cur.month == 12 else cur.replace(month=cur.month + 1)

def month_weekdays_sat(year, month):
    """月内の月〜土を週グループで返す（土曜発火31件があるため6列）"""
    first = date(year, month, 1)
    start_d = first - timedelta(days=first.weekday())
    last_day = (date(year + 1, 1, 1) - timedelta(days=1)) if month == 12 else (date(year, month + 1, 1) - timedelta(days=1))
    end_dd = last_day + timedelta(days=(6 - last_day.weekday()))
    cur = start_d
    weeks_list, cur_week = [], []
    while cur <= end_dd:
        if cur.weekday() < 6:  # 月〜土
            cur_week.append(cur)
        if cur.weekday() == 5:  # 土曜で区切り
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
<title>評価シート — シグナル × 実トレード</title>
<style>
* { box-sizing: border-box; }
body {
  margin: 0; background: #05090f; color: #8abaee;
  font-family: -apple-system, BlinkMacSystemFont, 'Hiragino Sans', sans-serif;
  font-size: 12px; padding: 20px;
}
h1 { font-size: 14px; color: #5a9adf; margin: 0 0 4px; letter-spacing: .08em; }
.sub { font-size: 10px; color: #2a4a6a; margin-bottom: 14px; }
.purpose {
  font-size: 10px; color: #4a6a8a; margin-bottom: 14px; line-height: 1.6;
  padding: 8px 12px; background: #080d16; border: 1px solid #162844; border-radius: 6px;
}
.purpose b { color: #6a8aaa; }

/* ===== フィルターバー ===== */
.filter-bar {
  position: sticky; top: 0; z-index: 50;
  display: flex; flex-wrap: wrap; gap: 10px 18px;
  padding: 10px 14px; background: #080d16ee;
  border: 1px solid #1a2a44; border-radius: 6px;
  margin-bottom: 14px; align-items: center;
  backdrop-filter: blur(4px);
}
.filter-bar .fgrp { display: flex; align-items: center; gap: 7px; }
.filter-bar .fttl { font-size: 9.5px; color: #4a6a8a; letter-spacing: .05em; }
.pat-cb {
  display: inline-flex; align-items: center; gap: 4px;
  font-size: 10.5px; cursor: pointer; user-select: none;
  padding: 2px 7px; border-radius: 3px;
  border: 1px solid #1a3454; background: #0a1320;
  color: #c8d8e8; transition: opacity .15s;
}
.pat-cb input { display: none; }
.pat-cb .sw { width: 9px; height: 9px; border-radius: 2px; display: inline-block; }
.pat-cb.off { opacity: 0.3; }
.seg-btn {
  background: #0a1320; color: #6a8aaa;
  border: 1px solid #1a3454; padding: 3px 11px;
  font-size: 10.5px; cursor: pointer; font-family: inherit;
  transition: background .15s, color .15s;
}
.seg-btn:first-of-type { border-radius: 3px 0 0 3px; }
.seg-btn:last-of-type { border-radius: 0 3px 3px 0; }
.seg-btn + .seg-btn { border-left: none; }
.seg-btn.active { background: #1a3a6a; color: #d8e8f8; font-weight: 700; }
.trade-toggle {
  background: #0a1320; color: #6a8aaa;
  border: 1px solid #1a3454; border-radius: 3px;
  padding: 3px 11px; font-size: 10.5px; cursor: pointer; font-family: inherit;
}
.trade-toggle.active { background: #3a2a0a; color: #ffd060; border-color: #6a5a2a; font-weight: 700; }
#visible-count { font-size: 11px; color: #8abaee; font-weight: 700; font-variant-numeric: tabular-nums; }
#visible-count .dim { color: #4a6a8a; font-weight: 400; }

/* ===== 凡例 ===== */
.legend {
  display: flex; gap: 18px; margin-bottom: 18px; flex-wrap: wrap;
  font-size: 10px; color: #6a8aaa;
  padding: 10px 14px; background: #080d16;
  border: 1px solid #162844; border-radius: 6px;
  align-items: center;
}
.legend .grp { display: flex; gap: 8px; align-items: center; flex-wrap: wrap; }
.legend .ttl { color: #4a7aaa; font-weight: 600; margin-right: 2px; }
.legend .lg-dot { font-size: 11px; }

/* ===== 月 ===== */
.month {
  margin-bottom: 24px; border: 1px solid #162844;
  border-radius: 6px; background: #080d16; padding: 12px;
}
.month-title { font-size: 13px; color: #5a9adf; margin-bottom: 2px; font-weight: 600; letter-spacing: .05em; }
.month-stats { font-size: 10px; color: #4a7aaa; margin-bottom: 8px; }
.dow-row { display: grid; grid-template-columns: repeat(6, 1fr); gap: 3px; padding: 0 3px; margin-bottom: 2px; }
.dow { text-align: center; font-size: 10px; color: #2a4a6a; font-weight: 600; padding: 3px 0; letter-spacing: .08em; }
.dow.sat { color: #3a5a8a; }
.week-cells {
  display: grid; grid-template-columns: repeat(6, 1fr); gap: 3px;
  background: rgba(0,0,0,0.2); padding: 3px; border-radius: 3px;
  margin-bottom: 4px;
}

/* ===== 日セル ===== */
.cell {
  border-radius: 4px; min-height: 64px;
  background: #0a0f18; border: 1px solid #0b1825;
  position: relative; overflow: hidden;
  display: flex; flex-direction: column;
}
.cell.outside { opacity: 0.15; }
.cell.has-fires, .cell.has-trade { cursor: pointer; }
.cell.has-fires:hover, .cell.has-trade:hover { border-color: #2a5a9a; background: #0c1422; }
.cell.drill-open { border-color: #4a90e2; box-shadow: inset 0 0 0 1px #4a90e2; }
.cell .day-hdr {
  display: flex; justify-content: space-between; align-items: center;
  padding: 2px 5px; font-size: 10px; font-weight: 600; color: #6a8aaa;
  background: rgba(0,0,0,0.3);
}
.cell .fires-box {
  flex: 1; display: flex; flex-wrap: wrap; align-content: flex-start;
  gap: 1px 2px; padding: 3px 4px;
}
.fire-dot {
  font-size: 11px; line-height: 1.1;
  text-shadow: 0 1px 2px rgba(0,0,0,0.7);
}
.fire-dot.suppressed { opacity: 0.3; }   /* pass_all=FALSE: 実機なら見えなかった発火 */
.fire-dot.fhide { display: none; }        /* フィルターで非表示 */
/* 実トレードオーバーレイ（v2: デフォルトON、トグルで「シグナルのみ」へ即切替可） */
.cell .trade-mark {
  display: none;
  position: absolute; right: 3px; bottom: 2px;
  font-size: 9px; font-weight: 700; color: #ffd060;
  text-shadow: 0 1px 2px rgba(0,0,0,0.8);
  letter-spacing: .04em;
}
body.show-trades .cell.has-trade { box-shadow: inset 0 0 0 2px rgba(255,208,96,0.55); }
body.show-trades .cell .trade-mark { display: block; }

/* ===== ドリルダウンドロワー ===== */
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
/* MFE/MAE ステップバー */
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

/* ===== v2: 実トレードカード（シグナルカードの下、トレード日のみ） ===== */
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

.notes { margin-top: 10px; font-size: 10px; color: #4a6a8a; line-height: 1.6; }
.notes b { color: #6a8aaa; }
</style></head><body class="show-trades">
""")

gen_ts = datetime.now().strftime("%Y-%m-%d %H:%M")
html.append('<h1>評価シート — シグナル発火 × 実トレード（マニ v2.0）</h1>')
html.append(f'<div class="sub">入力: {FIRES_CSV.name} / 発火 {n_total}件 (pass {n_pass} / 抑制 {n_supp}) / '
            f'期間: {all_fire_dates[0]:%Y-%m-%d} 〜 {all_fire_dates[-1]:%Y-%m-%d} / '
            f'実トレード {n_trades}件・{n_trade_days}日 / 生成: {gen_ts}</div>')
html.append('<div class="purpose"><b>目的:</b> シグナル発火とトレード実行を1画面で同時認知して、認知負荷を下げて戦略実行精度を上げる。'
            '解析ツールではない。トレード日をクリックすると、シグナルカードの下に実トレードカード（同一フォーマットの MFE/MAE 推移付き）。'
            '<b>薄いドット = pass_all=FALSE（フィルター抑制、実機チャートには出ていない発火）</b>。'
            '日付は JST 基準（サーバー金曜深夜 = JST 土曜の発火があるため土曜列あり）。</div>')

# ===== フィルターバー =====
html.append('<div class="filter-bar">')
html.append('<div class="fgrp"><span class="fttl">パターン:</span>')
for p in PATTERNS:
    c_buy = PATTERN_COLORS[p]["BUY"]
    html.append(f'<label class="pat-cb" data-pat="{p}"><input type="checkbox" checked>'
                f'<span class="sw" style="background:{c_buy};"></span>{p}</label>')
html.append('</div>')
html.append('<div class="fgrp"><span class="fttl">発火:</span>'
            '<button class="seg-btn active" data-pass="all">全発火</button>'
            '<button class="seg-btn" data-pass="pass">pass_all のみ</button></div>')
html.append('<div class="fgrp"><span class="fttl">方向:</span>'
            '<button class="seg-btn active" data-dir="ALL">ALL</button>'
            '<button class="seg-btn" data-dir="BUY">BUY ▲</button>'
            '<button class="seg-btn" data-dir="SELL">SELL ▼</button></div>')
html.append('<div class="fgrp"><button class="trade-toggle active" id="trade-toggle">実トレード表示 ON</button></div>')
html.append(f'<div class="fgrp"><span id="visible-count"></span></div>')
html.append('</div>')

# ===== 凡例 =====
html.append('<div class="legend">')
html.append('<div class="grp"><span class="ttl">色=パターン (v4矢印色と同一):</span>')
for p in PATTERNS:
    html.append(f'<span class="lg-dot"><span style="color:{PATTERN_COLORS[p]["BUY"]};">▲</span>'
                f'<span style="color:{PATTERN_COLORS[p]["SELL"]};">▼</span> {p}</span>')
html.append('</div>')
html.append('<div class="grp"><span class="ttl">形=方向:</span><span>▲ BUY / ▼ SELL（色は方向に使わない）</span></div>')
html.append('<div class="grp"><span class="ttl">薄表示:</span>'
            '<span class="lg-dot" style="opacity:0.3;color:#FFD700;">▲</span>'
            '<span>pass_all=FALSE（フィルター抑制 = 実機では見えなかった発火）</span></div>')
html.append('<div class="grp"><span class="ttl">実トレード(デフォルトON):</span>'
            '<span style="box-shadow: inset 0 0 0 2px rgba(255,208,96,0.55); padding:1px 6px; border-radius:3px;">枠</span>'
            '<span style="color:#ffd060;font-weight:700;">▲/▼=エントリー方向</span>'
            '<span style="opacity:0.6;">詳細は日クリック（トグルOFFで「シグナルのみ」表示）</span></div>')
html.append('</div>')

# ===== 月ループ =====
emitted_dot_count = 0          # 検証用: HTML に出した fire-dot 数
emitted_dot_fids = []          # 検証用: 出した fire_id
cell_dates_rendered = set()    # 検証用: in-month セルの日付集合
emitted_trade_cells = set()    # 検証用: has-trade セルの日付集合（v2）
emitted_trade_marks = 0        # 検証用: トレード方向マーク総数（v2）
DOW_LABELS = ["月", "火", "水", "木", "金", "土"]

for m_start in month_iter(start, end):
    weeks_list = month_weekdays_sat(m_start.year, m_start.month)
    m_fires = [fr for d, frs in fires_by_date.items()
               if d.year == m_start.year and d.month == m_start.month for fr in frs]
    m_pass = sum(1 for fr in m_fires if fr["pass_all"])
    m_supp = len(m_fires) - m_pass

    html.append('<div class="month">')
    html.append(f'<div class="month-title">{m_start.year}年 {m_start.month}月</div>')
    html.append(f'<div class="month-stats">発火 {len(m_fires)}件（pass {m_pass} / 抑制 {m_supp}）</div>')
    html.append('<div class="dow-row">')
    for i, dow in enumerate(DOW_LABELS):
        html.append(f'<div class="dow{" sat" if i == 5 else ""}">{dow}</div>')
    html.append('</div>')

    for week_days in weeks_list:
        html.append('<div class="week-cells">')
        for d in week_days:
            is_outside = d.month != m_start.month
            if is_outside:
                # outside セルにはドットを描画しない（隣月との二重描画防止 → 389件保証）
                html.append(f'<div class="cell outside"><div class="day-hdr"><span>{d.day}</span></div></div>')
                continue

            cell_dates_rendered.add(d)
            day_fires = fires_by_date.get(d, [])
            day_trades = trades_by_date.get(d, [])
            classes = ["cell"]
            if day_fires:
                classes.append("has-fires")
            if day_trades:
                classes.append("has-trade")

            tip_parts = [f"{d:%Y-%m-%d} ({['月','火','水','木','金','土','日'][d.weekday()]})"]
            for fr in day_fires:
                state = "pass" if fr["pass_all"] else "抑制"
                tip_parts.append(f"{fr['time_jst']} {fr['pattern']} {fr['direction']} ({state})")
            for t in day_trades:
                tip_parts.append(f"実トレード {t['entry_time']} {t['direction']}")
            title = " | ".join(tip_parts)

            html.append(f'<div class="{" ".join(classes)}" data-date="{d:%Y-%m-%d}" title="{title}">')
            html.append('<div class="day-hdr">')
            html.append(f'<span>{d.day}</span>')
            if day_fires:
                html.append(f'<span style="font-size:8px;color:#3a5a7a;">{len(day_fires)}</span>')
            html.append('</div>')
            html.append('<div class="fires-box">')
            for fr in day_fires:
                col = PATTERN_COLORS[fr["pattern"]][fr["direction"]]
                glyph = "▲" if fr["direction"] == "BUY" else "▼"
                supp_cls = "" if fr["pass_all"] else " suppressed"
                html.append(f'<span class="fire-dot{supp_cls}" data-fid="{fr["fid"]}" '
                            f'data-pat="{fr["pattern"]}" data-dir="{fr["direction"]}" '
                            f'data-pass="{1 if fr["pass_all"] else 0}" '
                            f'style="color:{col};">{glyph}</span>')
                emitted_dot_count += 1
                emitted_dot_fids.append(fr["fid"])
            html.append('</div>')
            if day_trades:
                marks = "".join("▲" if t["direction"] == "BUY" else "▼" for t in day_trades)
                html.append(f'<span class="trade-mark">{marks}</span>')
                emitted_trade_cells.add(d)
                emitted_trade_marks += len(day_trades)
            html.append('</div>')
        html.append('</div>')
    html.append('</div>')

html.append('<div class="notes">'
            '<b>注:</b> サーバー時間 = チャート表示時間（ドリルダウンに併記、チャート照合用）。'
            'MFE/MAE は発火/エントリー後 48h 固定追跡（12/24/36/48h スナップショット、USD建て）。'
            '環境値は段階ラベル優先（生値は括弧内の補助表示）。'
            'トレードカードの pips は価格幅（USD換算、MFE/MAE と同スケール）。'
            'このツールはシグナル×実行の同時認知用 — 月別・累計の損益/勝率サマリーは置かない（研究ルール準拠）。'
            '</div>')

# ============================================================
# JSON データ埋め込み（ドリルダウン用、自己完結HTML）
# ============================================================
fires_json = [{k: v for k, v in fr.items() if k != "_d"} for fr in fires]
json_blob = json.dumps(fires_json, ensure_ascii=False).replace("</", "<\\/")
colors_blob = json.dumps(PATTERN_COLORS)
trades_json = [{k: v for k, v in t.items() if k != "_d"} for t in trades]
trades_blob = json.dumps(trades_json, ensure_ascii=False).replace("</", "<\\/")

html.append('<div id="drill">'
            '<div class="drill-head"><span class="drill-title" id="drill-title"></span>'
            '<button class="drill-close" id="drill-close">閉じる ✕</button></div>'
            '<div class="drill-note">サーバー時間 = チャート表示時間（照合用）。'
            '薄カード = pass_all=FALSE（実機チャート非表示の発火）。バー長 = カード内の最大値基準（伸び方の形を見る用）。'
            'トレードカードの pips は価格幅（USD、MFE/MAE と同スケール）。</div>'
            '<div class="drill-body" id="drill-body"></div></div>')

html.append("<script>")
html.append(f"const FIRES = {json_blob};")
html.append(f"const PAT_COLORS = {colors_blob};")
html.append(f"const TRADES = {trades_blob};")
html.append("""
// ============ インデックス ============
const byDate = {};
for (const f of FIRES) {
  (byDate[f.date] = byDate[f.date] || []).push(f);
}
const tradesByDate = {};
for (const t of TRADES) {
  (tradesByDate[t.date] = tradesByDate[t.date] || []).push(t);
}

// ============ フィルター状態 ============
const state = { pats: new Set(["PatA","PatB","PatC","PatD","PatE"]), pass: "all", dir: "ALL" };

function fireVisible(pat, dir, pass) {
  if (!state.pats.has(pat)) return false;
  if (state.pass === "pass" && !pass) return false;
  if (state.dir !== "ALL" && dir !== state.dir) return false;
  return true;
}

function applyFilters() {
  let vis = 0, visPass = 0, visSupp = 0;
  document.querySelectorAll(".fire-dot").forEach(el => {
    const ok = fireVisible(el.dataset.pat, el.dataset.dir, el.dataset.pass === "1");
    el.classList.toggle("fhide", !ok);
    if (ok) { vis++; if (el.dataset.pass === "1") visPass++; else visSupp++; }
  });
  const total = document.querySelectorAll(".fire-dot").length;
  document.getElementById("visible-count").innerHTML =
    `表示中 ${vis} <span class="dim">/ ${total}件（pass ${visPass} / 抑制 ${visSupp}）</span>`;
  // ドリルダウンが開いていれば再描画（フィルター連動）
  if (openDate) renderDrill(openDate);
}

// パターンチェックボックス
document.querySelectorAll(".pat-cb").forEach(lbl => {
  lbl.addEventListener("change", () => {
    const p = lbl.dataset.pat;
    if (lbl.querySelector("input").checked) { state.pats.add(p); lbl.classList.remove("off"); }
    else { state.pats.delete(p); lbl.classList.add("off"); }
    applyFilters();
  });
});
// pass 切替
document.querySelectorAll(".seg-btn[data-pass]").forEach(btn => {
  btn.addEventListener("click", () => {
    document.querySelectorAll(".seg-btn[data-pass]").forEach(b => b.classList.remove("active"));
    btn.classList.add("active");
    state.pass = btn.dataset.pass;
    applyFilters();
  });
});
// 方向切替
document.querySelectorAll(".seg-btn[data-dir]").forEach(btn => {
  btn.addEventListener("click", () => {
    document.querySelectorAll(".seg-btn[data-dir]").forEach(b => b.classList.remove("active"));
    btn.classList.add("active");
    state.dir = btn.dataset.dir;
    applyFilters();
  });
});
// 実トレードオーバーレイ（有無+方向のみ）
const tradeBtn = document.getElementById("trade-toggle");
tradeBtn.addEventListener("click", () => {
  const on = document.body.classList.toggle("show-trades");
  tradeBtn.classList.toggle("active", on);
  tradeBtn.textContent = on ? "実トレード表示 ON" : "実トレード表示 OFF";
});

// ============ ドリルダウン ============
let openDate = null;
const drill = document.getElementById("drill");

function fmt(v, digits) {
  return (v === null || v === undefined) ? "—" : v.toFixed(digits === undefined ? 1 : digits);
}

function mmSteps(f) {
  // カード内最大値で正規化 → 「伸び方の形」を見る
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
  const col = PAT_COLORS[f.pattern][f.direction];
  const glyph = f.direction === "BUY" ? "▲" : "▼";
  const passHtml = f.pass_all
    ? '<span class="fc-pass ok">pass_all ✅</span>'
    : '<span class="fc-pass ng">抑制 ⛔</span>';
  const filt = f.filter_hits.length
    ? `<div class="fc-filters hit">フィルター: ${f.filter_hits.join(", ")} にヒット → 実機非表示</div>`
    : '<div class="fc-filters nohit">フィルター: 9本中ヒットなし</div>';
  return `<div class="fire-card${f.pass_all ? "" : " suppressed"}">` +
    `<div class="fc-head"><span class="fc-pat" style="background:${col};">${f.pattern} ${glyph}${f.direction}</span>` +
    `<span class="fc-time">${f.time_jst} JST</span>` +
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
    filt + mmSteps(f);
}

// ============ v2: 実トレードカード ============
// シグナルカードと同一フォーマットの MFE/MAE 推移（mmSteps を共用）— 認知サポートの核心
function esc(s) {
  return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
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

function renderDrill(dateStr) {
  openDate = dateStr;
  const all = byDate[dateStr] || [];
  const dayTrades = tradesByDate[dateStr] || [];
  const shown = all.filter(f => fireVisible(f.pattern, f.direction, f.pass_all));
  const hidden = all.length - shown.length;
  document.getElementById("drill-title").textContent =
    `${dateStr} — 発火 ${all.length}件${hidden ? `（フィルターで ${hidden} 件非表示中）` : ""}` +
    (dayTrades.length ? ` / 実トレード ${dayTrades.length}件` : "");
  let body;
  if (shown.length) {
    body = shown.map(fireCard).join("");
  } else if (all.length) {
    body = '<div style="color:#4a6a8a;font-size:11px;padding:20px 0;text-align:center;">現在のフィルター条件で表示できる発火がありません</div>';
  } else {
    body = '<div style="color:#4a6a8a;font-size:11px;padding:20px 0;text-align:center;">この日のシグナル発火はありません</div>';
  }
  if (dayTrades.length) {
    body += `<div class="trade-sec-hdr">実トレード ${dayTrades.length}件</div>` +
      dayTrades.map(tradeCard).join("");
  }
  document.getElementById("drill-body").innerHTML = body;
  drill.classList.add("open");
  document.querySelectorAll(".cell.drill-open").forEach(c => c.classList.remove("drill-open"));
  const cell = document.querySelector(`.cell[data-date="${dateStr}"]`);
  if (cell) cell.classList.add("drill-open");
}

document.querySelectorAll(".cell.has-fires, .cell.has-trade").forEach(cell => {
  cell.addEventListener("click", () => renderDrill(cell.dataset.date));
});
document.getElementById("drill-close").addEventListener("click", () => {
  drill.classList.remove("open");
  openDate = null;
  document.querySelectorAll(".cell.drill-open").forEach(c => c.classList.remove("drill-open"));
});

applyFilters();
""")
html.append("</script></body></html>")

OUT_HTML.write_text("\n".join(html), encoding="utf-8")

# ============================================================
# セルフチェック（完了条件の検証出力 — 指示書 §5）
# ============================================================
print("=" * 60)
print("signals_calendar.html セルフチェック (v2)")
print("=" * 60)
print(f"[1] CSV読込件数            : {n_total} 件（期待 389）")
print(f"[2] HTML描画 fire-dot 数   : {emitted_dot_count} 件（期待 389）")
missing_fids = set(fr["fid"] for fr in fires) - set(emitted_dot_fids)
print(f"[3] 欠落 fire_id           : {sorted(missing_fids) if missing_fids else 'なし（欠落ゼロ）'}")
dup = len(emitted_dot_fids) - len(set(emitted_dot_fids))
print(f"[4] 重複描画               : {dup} 件（期待 0）")
print(f"[5] pass_all 集計          : TRUE {n_pass} / FALSE {n_supp}（期待 265 / 124）")
not_in_cells = [d for d in fires_by_date if d not in cell_dates_rendered]
print(f"[6] セル未描画の発火日     : {not_in_cells if not_in_cells else 'なし（全発火日がカレンダー内）'}")
sat_fires = sum(len(v) for d, v in fires_by_date.items() if d.weekday() == 5)
sun_fires = sum(len(v) for d, v in fires_by_date.items() if d.weekday() == 6)
print(f"[7] 土曜発火（6列の根拠）  : {sat_fires} 件 / 日曜発火: {sun_fires} 件（日曜列は不要）")

assert n_total == 389, "CSV件数が389ではない"
assert emitted_dot_count == 389, "HTML描画数が389ではない"
assert not missing_fids and dup == 0, "欠落または重複あり"
assert (n_pass, n_supp) == (265, 124), "pass_all集計が指示書と不一致"
assert not not_in_cells, "カレンダー外の発火日あり"

# ----- v2: トレード統合の検証（指示書 v0.2 §4 完了条件） -----
print()
print(f"[v2-1] trades_enriched 読込    : {n_trades} 件 / {n_trade_days} 日（distinct entry_jst 日付）")
print(f"[v2-2] has-trade セル描画      : {len(emitted_trade_cells)} 日（期待 = {n_trade_days}）")
print(f"[v2-3] トレード方向マーク描画  : {emitted_trade_marks} 個（期待 = {n_trades}）")
trade_days_missing = set(trades_by_date.keys()) - emitted_trade_cells
print(f"[v2-4] セル未描画のトレード日  : {sorted(str(d) for d in trade_days_missing) if trade_days_missing else 'なし（全トレード日がカレンダー内）'}")
trade_only_days = sorted(str(d) for d in trades_by_date if d not in fires_by_date)
print(f"[v2-5] 発火ゼロのトレード日    : {len(trade_only_days)} 日 {trade_only_days}（クリック可・ドリルダウン対応）")
assert len(emitted_trade_cells) == n_trade_days, "トレード日セル数が不一致"
assert emitted_trade_marks == n_trades, "トレードマーク数が不一致"
assert not trade_days_missing, "カレンダー外のトレード日あり"

print()
print("[v2-6] トレードカード内容検証（サンプル日）:")
for ds in ("2026-05-29", "2026-06-02"):
    d_key = datetime.strptime(ds, "%Y-%m-%d").date()
    day_t = trades_by_date.get(d_key, [])
    day_f = fires_by_date.get(d_key, [])
    print(f"  {ds}: シグナル {len(day_f)}件 / 実トレード {len(day_t)}件")
    for t in day_t:
        pips_txt = "—" if t["pips"] is None else f"{t['pips']:+.1f}"
        meta = " ".join(x for x in (t["style"], f"★{t['star']}" if t["star"] else "", f"#{t['tag']}" if t["tag"] else "") if x)
        print(f"    [{t['direction']}] {t['entry_time']} → {t['exit_disp']} JST  {pips_txt} pips  {meta}")
        mm = " → ".join(f"{h}h: {mfe:.1f}/{mae:.1f}" for h, mfe, mae in
                        zip((12, 24, 36, 48), t["mfe"], t["mae"]))
        print(f"      MFE/MAE: {mm}")
        print(f"      新規理由: {'あり(折りたたみ・デフォルト閉)' if t['reason'] else 'なし'}")

print()
print("[8] ドリルダウン検証 (2026-06-04 / 2026-06-05):")
for ds in ("2026-06-04", "2026-06-05"):
    day = [fr for fr in fires if fr["date"] == ds]
    print(f"  {ds}: {len(day)} 件")
    for fr in day:
        hits = ", ".join(fr["filter_hits"]) if fr["filter_hits"] else "ヒットなし"
        print(f"    [{fr['pattern']} {fr['direction']}] {fr['time_jst']} JST (server {fr['time_server']}) "
              f"@ {fr['entry_price']:.2f} pass_all={'✅' if fr['pass_all'] else '⛔'}")
        print(f"      環境: ATR Zone={fr['atr_zone']} / H1 ADX={fr['h1_adx_zone']}({fr['h1_adx32']:.1f}) / "
              f"H1 pat={fr['h1_pattern']} / D1 cross={fr['cross_dir']}({fr['d1_cross_bars']}本) / "
              f"D1 DI={fr['d1_di_dir']} / H4 cross={fr['h4_cross_dir']} / H4 ADX={fr['h4_adx_zone']}({fr['h4_adx46']:.1f})")
        print(f"      フィルター: {hits}")
        mm = " → ".join(f"{h}h: {mfe:.1f}/{mae:.1f}" for h, mfe, mae in
                        zip((12, 24, 36, 48), fr["mfe"], fr["mae"]))
        print(f"      MFE/MAE: {mm}")
print()
print(f"出力: {OUT_HTML}")
print("全チェック PASS ✅")
