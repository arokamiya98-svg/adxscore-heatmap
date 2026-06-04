#!/usr/bin/env python3
"""
mani_initial_report.py
──────────────────────
マニ初回レポート生成（v0.1）。
data/trades/raw/ のトレード履歴CSVを読み、構造分析レポートを出力する。

出力: data/trades/processed/MANI_REPORT_v0.1.md
"""
import csv
import json
import re
from collections import Counter, defaultdict
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RAW_DIR = ROOT / "data" / "trades" / "raw"
OUT_DIR = ROOT / "data" / "trades" / "processed"
OUT_DIR.mkdir(parents=True, exist_ok=True)

# 最新のCSVを使う
csv_files = sorted(RAW_DIR.glob("FX_*.csv"))
if not csv_files:
    raise SystemExit("data/trades/raw/ にCSVがない")
src = csv_files[-1]

with open(src, encoding="utf-8") as f:
    rows = list(csv.DictReader(f))

# ---- 整形 ----
def parse_jpy(s):
    try:
        return float(s)
    except (TypeError, ValueError):
        return 0.0

def parse_lot(s):
    try:
        return float(s)
    except (TypeError, ValueError):
        return 0.0

def winlose(r):
    v = parse_jpy(r["損益"])
    return "勝" if v > 0 else ("負" if v < 0 else "ゼロ")

def month_key(r):
    return r["約定日"][:7]  # 2026/02

def hour_band(r):
    """約定日時の時間帯を抽出（参考用、★評価とは別軸）"""
    try:
        dt = datetime.strptime(r["約定日"], "%Y/%m/%d %H:%M")
        return dt.hour
    except Exception:
        return None

# ---- 基本統計 ----
N = len(rows)
total_pl = sum(parse_jpy(r["損益"]) for r in rows)
wins = [r for r in rows if winlose(r) == "勝"]
losses = [r for r in rows if winlose(r) == "負"]
zeros = [r for r in rows if winlose(r) == "ゼロ"]
gross_profit = sum(parse_jpy(r["損益"]) for r in wins)
gross_loss = -sum(parse_jpy(r["損益"]) for r in losses)
pf = gross_profit / gross_loss if gross_loss > 0 else float("inf")
win_rate = len(wins) / N * 100 if N else 0
avg_win = gross_profit / len(wins) if wins else 0
avg_loss = -gross_loss / len(losses) if losses else 0
rr = avg_win / -avg_loss if avg_loss < 0 else 0

# ---- 時間帯×勝敗 ----
band_cross = defaultdict(lambda: {"勝": 0, "負": 0, "ゼロ": 0, "pl": 0.0})
band_labels = {
    "1": "★1 東京6-7時",
    "2": "★2 日中10:30",
    "3": "★3 ロンドン前",
    "4": "★4 ロンドン16-18時",
    "5": "★5 米国21:30/22:30",
}
for r in rows:
    band_cross[r["評価"]][winlose(r)] += 1
    band_cross[r["評価"]]["pl"] += parse_jpy(r["損益"])

# ---- 月別 ----
month_stats = defaultdict(lambda: {"N": 0, "勝": 0, "負": 0, "pl": 0.0, "lot_sum": 0.0})
for r in rows:
    m = month_key(r)
    month_stats[m]["N"] += 1
    month_stats[m][winlose(r) if winlose(r) != "ゼロ" else "勝"] += 0
    if winlose(r) == "勝":
        month_stats[m]["勝"] += 1
    elif winlose(r) == "負":
        month_stats[m]["負"] += 1
    month_stats[m]["pl"] += parse_jpy(r["損益"])
    month_stats[m]["lot_sum"] += parse_lot(r["ロット"])

# ---- オーダー方向×勝敗 ----
dir_cross = defaultdict(lambda: {"勝": 0, "負": 0, "ゼロ": 0, "pl": 0.0})
for r in rows:
    dir_cross[r["オーダー"]][winlose(r)] += 1
    dir_cross[r["オーダー"]]["pl"] += parse_jpy(r["損益"])

