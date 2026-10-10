#!/usr/bin/env python3
"""
prepare_cent_input.py — セント口座（Exness USC）レーンの前処理（標準ライブラリのみ）

ガチ戦略レーン（FX記録アプリ → prepare_trade_input.py → T001〜）とは完全に別レーン。
ガチ側のファイル（trade_input.csv / trades_enriched*.csv）には一切触らない。

元データ: MT5 デスクトップ 履歴 → レポート → Open XML (xlsx) の「Positions」ブロック
  data/mani_room/raw/imports/ReportHistory_cent_*.xlsx（口座番号入り → .gitignore 済み）

このスクリプトの責務:
  1. xlsx の Positions ブロックをパース（セル参照で列を引く＝空セルでも列ズレしない）
  2. XAUUSDc → XAUUSD に正規化（銘柄原名は 銘柄原名 列に保持）
  3. サーバー時刻 → JST 変換（Exness MT5 = UTC 固定・DSTなし → +9h）
  4. trade_id = C001〜（エントリー時刻順。ガチ側 T 系列と衝突しない別系列）
  5. cent_trade_input.csv（Builder 入力・ガチと同スキーマ）を出力 → MT5 Files へ配置
  6. --merge: Builder 出力 cent_trades_enriched.csv と FX互換列をマージ
     → data/mani_room/enriched/cent_trades_enriched_full.csv（口座=cent タグ付き）

採番の前提: レポートは毎回「全期間」で出すこと（期間を絞ると C 番号がずれる＝7/18 採番衝突と同型）。
ポジションID・口座番号は出力に含めない（個人情報線引き 2026-06-19）。

使い方:
  # 1) 入力生成 + MT5 Files へ配置
  python3 scripts/prepare_cent_input.py
  # 2) MT5(HFM口座) で Trade_Snapshot_Builder を
  #    Input_File=cent_trade_input.csv / Output_File=cent_trades_enriched.csv で実行
  # 3) マージ
  python3 scripts/prepare_cent_input.py --merge
"""

import argparse
import csv
import shutil
import sys
import xml.etree.ElementTree as ET
import zipfile
from collections import OrderedDict
from datetime import datetime, timedelta
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from prepare_trade_input import get_server_offset_hours  # HFM(Builder実行側)のオフセット

ROOT = Path(__file__).resolve().parent.parent
IMPORTS = ROOT / "data" / "mani_room" / "raw" / "imports"
DEST = ROOT / "mt5_data"
INPUT_CSV = DEST / "cent_trade_input.csv"
ENRICHED_CSV = DEST / "cent_trades_enriched.csv"
ENRICHED_FULL = ROOT / "data" / "mani_room" / "enriched" / "cent_trades_enriched_full.csv"
MT5_FILES = Path("/Users/aro/Library/Application Support/net.metaquotes.wine.metatrader5/"
                 "drive_c/Program Files/MetaTrader 5/MQL5/Files")

ACCOUNT_TAG = "cent"
EXNESS_SERVER_UTC_OFFSET = 0  # Exness MT5 サーバー時刻 = UTC（DSTなし）
# 2026-10-11 検証: Twelve Data XAU/USD H1(UTC) で建値/決済値 12/12 が足レンジ内（UTC+1〜+3 は 3〜7/12）
NS = "{http://schemas.openxmlformats.org/spreadsheetml/2006/main}"


# ---------------- xlsx パース ----------------
def _col_letters(ref: str) -> str:
    return "".join(ch for ch in ref if ch.isalpha())


