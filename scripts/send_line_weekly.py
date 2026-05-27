"""
send_line_weekly.py
LINE Messaging API（Flex Message）週次配信
マルチタイムフレーム TIER × ADXスコア

Page 1: PHASE TIER カード（D1×H4×ATR組み合わせ）
Page 2: 週次スコアサマリー（5営業日 v3スコア一覧）
"""

import os
import json
import requests
from datetime import datetime, timezone, timedelta

DATA_PATH    = "data/scores.json"
LINE_TOKEN   = os.environ["LINE_CHANNEL_ACCESS_TOKEN"]
LINE_USER_ID = os.environ["LINE_USER_ID"]
PAGES_URL    = os.environ.get("PAGES_URL", "") or os.environ.get("GITHUB_PAGES_URL", "")

JST = timezone(timedelta(hours=9))


# ── Tier定義 ─────────────────────────────────────────
TIER_DEF = {
    "S":  {"wr": 89.7, "pf": 14.1, "color": "#f59e0b", "bg": "#1a1300",
           "note": "BU×BU×CONTRACT 黄金期"},
    "A":  {"wr": 70.0, "pf":  4.8, "color": "#10b981", "bg": "#001a0e",
           "note": "BU×BU×NEUTRAL  強い"},
    "A*": {"wr": 65.0, "pf":  2.9, "color": "#34d399", "bg": "#001a12",
           "note": "PD×NONE×CONTRACT 逆張り特効"},
    "B":  {"wr": 51.0, "pf":  2.4, "color": "#3b82f6", "bg": "#00091a",
           "note": "BU期 観察 環境待ち"},
    "C":  {"wr": 44.0, "pf":  1.4, "color": "#8b5cf6", "bg": "#080019",
           "note": "PD CONTRACT 慎重"},
    "D":  {"wr": 39.0, "pf":  0.9, "color": "#ef4444", "bg": "#1a0000",
           "note": "PD×非CONTRACT 回避"},
}


# ── ユーティリティ ────────────────────────────────────
def load_scores() -> list[dict]:
    if not os.path.exists(DATA_PATH): return []
    with open(DATA_PATH, encoding="utf-8") as f:
        return json.load(f)


def get_recent5(records: list[dict]) -> list[dict]:
    wd = [r for r in records if datetime.strptime(r["date"], "%Y-%m-%d").weekday() < 5]
    return wd[-5:] if len(wd) >= 5 else wd


def v3_band_color(band: str) -> tuple[str, str]:
    return {
        "OPTIMAL": ("#00c853", "#001a0a"),
        "GOOD":    ("#69f0ae", "#001a0a"),
        "WATCH":   ("#ffd740", "#1a1000"),
        "CAUTION": ("#ff5252", "#1a0000"),
    }.get(band, ("#444444", "#ffffff"))


def v3_phase_label(phase: str) -> str:
    return {
        "BOTTOM_CONT":  "🟢 収束底継続",
        "NORMAL_FLAT":  "🟢 ATR安定",
        "BOTTOM_TURN":  "🟡 底から立上",
        "BOTTOM":       "🟡 底圏待機",
        "PEAK_CONT":    "🟡 高ボラ継続",
        "NORMAL_FALL":  "🟠 収縮中",
        "HIGH_FALL":    "🟠 高ボラ収縮",
        "PEAK_FALL":    "🔴 過熱後急落",
        "HIGH_CONT":    "🔴 危険 過熱",
        "NORMAL_RISE":  "🔴 危険 ATR急拡",
        "N/A":          "⬜ 不明",
    }.get(phase, phase)


def ph_arrow(p: str) -> str:
    return "▲" if p == "BU" else ("▼" if p == "PD" else "→")


def ph_color(p: str) -> str:
    return "#10b981" if p == "BU" else ("#ef4444" if p == "PD" else "#94a3b8")


def build_footer() -> dict:
    base = {
        "type": "box", "layout": "vertical",
        "backgroundColor": "#0d1117", "paddingAll": "10px",
    }
    if PAGES_URL and PAGES_URL.startswith("http"):
        base["contents"] = [
            {"type": "button",
             "action": {"type": "uri", "label": "📊 週次レポートを見る", "uri": PAGES_URL},
             "style": "primary", "color": "#d4af37", "height": "sm"},
        ]
    else:
        base["contents"] = [
            {"type": "text", "text": "ARO-ADX Score System",
             "size": "xs", "color": "#444444", "align": "center"},
        ]
    return base