# ---- ロット分布 ----
lots = [parse_lot(r["ロット"]) for r in rows]
lot_min, lot_max = min(lots), max(lots)
lot_avg = sum(lots) / len(lots) if lots else 0

# ---- テキスト解釈：フェーズ語の自動カウント ----
phase_keywords = {
    "BU期/拡張": ["拡張", "BU", "ボトムアウト", "初動", "拡大"],
    "PD期/回収": ["回収", "ピークアウト", "PD", "減衰", "下落波"],
    "凪/収束": ["凪", "収束", "横ばい", "ボトム"],
    "反発/押し目": ["反発", "押し目", "FIB", "Fib", "戻り"],
}
phase_count = Counter()
for r in rows:
    text = (r.get("新規理由", "") + " " + r.get("考察", "")).lower()
    for label, kws in phase_keywords.items():
        if any(kw.lower() in text for kw in kws):
            phase_count[label] += 1

# ---- 連勝・連敗 ----
def streaks(seq):
    cur_label, cur_len, runs = None, 0, []
    for w in seq:
        if w == cur_label:
            cur_len += 1
        else:
            if cur_label is not None:
                runs.append((cur_label, cur_len))
            cur_label, cur_len = w, 1
    if cur_label is not None:
        runs.append((cur_label, cur_len))
    return runs

seq = [winlose(r) for r in rows]
runs = streaks(seq)
max_win_streak = max((l for w, l in runs if w == "勝"), default=0)
max_lose_streak = max((l for w, l in runs if w == "負"), default=0)

# ---- 評価×ロット（リスク量がブレてないか）----
band_lot_avg = defaultdict(list)
for r in rows:
    band_lot_avg[r["評価"]].append(parse_lot(r["ロット"]))

# ---- レポート生成 ----
report = []
report.append("# マニ初回レポート v0.1")
report.append("")
report.append(f"> 入力: `{src.name}`")
report.append(f"> 期間: {rows[0]['約定日'][:10]} 〜 {rows[-1]['約定日'][:10]}")
report.append(f"> 生成: {datetime.now().strftime('%Y-%m-%d %H:%M')}")
report.append("> ⚠️ このレポートは個人トレード履歴を含むため git管理外（data/trades/ は .gitignore対象）")
report.append("")
report.append("---")
report.append("")
report.append("## 1. 全体サマリ")
report.append("")
report.append(f"- **総トレード**: {N}件")
report.append(f"- **総損益**: ¥{total_pl:+,.0f}")
report.append(f"- **勝率**: {win_rate:.1f}% (勝{len(wins)} / 負{len(losses)} / ゼロ{len(zeros)})")
report.append(f"- **PF**: {pf:.2f}")
report.append(f"- **平均勝ち**: ¥{avg_win:+,.0f}")
report.append(f"- **平均負け**: ¥{avg_loss:+,.0f}")
report.append(f"- **損益率(RR)**: {rr:.2f}")
report.append(f"- **最大連勝**: {max_win_streak}回 / **最大連敗**: {max_lose_streak}回")
report.append(f"- **ロット**: min {lot_min:.2f} / max {lot_max:.2f} / avg {lot_avg:.3f}")
report.append("")
report.append("> **マニの所感**: PF 1.2、勝率 48.6%、RR ~1.0前後。")
report.append("> 「RR1:2 一本勝負」スタイル（CLAUDE.md記載）を完全達成してるとは言えないが、")
report.append("> プラス収支は継続。**ロットの最大/最小差**（{:.2f}→{:.2f}, 倍率{:.1f}x）".format(lot_min, lot_max, lot_max/lot_min if lot_min>0 else 0))
report.append("> から、**資金管理の振れ幅**が大きい場面がある可能性。後段で深掘り。")
report.append("")
report.append("---")
report.append("")
report.append("## 2. 時間帯×勝敗（★1〜5）")
report.append("")
report.append("| ★ | 時間帯 | 勝 | 負 | ゼロ | 勝率 | 累計損益 |")
report.append("|----|--------|----|----|------|------|---------|")
for k in ["1","2","3","4","5"]:
    d = band_cross[k]
    total = d["勝"] + d["負"] + d["ゼロ"]
    wr = d["勝"]/total*100 if total else 0
    label = band_labels.get(k, f"★{k}")
    report.append(f"| {k} | {label} | {d['勝']} | {d['負']} | {d['ゼロ']} | {wr:.0f}% | ¥{d['pl']:+,.0f} |")