def read_xlsx_rows(path: Path):
    """sheet1 を [{列記号: 値}] で返す（空セルは欠番のまま）"""
    z = zipfile.ZipFile(path)
    shared = []
    if "xl/sharedStrings.xml" in z.namelist():
        for si in ET.fromstring(z.read("xl/sharedStrings.xml")).iter(NS + "si"):
            shared.append("".join(t.text or "" for t in si.iter(NS + "t")))
    root = ET.fromstring(z.read("xl/worksheets/sheet1.xml"))
    rows = []
    for row in root.iter(NS + "row"):
        cells = {}
        for c in row.findall(NS + "c"):
            v, inline = c.find(NS + "v"), c.find(NS + "is")
            if c.get("t") == "s" and v is not None:
                val = shared[int(v.text)]
            elif inline is not None:
                val = "".join(t.text or "" for t in inline.iter(NS + "t"))
            elif v is not None:
                val = v.text or ""
            else:
                continue
            cells[_col_letters(c.get("r", ""))] = val.strip()
        if cells:
            rows.append(cells)
    return rows


def parse_positions(path: Path):
    """Positions ブロック（ヘッダ行〜 Orders 見出しの手前）を dict 列で返す"""
    rows = read_xlsx_rows(path)
    out, header = [], None
    for cells in rows:
        first = cells.get("A", "")
        if header is None:
            if first == "Time" and "Position" in cells.values():
                # 列記号 → 列名（Time/Price が2回出るので2回目は close_ 接頭辞）
                header, seen = {}, set()
                for col in sorted(cells, key=lambda k: (len(k), k)):
                    name = cells[col]
                    header[col] = f"close_{name}" if name in seen else name
                    seen.add(name)
            continue
        if first in ("Orders", "Deals"):
            break
        rec = {header[col]: val for col, val in cells.items() if col in header}
        if rec.get("Symbol"):
            out.append(rec)
    if header is None:
        raise SystemExit(f"[ERR] Positions ブロックが見つからない: {path.name}")
    return out


# ---------------- 正規化 ----------------
def server_to_jst(s: str) -> datetime:
    dt = datetime.strptime(s, "%Y.%m.%d %H:%M:%S")
    return dt + timedelta(hours=9 - EXNESS_SERVER_UTC_OFFSET)


def build_trades(path: Path):
    trades = []
    for p in parse_positions(path):
        sym = p["Symbol"]
        if not sym.upper().startswith("XAUUSD"):
            continue
        direction = p["Type"].upper()  # buy / sell
        if direction not in ("BUY", "SELL"):
            continue
        entry_jst = server_to_jst(p["Time"])
        exit_jst = server_to_jst(p["close_Time"]) if p.get("close_Time") else None
        entry = float(p["Price"])
        exit_ = float(p["close_Price"]) if p.get("close_Price") else None
        sign = 1 if direction == "BUY" else -1
        trades.append({
            "entry_jst": entry_jst, "exit_jst": exit_jst, "direction": direction,
            "entry": entry, "exit": exit_, "symbol_raw": sym,
            "lot": p.get("Volume", ""), "sl": p.get("S / L", ""), "tp": p.get("T / P", ""),
            "profit": p.get("Profit", ""),
            # pips = ガチ側 FX CSV と同じポイント値（USD価格幅×100）
            "pips": "" if exit_ is None else f"{(exit_ - entry) * sign * 100:.1f}",
        })
    trades.sort(key=lambda t: t["entry_jst"])
    for i, t in enumerate(trades, start=1):
        t["trade_id"] = f"C{i:03d}"
    return trades


def latest_report() -> Path:
    files = sorted(IMPORTS.glob("ReportHistory_cent_*.xlsx"))
    if not files:
        raise SystemExit(f"[ERR] {IMPORTS}/ReportHistory_cent_*.xlsx が無い")
    return files[-1]


