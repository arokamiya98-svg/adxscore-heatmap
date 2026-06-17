---
name: project_vps-base-2026-06
description: VPS（ABLENET/Windows Server 2022）にClaude Code導入完了。Mac=記憶母艦/VPS=24h前線のハイブリッド運用へ。リポジトリPUBLIC要検討
metadata: 
  node_type: memory
  type: project
  originSessionId: d01183c3-25d4-4c1e-b3e9-8855bbb0110a
---

2026-06-17、VPS本拠地化の「別荘作り」完了。狙い＝Mac故障対策（VPS＋GitHub多重バックアップ）＋セットアップ効率化（インジ配置がgit clone一発＝「ファイルのやり取り」問題が消える）＋将来の週次自動化基盤。

**構成**：ABLENET VPS（Windows Server 2022 Standard / 2GB / 仮想2Core / SSD60GB / 1,587円/月・縛り無し）に Node.js・Git・Claude Code・Python 3.14.6 を導入。リポジトリ `arokamiya98-svg/adxscore-heatmap`（**PUBLIC**）を `C:\Users\Administrator\adxscore-heatmap` に git clone。

**操作経路**：iPad の Windows App（RDP）。Macは Windows App 非対応（macOS14必須、Ventura終端）＝iPadルートが正解。Claudeログインは複数端末OK（Mac/VPS同時に同アカウント可）。

**フック修正**：`.claude/hooks/session-start.sh` をMac/VPS両対応に（`command -v python3 || command -v python` フォールバック＋`sys.stdout.reconfigure(encoding="utf-8")`）。Windowsは Python が `python` 名・標準出力 cp932 で、latest.md の絵文字が `UnicodeEncodeError` になるのが要因だった。

**運用方針**：当面ハイブリッド。Mac側おぱ＝記憶完全な思考母艦（戦略/BT/振り返り、入力も楽）、VPS側おぱ＝24h実行前線（MT5一体/通知/自動化/出先RDP）。最終的にVPS主力へ。

**積み残し**：VPS側メモリ未移行（CLAUDE.mdのみの素のおぱ）/ git config user.name/email 未設定 / **PUBLICリポジトリのprivate化要検討**（メモリ移行で個人情報をリポジトリ経由で運ぶと全世界公開リスク＝移行とセットで判断）/ VPS側MT5セットアップ（24h通知）。
[[project_fwd-data-pipeline-weakness]] [[project_hardware-mac-environment]] [[project_roadmap-sensory-to-logic-phase]]