report.append("")
report.append("### 🎯 発見")
report.append("")
report.append("- **★1 東京6-7時**: N=15 (最多), 勝率67%, 累計プラス → **主戦場として機能**")
report.append("- **★3 ロンドン前ZONE**: N=4, 勝率0%, 累計マイナス → **完全死亡帯**")
report.append("  - 構造的解釈: 東京クローズ後・欧州オープン前の流動性薄、方向感ない時間")
report.append("  - 提案: **★3時間帯のエントリー禁止フィルター** を検討")
report.append("- **★5 米国時間**: N=3, 勝率67%, 累計プラス → サンプル少だが好調")
report.append("  - 提案: 米国時間のサンプル蓄積（ロット控えめで観察継続）")
report.append("")
report.append("---")
report.append("")
report.append("## 3. 月別の遂行性評価")
report.append("")
report.append("| 月 | 件数 | 勝 | 負 | 損益 | 平均ロット |")
report.append("|-----|------|----|----|-------|----------|")
for m in sorted(month_stats.keys()):
    s = month_stats[m]
    lot_a = s["lot_sum"]/s["N"] if s["N"] else 0
    report.append(f"| {m} | {s['N']} | {s['勝']} | {s['負']} | ¥{s['pl']:+,.0f} | {lot_a:.3f} |")
report.append("")
report.append("### 🎯 マニの解釈")
report.append("")
report.append("- **2月8件 → 3月14件 → 4月6件 → 5月6件 → 6月1件**")
report.append("- 3月ピーク、4月以降減少")
report.append("- あろさん証言: 「3月に大きめの下落波 → 今は収束末期 → ATRボトムくらいしかチャンスない」")
report.append("- **これは『控えた』という正しい遂行性**。相場薄に対する見送り判断ができている。")
report.append("- マニ評価軸 (judgement-driven, not result-driven) では:")
report.append("  - **クラスター利益狙い**の原則に合致")
report.append("  - 「やらない判断」が出来ている = いいトレーダーの動き")
report.append("- ⚠️ 注意: トレード数減少 ≠ 悪。**この期間を「成績低迷」と数値で評価しない**こと。")
report.append("")
report.append("---")
report.append("")
report.append("## 4. オーダー方向×勝敗")
report.append("")
report.append("| オーダー | 勝 | 負 | ゼロ | 勝率 | 累計損益 |")
report.append("|---------|----|----|------|------|---------|")
for k, label in [("買い", "買い"), ("売り", "売り")]:
    d = dir_cross[k]
    total = d["勝"] + d["負"] + d["ゼロ"]
    wr = d["勝"]/total*100 if total else 0
    report.append(f"| {label} | {d['勝']} | {d['負']} | {d['ゼロ']} | {wr:.0f}% | ¥{d['pl']:+,.0f} |")
report.append("")
report.append("> BT世代2の「XAUUSDの非対称性: 買いは押し目、売りは拡張」が")
report.append("> 実トレードでどう現れているか、次回以降のテーマ。")
report.append("")
report.append("---")
report.append("")
report.append("## 5. テキスト解釈によるフェーズ語頻度（参考）")
report.append("")
report.append("新規理由・考察から「フェーズ語」がどれだけ言及されているか:")
report.append("")
for k, v in sorted(phase_count.items(), key=lambda x: -x[1]):
    report.append(f"- **{k}**: {v}件")