# ── Page1: TIER カード ────────────────────────────────
def build_bubble_tier(records: list[dict]) -> dict:
    recent = get_recent5(records)
    if not recent:
        return {"type": "bubble", "body": {"type": "box", "layout": "vertical",
                "contents": [{"type": "text", "text": "データなし"}]}}

    today     = recent[-1]
    tier      = today.get("tier",      "D")
    d1_phase  = today.get("d1_phase",  "UNKNOWN")
    h4_wave   = today.get("h4_wave",   "UNKNOWN")
    atr_class = today.get("atr_class", "NEUTRAL")
    score_v3  = today.get("score_v3",  0)
    band      = today.get("band_v3",   "CAUTION")
    phase     = today.get("atr_phase", "N/A")

    today_dt  = datetime.strptime(today["date"], "%Y-%m-%d")
    today_str = today_dt.strftime("%-m/%-d(%a)")
    week_num  = today_dt.isocalendar()[1]

    t  = TIER_DEF.get(tier, TIER_DEF["D"])
    tc = t["color"]
    tb = t["bg"]

    atr_c = {"CONTRACT": "#10b981", "NEUTRAL": "#f59e0b", "EXPAND": "#ef4444"}.get(atr_class, "#94a3b8")
    band_c, _ = v3_band_color(band)

    return {
        "type": "bubble",
        "size": "kilo",
        "header": {
            "type": "box", "layout": "vertical",
            "backgroundColor": "#0d1117", "paddingAll": "14px",
            "contents": [
                {"type": "text", "text": "🔱 WEEKLY PHASE TIER",
                 "size": "sm", "color": "#d4af37", "weight": "bold"},
                {"type": "text", "text": f"{today_str}  W{week_num}  XAUUSD",
                 "size": "xs", "color": "#666666", "margin": "xs"},
            ],
        },
        "hero": {
            "type": "box", "layout": "vertical",
            "backgroundColor": "#0d1117", "paddingAll": "14px",
            "contents": [
                # ── TIER バッジ ──────────────────────────
                {"type": "box", "layout": "vertical",
                 "paddingAll": "14px",
                 "backgroundColor": tb,
                 "cornerRadius": "10px",
                 "borderColor": tc, "borderWidth": "2px",
                 "contents": [
                     {"type": "text",
                      "text": f"TIER  {tier}",
                      "size": "xxl", "weight": "bold",
                      "color": tc, "align": "center"},
                     {"type": "text",
                      "text": f"WR {t['wr']}%  ·  PF {t['pf']}",
                      "size": "sm", "color": tc,
                      "align": "center", "margin": "xs"},
                     {"type": "text",
                      "text": t["note"],
                      "size": "xs", "color": "#64748b",
                      "align": "center", "margin": "xs", "wrap": True},
                 ]},
                # ── 区切り ──────────────────────────────
                {"type": "separator", "margin": "md", "color": "#1e293b"},
                # ── D1 / H4 / ATR ───────────────────────
                {"type": "box", "layout": "vertical",
                 "margin": "md", "spacing": "sm",
                 "contents": [
                     {"type": "box", "layout": "horizontal",
                      "contents": [
                          {"type": "text", "text": "D1  フェーズ",
                           "size": "xs", "color": "#64748b", "flex": 4},
                          {"type": "text",
                           "text": f"{d1_phase}  {ph_arrow(d1_phase)}",
                           "size": "xs", "color": ph_color(d1_phase),
                           "weight": "bold", "flex": 3, "align": "end"},
                      ]},
                     {"type": "box", "layout": "horizontal",
                      "contents": [
                          {"type": "text", "text": "H4  波形",
                           "size": "xs", "color": "#64748b", "flex": 4},
                          {"type": "text",
                           "text": f"{h4_wave}  {ph_arrow(h4_wave)}",
                           "size": "xs", "color": ph_color(h4_wave),
                           "weight": "bold", "flex": 3, "align": "end"},
                      ]},
                     {"type": "box", "layout": "horizontal",
                      "contents": [
                          {"type": "text", "text": "H4  ATR状態",
                           "size": "xs", "color": "#64748b", "flex": 4},
                          {"type": "text", "text": atr_class,
                           "size": "xs", "color": atr_c,
                           "weight": "bold", "flex": 3, "align": "end"},
                      ]},
                 ]},
            ],
        },
        "body": {
            "type": "box", "layout": "vertical",
            "backgroundColor": "#161b22", "paddingAll": "12px",
            "contents": [
                {"type": "box", "layout": "horizontal",
                 "contents": [
                     {"type": "box", "layout": "vertical", "flex": 1,
                      "contents": [
                          {"type": "text", "text": "v3スコア",
                           "size": "xxs", "color": "#666666"},
                          {"type": "text", "text": f"{score_v3}pt",
                           "size": "lg", "weight": "bold", "color": band_c},
                      ]},
                     {"type": "box", "layout": "vertical", "flex": 2,
                      "contents": [
                          {"type": "text", "text": "ATRフェーズ",
                           "size": "xxs", "color": "#666666"},
                          {"type": "text", "text": v3_phase_label(phase),
                           "size": "xs", "weight": "bold",
                           "color": "#e2e8f0", "wrap": True},
                      ]},
                 ]},
            ],
        },
        "footer": build_footer(),
    }


