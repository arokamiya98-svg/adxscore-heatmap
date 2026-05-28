#!/usr/bin/env python3
"""
generate_heatmap_v12.py  ─ Multi-Layer State Transition Heatmap
DI方向（青=BU/赤=PD）でフェーズ表示、Fibo/ラベル列スクロール固定、
上段に年区切り・下段に週開始日付のヘッダー2段構成。
"""

import json, os
from datetime import datetime
from collections import defaultdict, Counter

BASE_DIR    = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WAVES_JSON  = os.path.join(BASE_DIR, "data", "weekly_waves.json")
SCORES_JSON = os.path.join(BASE_DIR, "data", "scores.json")
OUT_HTML    = os.path.join(BASE_DIR, "docs", "heatmap_v12.html")

def load_json(path):
    if not os.path.exists(path): return []
    with open(path, encoding="utf-8") as f: return json.load(f)

def aggregate_scores(records):
    weeks = defaultdict(list)
    for r in records:
        dt  = datetime.strptime(r["date"], "%Y-%m-%d")
        iso = dt.isocalendar()
        wk  = f"{iso.year}-W{iso.week:02d}"
        weeks[wk].append(r)
    result = {}
    for wk, recs in weeks.items():
        scores = [r.get("score_v3", r.get("score", 0)) for r in recs]
        h1adxs = [r.get("h1_avg_adx", 0) for r in recs]
        def mc(lst):
            lst = [x for x in lst if x]
            return Counter(lst).most_common(1)[0][0] if lst else "—"
        result[wk] = {
            "score_v3":  round(sum(scores)/len(scores), 1),
            "h1_adx":    round(sum(h1adxs)/len(h1adxs), 1),
            "band_v3":   mc([r.get("band_v3") for r in recs]),
            "atr_phase": mc([r.get("atr_phase") for r in recs]),
        }
    return result

def merge_weekly(wave_data, score_data):
    result = {}
    all_weeks = set(w["week"] for w in wave_data) | set(score_data.keys())
    wave_by_wk = {w["week"]: w for w in wave_data}
    for wk in sorted(all_weeks):
        w = wave_by_wk.get(wk, {})
        s = score_data.get(wk, {})
        result[wk] = {
            "week":         wk,
            "fib_zone":     w.get("fib_zone", "—"),
            "fib_pos":      w.get("fib_pos"),
            "fib_days_to_end": w.get("fib_days_to_end"),
            "fib_level":    w.get("fib_level"),
            "fib_anchor":   w.get("fib_anchor", "—"),
            "d1_pattern":   w.get("d1_pattern", "—"),
            "d1_adx22":     w.get("d1_adx22"),
            "d1_di_dir":    w.get("d1_di_dir", "—"),
            "d1_di_plus":   w.get("d1_di_plus"),
            "d1_di_minus":  w.get("d1_di_minus"),
            "d1_di_spread": w.get("d1_di_spread"),
            "d1_atr_trend": w.get("d1_atr_trend", "—"),
            "h4_pattern":   w.get("h4_pattern", "—"),
            "h4_adx46":     w.get("h4_adx46"),
            "h4_di_dir":    w.get("h4_di_dir", "—"),
            "h4_di_plus":   w.get("h4_di_plus"),
            "h4_di_minus":  w.get("h4_di_minus"),
            "h4_di_spread": w.get("h4_di_spread"),
            "h4_atr_cross": w.get("h4_atr_cross", "—"),
            "atr_class":    w.get("atr_class", "—"),
            "atr_phase":    s.get("atr_phase") or w.get("d1_atr_zone", "—"),
            "tier":         w.get("tier", "—"),
            "score_v3":     s.get("score_v3"),
            "h1_adx":       s.get("h1_adx"),
            "band_v3":      s.get("band_v3", "—"),
            "phase_align":  w.get("phase_align", "—"),
        }
    return result

