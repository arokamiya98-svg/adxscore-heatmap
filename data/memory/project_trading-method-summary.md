---
name: trading-method-summary
description: 現在のトレード手法。ATR×ADX戦略、ATR=タイミング指標(ボトムアウト)、ADX=評価軸(先行指標ではない)、多時間軸の役割分担
metadata: 
  node_type: memory
  type: project
  originSessionId: 9680f5e6-e416-42b9-9329-3c878ab13dc9
---

2026-06-01に本人言語化された手法サマリー。CLAUDE.md セクション 2/5 と整合性あり、より具体的なルールが追加された。

## 全体構造

- **ATR = タイミング指標**（ボトムアウト採用）
- **ADX = 評価軸**（先行指標ではない、スコア化で領域認識）

## 多時間軸の役割

| TF | 役割 | キー判定 |
|----|------|---------|
| D1 | 俯瞰・周期 | BU/PD、ADX方向、大局フェーズ |
| H4 | 戦略立案 | クロスポイント、H4ボトム、重めADXでトレンド方向 |
| H1 | 執行 | エントリー/エグジット、イベント・曜日・時間帯 |

## H1の具体ルール

- 出来高時間帯: OPEN、東京、ロンドン、米国
- 収縮パターン: 三尊、逆三尊、Wトップ、Wボトム
- 保有時間: **3時間 〜 2日**
- **H1 ADX 35超え = 冷え待ち**（過熱でエントリーしない）

## 戦略中核思想

**「重めのADXでトレンドに逆らわない方向でトレードできる環境」を常に意識**
= 大局トレンドに沿った方向のみエントリー、逆張りは基本しない。

## ATRパターン優先順（CLAUDE.md 5節）

1. RISING_DECEL × NORMAL（最優先、PF 8〜10クラス）
2. EXPANDING × HIGH（第2）
3. RISING_ACCEL（H4フィルター厳格化）
4. CONTRACTING系（スキップ）

## 関連

- CLAUDE.md セクション 5: スコア設計・ATRパターン優先順
- [[capital-management-flow-and-theory]] - 軸C戦略遂行の判定基準
- [[retrospection-three-axes]] - 軸A個別判断・軸B方向性の判定基準
- aro-おぱ/02_principles/trading_method.md - ユーザー側参照ファイル