# ── Page2: 週次スコアサマリー ──────────────────────────
def build_bubble_weekly(records: list[dict]) -> dict:
    recent = get_recent5(records)
    if not recent:
        return {"type": "bubble", "body": {"type": "box", "layout": "vertical",
                "contents": [{"type": "text", "text": "データなし"}]}}

    last_dt  = datetime.strptime(recent[-1]["date"], "%Y-%m-%d")
    week_num = last_dt.isocalendar()[1]

    rows = []
    for r in recent:
        s3   = r.get("score_v3", 0)
        bd   = r.get("band_v3",  "CAUTION")
        tier = r.get("tier",     "?")
        b_c, _ = v3_band_color(bd)
        t_c    = TIER_DEF.get(tier, {}).get("color", "#666666")

        dt   = datetime.strptime(r["date"], "%Y-%m-%d")
        is_t = r["date"] == recent[-1]["date"]
        dow  = ["Mon","Tue","Wed","Thu","Fri","Sat","Sun"][dt.weekday()]
        lbl  = dt.strftime(f"%-m/%-d({dow})")

        row = {
            "type": "box", "layout": "horizontal",
            "paddingAll": "4px", "cornerRadius": "4px", "margin": "xs",
            "contents": [
                {"type": "text", "text": lbl, "size": "xs",
                 "color": "#e0e0e0" if is_t else "#888888",
                 "flex": 3, "weight": "bold" if is_t else "regular"},
                {"type": "text", "text": f"{s3}pt", "size": "xs",
                 "color": b_c, "flex": 2, "weight": "bold", "align": "end"},
                {"type": "text", "text": bd[:4],
                 "size": "xs", "color": b_c, "flex": 3, "align": "center"},
                {"type": "text",
                 "text": f"T{tier}" if tier not in ("?", "") else "-",
                 "size": "xs", "color": t_c, "weight": "bold",
                 "flex": 2, "align": "end"},
            ],
        }
        if is_t:
            row["backgroundColor"] = "#1a2a1a"
        rows.append(row)

    # 最新日のフェーズ状態
    today = recent[-1]
    d1    = today.get("d1_phase",  "?")
    h4w   = today.get("h4_wave",   "?")
    atr   = today.get("atr_class", "?")
    atr_c = {"CONTRACT": "#10b981", "NEUTRAL": "#f59e0b", "EXPAND": "#ef4444"}.get(atr, "#94a3b8")

    return {
        "type": "bubble",
        "size": "kilo",
        "header": {
            "type": "box", "layout": "vertical",
            "backgroundColor": "#0d1117", "paddingAll": "14px",
            "contents": [
                {"type": "text", "text": "📅 週次スコアサマリー",
                 "size": "sm", "color": "#d4af37", "weight": "bold"},
                {"type": "text", "text": f"W{week_num}  直近5営業日",
                 "size": "xs", "color": "#666666", "margin": "xs"},
            ],
        },
        "body": {
            "type": "box", "layout": "vertical",
            "backgroundColor": "#161b22", "paddingAll": "12px",
            "contents": [
                # カラムヘッダー
                {"type": "box", "layout": "horizontal", "paddingBottom": "4px",
                 "contents": [
                     {"type": "text", "text": "日付",  "size": "xxs", "color": "#444444", "flex": 3},
                     {"type": "text", "text": "v3",    "size": "xxs", "color": "#444444", "flex": 2, "align": "end"},
                     {"type": "text", "text": "Band",  "size": "xxs", "color": "#444444", "flex": 3, "align": "center"},
                     {"type": "text", "text": "Tier",  "size": "xxs", "color": "#444444", "flex": 2, "align": "end"},
                 ]},
                {"type": "separator", "color": "#1e293b", "margin": "xs"},
                *rows,
                {"type": "separator", "color": "#1e293b", "margin": "sm"},
                # フェーズ状態（最新）
                {"type": "box", "layout": "horizontal", "margin": "sm",
                 "contents": [
                     {"type": "text", "text": "D1",  "size": "xxs", "color": "#64748b", "flex": 1},
                     {"type": "text", "text": d1,    "size": "xxs", "color": ph_color(d1),
                      "weight": "bold", "flex": 2},
                     {"type": "text", "text": "H4",  "size": "xxs", "color": "#64748b", "flex": 1},
                     {"type": "text", "text": h4w,   "size": "xxs", "color": ph_color(h4w),
                      "weight": "bold", "flex": 2},
                     {"type": "text", "text": "ATR", "size": "xxs", "color": "#64748b", "flex": 1},
                     {"type": "text", "text": atr[:4] if len(atr) >= 4 else atr,
                      "size": "xxs", "color": atr_c,
                      "weight": "bold", "flex": 3},
                 ]},
            ],
        },
        "footer": build_footer(),
    }