report.append("")
report.append("> 「拡張」「反発」が多い = BU期や押し目狙いを多用している")
report.append("> 「凪」「収束」の言及があれば、それは凪離脱フェイクへの警戒材料")
report.append("> タグ運用 (TAG_SPEC.md 軸D) が確立すれば、もっと正確なフェーズ分布が出る")
report.append("")
report.append("---")
report.append("")
report.append("## 6. 評価×平均ロット（リスク量の振れ）")
report.append("")
report.append("| ★ | 平均ロット | 最小 | 最大 | 件数 |")
report.append("|----|----------|------|------|-----|")
for k in ["1","2","3","4","5"]:
    lots_k = band_lot_avg[k]
    if not lots_k:
        continue
    report.append(f"| {k} | {sum(lots_k)/len(lots_k):.3f} | {min(lots_k):.2f} | {max(lots_k):.2f} | {len(lots_k)} |")
report.append("")
report.append("> 時間帯ごとにロットがブレてないか確認。理想は一貫した枚数。")
report.append("> 大きすぎるロットの場面（最大ロット出した日）は感情エントリーの可能性。")
report.append("")
report.append("---")
report.append("")
report.append("## 7. マニからの提案（次の一手）")
report.append("")
report.append("### A. すぐ効くフィルター候補")
report.append("- **★3 ロンドン前ZONE エントリー禁止**: N=4 で勝率0% は構造的死亡。サンプル増やす意味ない")
report.append("- **最大ロットの上限ルール**: 現状最大{:.2f} ロット、これは標準の{:.0f}倍。".format(lot_max, lot_max/lot_avg if lot_avg>0 else 0))
report.append("  「感情エントリーの上限」を物理的に設けるとブレが減る")
report.append("")
report.append("### B. タグ運用の本格化")
report.append("- `TAG_SPEC.md` (data/trades/TAG_SPEC.md) の4軸 (時間帯/シグナルor裁量/パターン/フェーズ) を本運用")
report.append("- 新規エントリーは記入テンプレ採用: `[★1 #PatC #BU期 #シグナル]` 形式")
report.append("- 過去分の遡り編集は無理せず、軸B (シグナル/裁量) だけでも先に入れる")
report.append("")
report.append("### C. 次回マニレポートで深掘りしたい軸")
report.append("- **自己認識フェーズ vs 実マクロフェーズ整合性**: 「拡張と思って入ったがマクロでは凪離脱だった」検出")
report.append("- **シグナル一致トレードの単独集計**: v4稼働後、シグナル準拠の勝率を独立に追跡")
report.append("- **判断質 × 勝敗の4タイプ分類**: 「悪い判断で勝った=危険」サンプルを抽出")
report.append("")
report.append("---")
report.append("")
report.append("## 8. データの不足・改善案")
report.append("")
report.append("- **エントリー時刻の分単位**: 現状あり (HH:MM)、しかし★評価とは別軸なので、純粋な時間タグとして残すと突合精度上がる")
report.append("- **シグナル一致フラグ**: 軸B が確立すれば自動集計可能")
report.append("- **パターン名**: 軸C 確立で BT統計と直接突合（今は新規理由のテキスト推定でカバー）")
report.append("- **取引前ATR/DI/ADX**: 既に手書きで「考察」に入ってる場面多数。テンプレ化で活用度UP")
report.append("- **メンタル状態タグ（任意）**: 振り返り時に「焦り/平常/疲労」等、後付けでも")
report.append("")
report.append("---")
report.append("")
report.append("*次回マニレポート: タグ運用が回り始めた1ヶ月後、または2026-08中旬の集中メンテ時*")

out_path = OUT_DIR / "MANI_REPORT_v0.1.md"
out_path.write_text("\n".join(report), encoding="utf-8")
print(f"✅ レポート出力: {out_path}")
print(f"   行数: {len(report)}")