def generate_html(merged: dict, current_week: str) -> str:
    all_weeks = sorted(merged.keys())
    weeks_with_d1 = [wk for wk in all_weeks if merged[wk]["d1_pattern"] != "—"]
    start_wk = max(weeks_with_d1[0] if weeks_with_d1 else all_weeks[-60], "2024-W01")
    weeks = [wk for wk in all_weeks if wk >= start_wk]
    data_js = json.dumps([merged[w] for w in weeks], ensure_ascii=False)

    html = f"""<!DOCTYPE html>
<html lang="ja">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1.0">
<title>XAUUSD マルチレイヤー 状態遷移マップ v12</title>
<style>
*{{box-sizing:border-box;margin:0;padding:0;}}
body{{font-family:'Helvetica Neue',Arial,sans-serif;background:#060d1a;color:#c8d8f0;min-height:100vh;padding:12px;}}
h1{{font-size:1.15rem;color:#7ab8ff;letter-spacing:.04em;}}
.sub{{font-size:.68rem;color:#3a6aaa;margin-top:2px;margin-bottom:10px;}}

/* ─── ステータスカード ─── */
.cards{{display:flex;gap:8px;flex-wrap:wrap;margin:8px 0 14px;}}
.card{{background:#0d1d35;border:1px solid #1e3d70;border-radius:9px;padding:8px 12px;min-width:88px;text-align:center;}}
.card .lbl{{font-size:.58rem;color:#3a6aaa;text-transform:uppercase;letter-spacing:.08em;}}
.card .val{{font-size:1.25rem;font-weight:900;margin-top:1px;}}
.card .sub{{font-size:.6rem;color:#5a7aaa;margin-top:1px;}}

/* ─── スクロール + グリッド ─── */
.scroll{{overflow-x:auto;-webkit-overflow-scrolling:touch;padding-bottom:6px;}}
.grid{{
  display:grid;
  min-width:max-content;
  border-radius:8px;
  overflow:hidden;
}}

/* ─── ラベル列 (スクロール固定) ─── */
.lbl{{
  background:#07101e;
  color:#4a7aaa;
  font-size:.62rem;
  font-weight:700;
  text-align:left;
  padding:4px 8px;
  border-right:2px solid #1a3558;
  white-space:nowrap;
  min-width:108px;
  /* sticky */
  position:sticky;
  left:0;
  z-index:10;
}}
.lbl-top{{
  position:sticky;
  left:0;
  z-index:11;
  background:#050c18;
}}

/* ─── 年行 ─── */
.yr-lbl{{background:#050c18;border-bottom:1px solid #0a1830;}}
.yr-cell{{
  background:#050c18;
  color:#2a5a9a;
  font-size:.6rem;
  font-weight:700;
  padding:3px 2px;
  text-align:center;
  border:1px solid #0a1525;
  letter-spacing:.05em;
}}
.yr-cell.has-year{{color:#5a9adf;border-left:1px solid #1a3a6a;}}
.yr-cell.is-cur{{color:#FFD700;border-left:1px solid #FFD70044;border-right:1px solid #FFD70044;}}

/* ─── 日付ヘッダー行 ─── */
.dt-lbl{{background:#0a1830;border-bottom:2px solid #1a3558;color:#3a6aaa;font-size:.6rem;font-weight:700;padding:5px 6px;}}
.dt-cell{{
  background:#0a1830;
  color:#4a8acc;
  font-size:.62rem;
  font-weight:600;
  padding:4px 2px;
  text-align:center;
  border:1px solid #0a1525;
  white-space:pre-line;
  line-height:1.4;
  min-width:50px;
}}
.dt-cell.is-cur{{background:#2a1f00;color:#FFD700;border-left:2px solid #FFD70066;border-right:2px solid #FFD70066;}}
.dt-cell.is-cur::after{{content:"NOW";display:block;font-size:.48rem;color:#FFD70099;}}

/* ─── データセル ─── */
.c{{
  padding:4px 2px;
  text-align:center;
  font-size:.68rem;
  font-weight:600;
  border:1px solid #0a1525;
  min-width:50px;
  cursor:default;
  transition:filter .12s;
}}
.c:hover{{filter:brightness(1.4);}}
.c.is-cur{{border-left:2px solid #FFD70033!important;border-right:2px solid #FFD70033!important;}}

/* ── TIER ── */
.tS{{background:#2a1f00;color:#FFD700;font-size:.95rem;text-shadow:0 0 8px #FFD70044;}}
.tA{{background:#003320;color:#00E676;font-size:.95rem;}}
.tAx{{background:#002b33;color:#00BCD4;font-size:.95rem;}}
.tB{{background:#001533;color:#42A5F5;font-size:.95rem;}}
.tC{{background:#2d1700;color:#FFA726;font-size:.95rem;}}
.tD{{background:#2a0a0a;color:#EF5350;font-size:.95rem;}}
.t0{{background:#080f1e;color:#1e3a5f;}}

/* ── DI方向: 青=BU(DI+優勢), 赤=PD(DI-優勢) ── */
/* 強さは|spread|で3段階 */
.di-bu-s{{background:#0d2040;color:#90CAF9;border:1px solid #1a3a6a;}}   /* strong BU |sp|>15 */
.di-bu-m{{background:#091830;color:#64B5F6;border:1px solid #153060;}}   /* mid   BU  >7     */
.di-bu-w{{background:#060e20;color:#42A5F5;border:1px solid #0d2040;}}   /* weak  BU  <=7    */
.di-pd-s{{background:#400d0d;color:#EF9A9A;border:1px solid #6a1a1a;}}   /* strong PD |sp|>15 */
.di-pd-m{{background:#300808;color:#EF5350;border:1px solid #601818;}}   /* mid   PD  >7     */
.di-pd-w{{background:#200606;color:#E57373;border:1px solid #400d0d;}}   /* weak  PD  <=7    */
.di-none{{background:#0f1e2a;color:#78909C;border:1px solid #1e3040;}}
.di-0{{background:#080f1e;color:#1e3a5f;}}

/* ── ATR (green=CONTRACT, amber=NEUTRAL, purple=EXPAND) ── */
.aC{{background:#0a2010;color:#69F0AE;border:1px solid #1a4025;}}   /* CONTRACT */
.aN{{background:#2a1f00;color:#FFD180;border:1px solid #4a3800;}}   /* NEUTRAL  */
.aE{{background:#200828;color:#CE93D8;border:1px solid #401860;}}   /* EXPAND   */
.a0{{background:#080f1e;color:#1e3a5f;}}

/* ── Fibo ── */
.fBU_EARLY{{background:#001a0a;color:#69F0AE;border:1px solid #00401a;}}
.fBU_LATE{{background:#0a1a00;color:#B9F6CA;border:1px solid #204a10;}}
.fPD_ZONE{{background:#1a0a2a;color:#CE93D8;border:1px solid #3a1a55;}}
.fBEYOND{{background:#200a00;color:#FFAB91;border:1px solid #500a0a;}}
.fPD_EXT{{background:#300808;color:#EF9A9A;border:1px solid #600808;}}
.fPRE_BU{{background:#0a1030;color:#80DEEA;border:1px solid #1a3060;}}
.f0{{background:#080f1e;color:#1e3a5f;}}

/* ── 凡例 ── */
.leg{{display:flex;flex-wrap:wrap;gap:14px;margin-top:18px;padding:12px;background:#0d1627;border-radius:8px;border:1px solid #1e3a5f;}}
.leg-s h3{{font-size:.6rem;color:#3a6aaa;text-transform:uppercase;letter-spacing:.1em;margin-bottom:5px;}}
.leg-r{{display:flex;gap:5px;flex-wrap:wrap;align-items:center;}}
.lc{{padding:2px 8px;border-radius:3px;font-size:.65rem;font-weight:700;}}
.ld{{font-size:.6rem;color:#3a6aaa;margin-top:3px;line-height:1.5;}}

.upd{{font-size:.58rem;color:#1a4a7a;margin-top:6px;text-align:right;}}
::-webkit-scrollbar{{height:5px;}}
::-webkit-scrollbar-track{{background:#060d1a;}}
::-webkit-scrollbar-thumb{{background:#1a3a6a;border-radius:3px;}}
</style>
</head>
<body>

<h1>XAUUSD マルチレイヤー 状態遷移マップ <span style="color:#2a5a9a">v12</span></h1>
<div class="sub">FractalWaveLog D1/H4 × H1 ADX Score ／ DI方向（青=BU/赤=PD）+ Fibo Time Zone + ATR + TIER</div>

<div class="cards" id="cards"></div>

<div class="scroll">
  <div class="grid" id="grid"></div>
</div>

<div class="leg">
  <div class="leg-s">
    <h3>🏆 TIER</h3>
    <div class="leg-r">
      <span class="lc tS">S</span><span class="lc tA">A</span>
      <span class="lc tAx">A*</span><span class="lc tB">B</span>
      <span class="lc tC">C</span><span class="lc tD">D</span>
    </div>
    <div class="ld">S:BU×BU×CONT WR89.7% ｜ A:BU×BU×NTRL WR70%<br>A*:PD×NONE×CONT WR65% ｜ B:BU期 WR51%<br>C:PD+CONT WR44% ｜ D:PD+非CONT WR39%</div>
  </div>
  <div class="leg-s">
    <h3>🔵🔴 DI方向 (D1/H4)</h3>
    <div class="leg-r">
      <span class="lc di-bu-s">BU強</span>
      <span class="lc di-bu-m">BU中</span>
      <span class="lc di-bu-w">BU弱</span>
      <span class="lc di-none">NONE</span>
      <span class="lc di-pd-w">PD弱</span>
      <span class="lc di-pd-m">PD中</span>
      <span class="lc di-pd-s">PD強</span>
    </div>
    <div class="ld">DI+>DI−: 青=BU ｜ DI−>DI+: 赤=PD ｜ |spread|: 強&gt;15 中&gt;7 弱≤7</div>
  </div>
  <div class="leg-s">
    <h3>💚🟡🟣 ATR Class</h3>
    <div class="leg-r">
      <span class="lc aC">CONTRACT</span>
      <span class="lc aN">NEUTRAL</span>
      <span class="lc aE">EXPAND</span>
    </div>
    <div class="ld">ATR22/ATR42比 &lt;0.90 ｜ 0.90–1.10 ｜ &gt;1.10</div>
  </div>
  <div class="leg-s">
    <h3>🌀 Fibo Zone</h3>
    <div class="leg-r">
      <span class="lc fBU_EARLY">BU早期</span>
      <span class="lc fBU_LATE">BU後期</span>
      <span class="lc fPD_ZONE">PD圏内</span>
      <span class="lc fBEYOND">超過</span>
      <span class="lc fPD_EXT">PD延長</span>
    </div>
    <div class="ld">D1 FractalWaveLog Fiboブロック位置</div>
  </div>
</div>
<div class="upd" id="upd"></div>

<script>
const WEEKLY = {data_js};
const CUR_WK = "{current_week}";

// ── ISO週→月曜日 ──────────────────────────────────────────────────
function wkToMonday(wk) {{
  const [y, w] = wk.split('-W').map(Number);
  // Jan 4 is always in week 1 of its ISO year
  const jan4 = new Date(y, 0, 4);
  const jan4Dow = jan4.getDay() || 7;          // Mon=1 … Sun=7
  const wk1Mon = new Date(jan4.getTime() - (jan4Dow - 1) * 86400000);
  return new Date(wk1Mon.getTime() + (w - 1) * 7 * 86400000);
}}
function fmtDate(d) {{ return `${{d.getMonth()+1}}/${{d.getDate()}}`; }}

// ── DI方向クラス ─────────────────────────────────────────────────
function diClass(pattern, spread) {{
  if (!pattern || pattern === '—' || pattern === 'NONE') return 'di-none';
  if (spread == null) {{
    return pattern === 'BU' ? 'di-bu-m' : pattern === 'PD' ? 'di-pd-m' : 'di-none';
  }}
  const abs = Math.abs(spread);
  if (pattern === 'BU') {{
    return abs > 15 ? 'di-bu-s' : abs > 7 ? 'di-bu-m' : 'di-bu-w';
  }} else if (pattern === 'PD') {{
    return abs > 15 ? 'di-pd-s' : abs > 7 ? 'di-pd-m' : 'di-pd-w';
  }}
  return 'di-none';
}}

// ── スコア / ADX スタイル ─────────────────────────────────────────
function scoreBg(v) {{
  if (v == null) return 'background:#080f1e;color:#1e3a5f';
  if (v >= 75)  return 'background:#2a1e00;color:#FFD700';
  if (v >= 60)  return 'background:#0a2510;color:#69F0AE';
  if (v >= 45)  return 'background:#001535;color:#82AAFF';
  if (v >= 30)  return 'background:#2a1800;color:#FFA726';
  return              'background:#280808;color:#EF5350';
}}
function adxBg(v) {{
  if (v == null) return 'background:#080f1e;color:#1e3a5f';
  if (v >= 30) return 'background:#0a2510;color:#69F0AE';
  if (v >= 20) return 'background:#001535;color:#82AAFF';
  return             'background:#0f1420;color:#4a6a8a';
}}
const TIER_CLS = {{S:'tS',A:'tA','A*':'tAx',B:'tB',C:'tC',D:'tD'}};
const ATR_CLS  = {{CONTRACT:'aC',NEUTRAL:'aN',EXPAND:'aE'}};
const FIB_CLS  = {{
  BU_EARLY:'fBU_EARLY', BU_LATE:'fBU_LATE', BU_CONT:'fBU_EARLY',
  PD_ZONE:'fPD_ZONE', PD_EXT:'fPD_EXT', BEYOND:'fBEYOND', PRE_BU:'fPRE_BU',
}};
const ATR_PH_COLOR = {{
  BOTTOM:'#5a7aaa', BOTTOM_TURN:'#82AAFF', BOTTOM_CONT:'#6a8aaa',
  NORMAL_FLAT:'#FFD180', NORMAL_RISE:'#69F0AE', NORMAL_HIGH:'#FFD700',
  PEAK:'#FF6E40', DECAY:'#FF8A80', NORMAL:'#FFD180',
}};
function fibShort(z) {{
  return {{BU_EARLY:'BU早',BU_LATE:'BU後',BU_CONT:'BU継',
           PD_ZONE:'PD圏',PD_EXT:'PD延',BEYOND:'超過',PRE_BU:'BU前'}}[z]
    || (z && z!=='—' ? z.slice(0,4) : '—');
}}
function atrPhShort(s) {{
  return {{BOTTOM:'BOT',BOTTOM_TURN:'↑BOT',BOTTOM_CONT:'BOT+',
           NORMAL_FLAT:'NRM',NORMAL_RISE:'NRM↑',NORMAL_HIGH:'NRM!',
           PEAK:'PEAK',DECAY:'↓DK',NORMAL:'NRM'}}[s] || (s||'—').slice(0,4);
}}

// ── 現在ステータスカード ──────────────────────────────────────────
function buildCards() {{
  const cur = WEEKLY.find(w=>w.week===CUR_WK)
           || WEEKLY.filter(w=>w.d1_pattern!=='—').slice(-1)[0]
           || WEEKLY[WEEKLY.length-1];
  const el = document.getElementById('cards');
  const tm = {{
    S:{{fg:'#FFD700',bg:'#2a1f00',note:'黄金 WR89.7%'}},
    A:{{fg:'#00E676',bg:'#003320',note:'強い WR70%'}},
    'A*':{{fg:'#00BCD4',bg:'#002b33',note:'逆張特効 WR65%'}},
    B:{{fg:'#42A5F5',bg:'#001533',note:'環境待 WR51%'}},
    C:{{fg:'#FFA726',bg:'#2d1700',note:'慎重 WR44%'}},
    D:{{fg:'#EF5350',bg:'#2a0a0a',note:'回避 WR39%'}},
  }}[cur.tier] || {{fg:'#4a7aaa',bg:'#0d1d35',note:'データ待ち'}};

  const d1sp = cur.d1_di_spread;
  const h4sp = cur.h4_di_spread;
  const d1cls = diClass(cur.d1_pattern, d1sp);
  const h4cls = diClass(cur.h4_pattern, h4sp);
  // extract colors from class
  const diStyle = cls => {{
    const m = {{
      'di-bu-s':'#0d2040,#90CAF9','di-bu-m':'#091830,#64B5F6','di-bu-w':'#060e20,#42A5F5',
      'di-pd-s':'#400d0d,#EF9A9A','di-pd-m':'#300808,#EF5350','di-pd-w':'#200606,#E57373',
      'di-none':'#0f1e2a,#78909C','di-0':'#080f1e,#1e3a5f',
    }};
    const p = (m[cls]||m['di-0']).split(',');
    return {{bg:p[0],fg:p[1]}};
  }};

  const d1s = diStyle(d1cls), h4s = diStyle(h4cls);
  const cards = [
    {{lbl:'現在週',val:CUR_WK.replace('-W',' W'),sub:'',fg:'#7ab8ff',bg:'#0d1d35'}},
    {{lbl:'🏆 TIER',val:cur.tier||'—',sub:tm.note,fg:tm.fg,bg:tm.bg}},
    {{lbl:'📊 v3スコア',val:cur.score_v3??'—',sub:cur.band_v3||'',
      fg:scoreBg(cur.score_v3).match(/color:([^;]+)/)?.[1]||'#7ab8ff',
      bg:scoreBg(cur.score_v3).match(/background:([^;]+)/)?.[1]||'#0d1d35'}},
    {{lbl:'🌍 D1 Phase',val:cur.d1_pattern||'—',
      sub:`DI+${{cur.d1_di_plus?.toFixed(1)||'?'}} DI−${{cur.d1_di_minus?.toFixed(1)||'?'}}`,
      fg:d1s.fg,bg:d1s.bg}},
    {{lbl:'📈 H4 Wave',val:cur.h4_pattern||'—',
      sub:`DI+${{cur.h4_di_plus?.toFixed(1)||'?'}} DI−${{cur.h4_di_minus?.toFixed(1)||'?'}}`,
      fg:h4s.fg,bg:h4s.bg}},
    {{lbl:'💨 ATR',val:cur.atr_class==='CONTRACT'?'CONT':(cur.atr_class||'—'),
      sub:cur.d1_atr_trend||'',
      fg:cur.atr_class==='CONTRACT'?'#69F0AE':cur.atr_class==='NEUTRAL'?'#FFD180':'#CE93D8',
      bg:cur.atr_class==='CONTRACT'?'#0a2010':cur.atr_class==='NEUTRAL'?'#2a1f00':'#200828'}},
    {{lbl:'🌀 Fibo Zone',val:fibShort(cur.fib_zone),
      sub:cur.fib_zone!=='—'?`pos ${{(cur.fib_pos||0).toFixed(2)}}`:'',
      fg:'#CE93D8',bg:'#1a0a2a'}},
  ];
  cards.forEach(c=>{{
    const d=document.createElement('div');
    d.className='card';
    d.style.background=c.bg||'#0d1d35';
    d.style.borderColor=(c.fg||'#1e3d70')+'44';
    d.innerHTML=`<div class="lbl">${{c.lbl}}</div><div class="val" style="color:${{c.fg}}">${{c.val}}</div><div class="sub">${{c.sub}}</div>`;
    el.appendChild(d);
  }});
}}

// ── ヒートマップ ─────────────────────────────────────────────────
function buildGrid() {{
  const g = document.getElementById('grid');
  const N = WEEKLY.length;
  // 1 label col + N data cols
  g.style.gridTemplateColumns = `108px repeat(${{N}}, minmax(48px,56px))`;

  function ce(cls,txt='') {{
    const d=document.createElement('div');
    d.className=cls;
    if(txt) d.textContent=txt;
    return d;
  }}

  // ── 年行 ──
  g.appendChild(ce('lbl lbl-top yr-lbl','')).textContent='';
  WEEKLY.forEach((w,i)=>{{
    const isCur = w.week === CUR_WK;
    const yr = w.week.split('-W')[0];
    const prevYr = i>0 ? WEEKLY[i-1].week.split('-W')[0] : null;
    const hasYr = yr !== prevYr;
    const d = ce(`yr-cell${{hasYr?' has-year':''}}${{isCur?' is-cur':''}}`);
    if (hasYr) d.textContent = yr;
    if (isCur) {{ d.style.borderLeft='2px solid #FFD70066'; d.style.borderRight='2px solid #FFD70066'; }}
    g.appendChild(d);
  }});

  // ── 日付行 ──
  g.appendChild(ce('lbl lbl-top dt-lbl','週'));
  WEEKLY.forEach(w=>{{
    const isCur = w.week === CUR_WK;
    const mon = wkToMonday(w.week);
    const d = ce(`dt-cell${{isCur?' is-cur':''}}`);
    const wkNum = w.week.split('-W')[1];
    d.textContent = `W${{wkNum}}\n${{fmtDate(mon)}}`;
    if (isCur) {{ d.style.borderLeft='2px solid #FFD70066'; d.style.borderRight='2px solid #FFD70066'; }}
    g.appendChild(d);
  }});

  // ── データ行 ──
  const rows = [
    {{key:'fib',    lbl:'🌀 Fibo Zone',     color:'#CE93D8'}},
    {{key:'d1',     lbl:'🌍 D1 Phase+ADX',  color:'#90CAF9'}},
    {{key:'h4',     lbl:'📈 H4 Wave',       color:'#64B5F6'}},
    {{key:'atr',    lbl:'💨 ATR Class',     color:'#69F0AE'}},
    {{key:'adx',    lbl:'⚡ ADX',           color:'#CE93D8'}},
    {{key:'score',  lbl:'📊 H1 Score/TIER', color:'#82AAFF'}},
    {{key:'atrph',  lbl:'🌊 ATRフェーズ',   color:'#FFD180'}},
  ];

  rows.forEach(row=>{{
    // ラベル
    const lbl = ce('lbl');
    lbl.textContent = row.lbl;
    lbl.style.color = row.color;
    g.appendChild(lbl);

    WEEKLY.forEach(w=>{{
      const isCur = w.week === CUR_WK;
      const d = ce('c' + (isCur?' is-cur':''));
      // Tooltip
      const sp_d1 = w.d1_di_spread != null ? w.d1_di_spread.toFixed(1) : '?';
      const sp_h4 = w.h4_di_spread != null ? w.h4_di_spread.toFixed(1) : '?';
      d.title = `${{w.week}} (${{fmtDate(wkToMonday(w.week))}})\nD1:${{w.d1_pattern}} ADX${{w.d1_adx22?.toFixed(1)||'?'}} DI-sp${{sp_d1}}\nH4:${{w.h4_pattern}} ADX${{w.h4_adx46?.toFixed(1)||'?'}} DI-sp${{sp_h4}}\nATR:${{w.atr_class}} TIER:${{w.tier}}\nFibo:${{w.fib_zone}} pos${{w.fib_pos?.toFixed(2)||'?'}}`;

      switch(row.key) {{
        case 'fib': {{
          d.className += ' ' + (FIB_CLS[w.fib_zone]||'f0');
          const posStr = w.fib_pos != null ? `\n${{w.fib_pos.toFixed(2)}}` : '';
          d.innerHTML = `${{fibShort(w.fib_zone)}}<br><span style="font-size:.52rem;opacity:.7">${{posStr}}</span>`;
          break;
        }}
        case 'd1': {{
          d.className += ' ' + diClass(w.d1_pattern, w.d1_di_spread);
          const adx = w.d1_adx22 != null ? w.d1_adx22.toFixed(0) : '—';
          const sp  = w.d1_di_spread != null ? `sp${{w.d1_di_spread.toFixed(1)}}` : '';
          d.innerHTML = `${{w.d1_pattern||'—'}}<br><span style="font-size:.5rem;opacity:.7">${{adx}} ${{sp}}</span>`;
          break;
        }}
        case 'h4': {{
          d.className += ' ' + diClass(w.h4_pattern, w.h4_di_spread);
          const adx = w.h4_adx46 != null ? w.h4_adx46.toFixed(0) : '—';
          const sp  = w.h4_di_spread != null ? `sp${{w.h4_di_spread.toFixed(1)}}` : '';
          d.innerHTML = `${{w.h4_pattern||'—'}}<br><span style="font-size:.5rem;opacity:.7">${{adx}} ${{sp}}</span>`;
          break;
        }}
        case 'atr': {{
          d.className += ' ' + (ATR_CLS[w.atr_class]||'a0');
          const trend = {{CONTRACTING:'収縮',EXPANDING:'拡大',FLAT:'横ばい'}}[w.d1_atr_trend]||'';
          d.innerHTML = ({{CONTRACT:'CONT',NEUTRAL:'NTRL',EXPAND:'EXP'}}[w.atr_class]||'—')
            + `<br><span style="font-size:.5rem;opacity:.7">${{trend}}</span>`;
          break;
        }}
        case 'adx': {{
          // H4 ADX優先、なければD1
          const v = w.h4_adx46 ?? w.d1_adx22;
          d.setAttribute('style', adxBg(v));
          d.textContent = v != null ? v.toFixed(1) : '—';
          break;
        }}
        case 'score': {{
          if (w.score_v3 != null) {{
            d.setAttribute('style', scoreBg(w.score_v3));
            const tc = TIER_CLS[w.tier]||'t0';
            const badge = w.tier && w.tier!=='—'
              ? `<span class="${{tc}}" style="font-size:.5rem;padding:1px 4px;border-radius:3px;">${{w.tier}}</span>`
              : '';
            d.innerHTML = `${{w.score_v3}}<br>${{badge}}`;
          }} else if (w.tier && w.tier!=='—') {{
            d.className += ' ' + (TIER_CLS[w.tier]||'t0');
            const wr = {{S:'89%',A:'70%','A*':'65%',B:'51%',C:'44%',D:'39%'}}[w.tier]||'';
            d.innerHTML = `${{w.tier}}<br><span style="font-size:.5rem;opacity:.7">${{wr}}</span>`;
          }} else {{
            d.className += ' t0';
            d.textContent = '—';
          }}
          break;
        }}
        case 'atrph': {{
          const ph = w.atr_phase||'—';
          d.style.background = '#080f1e';
          d.style.color = ATR_PH_COLOR[ph]||'#3a5a7a';
          d.style.fontSize = '.56rem';
          d.textContent = atrPhShort(ph);
          break;
        }}
      }}
      g.appendChild(d);
    }});
  }});
}}

buildCards();
buildGrid();
setTimeout(()=>{{ document.querySelector('.scroll').scrollLeft=99999; }}, 80);
document.getElementById('upd').textContent =
  `${{WEEKLY.length}}週 ｜ 現在: ${{CUR_WK}} ｜ ソース: FractalWaveLog D1/H4 + scores.json`;
</script>
</body>
</html>"""
    return html

def main():
    print("📂 Loading data...")
    wave_data = load_json(WAVES_JSON)
    score_records = load_json(SCORES_JSON)
    score_data = aggregate_scores(score_records)
    merged = merge_weekly(wave_data, score_data)
    now = datetime.now()
    iso = now.isocalendar()
    current_week = f"{iso.year}-W{iso.week:02d}"
    html = generate_html(merged, current_week)
    os.makedirs(os.path.dirname(OUT_HTML), exist_ok=True)
    with open(OUT_HTML, "w", encoding="utf-8") as f:
        f.write(html)
    print(f"✅ {OUT_HTML}  ({len(html):,} bytes)")

if __name__ == "__main__":
    main()
