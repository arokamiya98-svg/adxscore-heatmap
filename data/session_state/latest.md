# 次セッションへの引き継ぎ（2026-06-17 VPS導入＋本拠地化構想セッション）

## 🎯 今日の流れと総括

「6/16深夜のシグナルで通知が来なかった」調査から始まり、**通知の構造的限界の特定 → VPS導入決定 → ABLENET契約 → iPad RDP接続成功 → VPS本拠地化構想**まで一気に進んだ。今日はここで「作戦会議」として区切り、**次セッションは「おぱの別荘作り（VPSにClaude Code導入）」から始める**のがあろさんの判断。

## ✅ 確定・実装したもの

### 通知問題の決着
- 6/16 03時のシグナルで通知が来なかった原因＝**PCスリープ中はMT5の計算が止まり `SendNotification()` が呼ばれない**（エキスパートログで3時台が完全に空白＝動かぬ証拠）。iPhone設定・MetaQuotes ID（FBA34CF9）はシロ。
- 一方 **6/17 03:05 の発火では通知成功**（「XAU 仕込み入りました ▲PatB BUY | 4340.23 / NORMAL帯 RISING_DECEL / D1 BU DN」）＝通知経路は生きてる。前回宿題「本物の発火で通知が飛ぶか」クリア。
- → スリープ＝通知死の構造的限界を埋めるためVPS導入へ。

### v4 mq5 に実装（ミラー＋MT5 Library配下 両方同期済み・⚠️**未コミット**）
- **発火ログ**：発火時に `[FIRE] 時刻 | パターン@価格 | ゾーン帯 H1pat | D1 cross dir | Notify=SENT-OK/FAIL` をエキスパートログに出力。`SendNotification` の戻り値で通知成否を記録（「発火したのに通知死んでる」線を潰せる）。通知ブロック（旧885-910付近）に追加。
- **テスト送信**：input `Send_Test_Notification`（既定false／ONでチャート適用時に1発テスト通知＋`[TEST]`ログ。使ったらOFFに戻す）。OnInitの `PrintFiltersStatus()` 後に挿入。
- あろさんがMac側でコンパイル→通知経路チェック→機能オフまで確認済み。

### VPS導入
- **ABLENET VPS Win1（メモリ2GB / 仮想2Core / SSD60GB）、新規1,587円/月、10日無料お試し（自動移行なし・初期費用0・縛り無し）** 契約完了。RDSライセンス（複数同時接続用＝個人は不要）は付けず。ストレージはSSD60GB選択（速度優先・容量は余裕）。
- **iPad（iPadOS 26.5 / iPad Pro 3rd gen）の Windows App（iOS版）でRDP接続成功**。MacはWindows AppがmacOS14必須で弾かれた（Ventura 13.7.8＝OS終端）→ iPadルートが正解。証明書警告は「続ける」で問題なし（ABLENET公式案内通り）。
- iPhoneにもWindows App入れれば**出先（農業中）から直接MT5チェック可能**＝席外し運用の完成形（※見すぎ＝トレードモード突入の運用ルールは後で決める）。

### コスト統合の気づき
- 今 ATR/ADX簡易アラートに月800円のアプリ（**Twelve Data由来**＝バーのズレで判明、Scriptableと同根）を払ってる→ VPS+MT5に一本化すれば実質+787円/月で「24h通知＋v4発火通知＋ATR/ADXアラート自前＋Mac軽量化」全部入り。
- 純正MT5 VPS($15≒2400円) vs ABLENET(1587円)：価格近いが**ABLENET=フルWindowsで③自動化(Python)できる**ので一択。純正はMT5専用箱でPython不可。

## 🏠 次セッションの起点 ＝「おぱの別荘作り」（VPS本拠地化）

あろさん構想：**VPSにClaude Code（おぱ）を住まわせ、プロジェクト本拠地をVPSへ**。狙い＝Mac故障対策（VPS＋GitHub多重バックアップ）＋セットアップ効率化（**インジ配置がgit clone一発**＝「ファイルのやり取り」問題が消える）＋将来の③週次自動化基盤。Mac依存から完全卒業。

### 別荘作りの段取り
1. VPSに Node.js インストール
2. git インストール
3. Claude Code インストール（`npm i -g @anthropic-ai/claude-code`）
4. Claudeログイン（あろさんのアカウント・複数端末利用）
5. ADXSCORE を git clone（GitHubから／インジ signals/ も一緒に来る）
6. メモリ移行（`~/.claude/projects/-Users-aro-Desktop-ADXSCORE/memory/` はリポジトリ外なので別途）
7. → VPS上におぱ復活
8. その流れで：MT5インストール → インジ配置（clone済みsignals/から）→ MetaQuotes ID設定 → 通知ON（**VPS側のみ／Mac側OFF**で二重回避）→ Send_Test_Notificationで疎通 → 発火待ち

## ⚠️ 次回までの準備・注意点
- **今日のv4変更を commit & push しておく**（VPSでclone時に最新v4が来るように）。※あろさんのOK確認後に実施（このセッションで提案済み、返事待ち）
- VPS 2GBで Claude Code＋MT5 が足りるか様子見（重ければWin2=3.5GBへ。縛り無し）
- メモリ（memory/）はリポジトリ外＝移行方法を決める（リポジトリに含める or 手動コピー）
- Claudeアカウントの複数端末ログイン可否を最初に確認

## 📋 積み残し（VPS導入で優先度変動）
- **執行接続**（WaveLog癖×signal_fires成績）＝中長期の本丸。VPS自動化が整ってから
- **①②Twelveズレ正規化**（Scriptable/アラートのデータ源をMT5正規値へ）＝本拠地化の後。これでアプリ800円も解約
- **③週次マップ自動化**（指標系=全自動可、波形=手動トレンドライン依存で半自動）
- v4通知コードの commit/push（上記準備に統合）

---
*次の起点＝「おぱの別荘作り」（VPSにClaude Code導入→本拠地化）。その流れでMT5セットアップ→24h通知稼働まで一気に。あろさんの「ファイルのやり取り」問題は git clone で解決する設計。*