# ── Carousel + 送信 ───────────────────────────────────
def build_carousel_weekly(records: list[dict]) -> dict:
    recent    = get_recent5(records)
    today     = recent[-1] if recent else {}
    tier      = today.get("tier",     "?")
    score_v3  = today.get("score_v3", 0)
    band      = today.get("band_v3",  "CAUTION")
    d1        = today.get("d1_phase", "?")
    h4w       = today.get("h4_wave",  "?")
    today_str = (datetime.strptime(today["date"], "%Y-%m-%d").strftime("%-m/%-d")
                 if today else "??")

    return {
        "type": "flex",
        "altText": (
            f"[週次TIER] {today_str}  TIER {tier} / {score_v3}pt {band}"
            f"  D1:{d1} H4:{h4w}"
        ),
        "contents": {
            "type": "carousel",
            "contents": [
                build_bubble_tier(records),
                build_bubble_weekly(records),
            ],
        },
    }


def send_line(message: dict):
    url     = "https://api.line.me/v2/bot/message/push"
    headers = {
        "Content-Type":  "application/json",
        "Authorization": f"Bearer {LINE_TOKEN}",
    }
    payload = {"to": LINE_USER_ID, "messages": [message]}
    resp    = requests.post(url, headers=headers, json=payload, timeout=15)
    if resp.status_code == 200:
        print("[OK] LINE送信成功")
    else:
        print(f"[ERROR] LINE送信失敗: {resp.status_code} {resp.text}")
        resp.raise_for_status()


# ── メイン ───────────────────────────────────────────
def main():
    print("=== send_line_weekly.py 開始 ===")
    records = load_scores()
    if not records:
        print("[WARN] データなし → スキップ")
        return

    recent = get_recent5(records)
    today  = recent[-1] if recent else {}
    print(
        f"配信日: {today.get('date','')}  "
        f"TIER={today.get('tier','?')}  "
        f"D1={today.get('d1_phase','?')}  "
        f"H4w={today.get('h4_wave','?')}  "
        f"ATR={today.get('atr_class','?')}  "
        f"v3={today.get('score_v3','?')} [{today.get('band_v3','?')}]"
    )

    msg = build_carousel_weekly(records)
    send_line(msg)
    print("=== 完了 ===")


if __name__ == "__main__":
    main()
