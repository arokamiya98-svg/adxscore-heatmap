#!/usr/bin/env python3
"""
prepare_trade_input.py — マニの部屋 Phase C 前処理（標準ライブラリのみ）

元 CSV (FX_*.csv from FXトレード記録アプリ) → 中間 CSV (trade_input.csv for MT5 Trade_Snapshot_Builder)

研究目的（固定）:
  日時+価格をキーとして、エントリー時点の市場環境を後付け取得し、
  どの市場環境で期待値が発生しているかを研究する。

このスクリプトの責務:
  1. 元 CSV の multi-line quote をパース (csv.DictReader が対応)
  2. XAUUSD 行のみ抽出
  3. trade_id 連番付与 (T001〜)
  4. JST 時刻を yyyy-mm-dd HH:MM 形式に正規化
  5. 方向を BUY/SELL に正規化
  6. DST 判定 → server_offset_hours 付与 (HFM EET 想定)
  7. 中間 CSV を MT5 が読みやすい形で出力

DST 判定 (HFMarkets サーバー EET/EEST 前提):
  冬時間 GMT+2: 10月最終日曜 01:00 UTC 以降〜3月最終日曜 01:00 UTC まで
  夏時間 GMT+3: 3月最終日曜 01:00 UTC 〜10月最終日曜 01:00 UTC まで

使い方:
  # 中間 CSV 生成
  python3 scripts/prepare_trade_input.py \\
      --input data/mani_room/raw/imports/FX_20260608_144251.csv \\
      --output mt5_data/trade_input.csv

  # MT5 出力後のマージ
  python3 scripts/prepare_trade_input.py \\
      --input data/mani_room/raw/imports/FX_20260608_144251.csv \\
      --output mt5_data/trade_input.csv \\
      --enriched mt5_data/trades_enriched.csv \\
      --enriched-full data/mani_room/enriched/trades_enriched_full.csv

関連:
  data/mani_room/コー_指示書_Trade_Snapshot_Builder.md (中間CSV仕様 §4.3 / DST §5)
  signals/Trade_Snapshot_Builder.mq5 (中間CSVを読む側)
"""

import argparse
import csv
from collections import OrderedDict
from datetime import datetime, timedelta
from pathlib import Path


# ---------------- DST ----------------
def get_last_sunday(year: int, month: int) -> datetime:
    """指定された年月の最終日曜日 00:00 を返す"""
    if month == 12:
        next_month = datetime(year + 1, 1, 1)
    else:
        next_month = datetime(year, month + 1, 1)
    last_day = next_month - timedelta(days=1)
    days_back = (last_day.weekday() - 6) % 7  # weekday: 月=0, 日=6
    return last_day - timedelta(days=days_back)


def is_european_dst(utc_dt: datetime) -> bool:
    """欧州 DST (EET/EEST) 期間か判定

    DST 開始: 3月最終日曜 01:00 UTC
    DST 終了: 10月最終日曜 01:00 UTC
    """
    year = utc_dt.year
    dst_start = get_last_sunday(year, 3).replace(hour=1)
    dst_end = get_last_sunday(year, 10).replace(hour=1)
    return dst_start <= utc_dt < dst_end


def get_server_offset_hours(jst_dt: datetime) -> int:
    """JST → HFM サーバーオフセット時間 (冬2 / 夏3)"""
    utc_dt = jst_dt - timedelta(hours=9)
    return 3 if is_european_dst(utc_dt) else 2


# ---------------- 正規化 ----------------
def normalize_direction(jp) -> str:
    """日本語方向 → BUY/SELL"""
    if jp is None:
        return ""
    s = str(jp).strip()
    if s == "買い":
        return "BUY"
    if s == "売り":
        return "SELL"
    return s  # 既に英語なら通す


def normalize_datetime(s) -> str:
    """日時文字列を yyyy-mm-dd HH:MM に正規化"""
    if s is None or str(s).strip() == "":
        return ""
    s = str(s).strip()
    for fmt in ("%Y/%m/%d %H:%M", "%Y-%m-%d %H:%M", "%Y/%m/%d %H:%M:%S"):
        try:
            dt = datetime.strptime(s, fmt)
            return dt.strftime("%Y-%m-%d %H:%M")
        except ValueError:
            continue
    print(f"[WARN] 未対応の日時形式: {s!r}")
    return s