# ---------------- 出力 ----------------
def write_input(trades):
    rows = [OrderedDict([
        ("trade_id", t["trade_id"]),
        ("entry_jst", t["entry_jst"].strftime("%Y-%m-%d %H:%M")),
        ("exit_jst", t["exit_jst"].strftime("%Y-%m-%d %H:%M") if t["exit_jst"] else ""),
        ("direction", t["direction"]),
        ("entry_price", f"{t['entry']:.3f}"),
        ("server_offset_hours", get_server_offset_hours(t["entry_jst"].replace(second=0))),
    ]) for t in trades]
    with open(INPUT_CSV, "w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)
    print(f"[OK] {INPUT_CSV.relative_to(ROOT)} ({len(rows)} 件)")
    for r in rows:
        print("   " + ",".join(str(v) for v in r.values()))
    if MT5_FILES.exists():
        shutil.copy(INPUT_CSV, MT5_FILES / INPUT_CSV.name)
        print(f"[OK] MT5 Files/ へ配置 → Builder を Input_File={INPUT_CSV.name} / "
              f"Output_File={ENRICHED_CSV.name} で実行（HFM口座・XAUUSD H1 チャート）")
    else:
        print("[WARN] MT5 Files が見つからない → 配置スキップ")


def fx_columns(t):
    """ガチ側 FX CSV 互換列（カレンダーのトレードカードが読む列名に揃える）"""
    return OrderedDict([
        ("口座", ACCOUNT_TAG),
        ("約定日", t["entry_jst"].strftime("%Y/%m/%d %H:%M")),
        ("決済日", t["exit_jst"].strftime("%Y/%m/%d %H:%M") if t["exit_jst"] else ""),
        ("通貨ペア", "XAUUSD"),
        ("銘柄原名", t["symbol_raw"]),
        ("オーダー", "買い" if t["direction"] == "BUY" else "売り"),
        ("新規レート", f"{t['entry']:.3f}"),
        ("決済レート", "" if t["exit"] is None else f"{t['exit']:.3f}"),
        ("pips", t["pips"]),
        ("スタイル", ""),
        ("ロット", t["lot"]),
        ("損益", t["profit"]),  # USC（ガチ側の円と混ぜない＝カレンダー集計に入れない）
        ("損益通貨", "USC"),
        ("SL", t["sl"]),
        ("TP", t["tp"]),
        ("評価", ""), ("反省", ""), ("新規理由", ""), ("決済理由", ""), ("考察", ""),
    ])


def merge(trades):
    src = MT5_FILES / ENRICHED_CSV.name
    if src.exists():
        shutil.copy(src, ENRICHED_CSV)
    if not ENRICHED_CSV.exists():
        raise SystemExit(f"[ERR] {ENRICHED_CSV.name} が無い（Builder 未実行？）")
    with open(ENRICHED_CSV, encoding="utf-8-sig", newline="") as f:
        enr = {r["trade_id"].strip(): r for r in csv.DictReader(f)}

    merged, missing = [], []
    for t in trades:
        row = fx_columns(t)
        row["trade_id"] = t["trade_id"]
        e = enr.get(t["trade_id"])
        if e is None:
            missing.append(t["trade_id"])
        else:
            for k, v in e.items():
                if k != "trade_id":
                    row[k] = v
        merged.append(row)

    keys = []
    for r in merged:
        for k in r:
            if k not in keys:
                keys.append(k)
    ENRICHED_FULL.parent.mkdir(parents=True, exist_ok=True)
    with open(ENRICHED_FULL, "w", encoding="utf-8-sig", newline="") as f:
        w = csv.DictWriter(f, fieldnames=keys)
        w.writeheader()
        for r in merged:
            w.writerow({k: r.get(k, "") for k in keys})
    print(f"[OK] {ENRICHED_FULL.relative_to(ROOT)} ({len(merged)} 件 / 未マッチ {len(missing)})")
    if missing:
        print(f"[WARN] enriched 未マッチ: {missing}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--report", help="xlsx パス（省略時 imports/ReportHistory_cent_*.xlsx の最新）")
    ap.add_argument("--merge", action="store_true", help="Builder 出力をマージ")
    a = ap.parse_args()
    report = Path(a.report) if a.report else latest_report()
    print(f"[IN] {report.name}")
    trades = build_trades(report)
    if not trades:
        raise SystemExit("[ERR] XAUUSD 系ポジションが 0 件")
    if a.merge:
        merge(trades)
    else:
        write_input(trades)


if __name__ == "__main__":
    main()
