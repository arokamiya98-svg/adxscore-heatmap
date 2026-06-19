@echo off
REM ============================================================
REM vps_data_pool_push.bat — タスクスケジューラ用ラッパー
REM   schtasks の /TR で bash の二重引用符エスケープを避けるため、
REM   .bat 経由で Git Bash スクリプトを起動する（設計書 §7）。
REM ============================================================
"C:\Program Files\Git\bin\bash.exe" -lc "/c/Users/Administrator/adxscore-heatmap/scripts/vps_data_pool_push.sh"