# ---------------- メイン処理 ----------------
def prepare_trade_input(input_path: str, output_path: str, symbol_filter: str = "XAUUSD"):
    """元 CSV → 中間 CSV 変換

    Returns: 元 CSV 全カラム + trade_id を持つ List[dict]（後処理マージ用）
    """
    with open(input_path, "r", encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f)
        rows = list(reader)

    # XAUUSD のみ抽出
    rows = [r for r in rows if r.get("通貨ペア") == symbol_filter]

    # trade_id 付与 + 正規化
    output_rows = []
    offset_counts = {}
    for i, r in enumerate(rows, start=1):
        trade_id = f"T{i:03d}"
        r["trade_id"] = trade_id

        entry_jst = normalize_datetime(r.get("約定日"))
        exit_jst = normalize_datetime(r.get("決済日"))
        direction = normalize_direction(r.get("オーダー"))
        entry_price = r.get("新規レート", "")

        # DST 判定
        offset = ""
        if entry_jst:
            try:
                jst_dt = datetime.strptime(entry_jst, "%Y-%m-%d %H:%M")
                offset = get_server_offset_hours(jst_dt)
                offset_counts[offset] = offset_counts.get(offset, 0) + 1
            except Exception:
                pass

        output_rows.append(OrderedDict([
            ("trade_id", trade_id),
            ("entry_jst", entry_jst),
            ("exit_jst", exit_jst),
            ("direction", direction),
            ("entry_price", entry_price),
            ("server_offset_hours", offset),
        ]))

    # 中間 CSV 出力
    Path(output_path).parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, "w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=list(output_rows[0].keys()))
        writer.writeheader()
        writer.writerows(output_rows)
    print(f"[OK] 中間 CSV 出力: {output_path} ({len(output_rows)} 件)")

    # プレビュー
    print(f"\n[Preview] 先頭5件:")
    print(",".join(output_rows[0].keys()))
    for r in output_rows[:5]:
        print(",".join(str(v) for v in r.values()))

    # DST 統計
    print(f"\n[DST] server_offset_hours 分布: {offset_counts}")

    return rows  # 元データ（マージ用）


def merge_enriched(original_rows, enriched_path: str, output_path: str):
    """MT5 出力を元 CSV とマージして最終 enriched CSV を出力"""
    with open(enriched_path, "r", encoding="utf-8-sig", newline="") as f:
        reader = csv.DictReader(f)
        enriched_rows = list(reader)

    # trade_id でインデックス化
    enriched_by_id = {r["trade_id"]: r for r in enriched_rows}

    # マージ
    merged_rows = []
    all_keys = list(original_rows[0].keys())  # trade_id 含む
    if enriched_rows:
        for k in enriched_rows[0].keys():
            if k not in all_keys:
                all_keys.append(k)

    missing = 0
    for orig in original_rows:
        merged = OrderedDict()
        for k in all_keys:
            merged[k] = orig.get(k, "")
        enr = enriched_by_id.get(orig["trade_id"])
        if enr:
            for k, v in enr.items():
                if k != "trade_id":
                    merged[k] = v
        else:
            missing += 1
        merged_rows.append(merged)

    Path(output_path).parent.mkdir(parents=True, exist_ok=True)
    # utf-8-sig (BOM付き) で出力 = Mac の Excel で直接開ける
    with open(output_path, "w", encoding="utf-8-sig", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=all_keys)
        writer.writeheader()
        writer.writerows(merged_rows)

    print(f"[OK] マージ済 CSV 出力: {output_path} ({len(merged_rows)} 件)")
    if missing > 0:
        print(f"[WARN] MT5 取得なしレコード: {missing} 件（オープン中 or ヒストリカル不足）")

    return merged_rows


# ---------------- CLI ----------------
def main():
    parser = argparse.ArgumentParser(description="マニの部屋 Phase C 前処理")
    parser.add_argument("--input", required=True, help="元 CSV パス (FX_*.csv)")
    parser.add_argument("--output", required=True, help="中間 CSV 出力パス (MT5 Files用)")
    parser.add_argument("--symbol", default="XAUUSD", help="銘柄フィルタ")
    parser.add_argument("--enriched", help="(後処理) MT5 出力 trades_enriched.csv のパス")
    parser.add_argument("--enriched-full", help="(後処理) マージ後の最終出力先")
    args = parser.parse_args()

    original = prepare_trade_input(args.input, args.output, args.symbol)

    if args.enriched and args.enriched_full:
        merge_enriched(original, args.enriched, args.enriched_full)
    elif args.enriched or args.enriched_full:
        print("[WARN] --enriched と --enriched-full は両方指定する必要がある")


if __name__ == "__main__":
    main()
