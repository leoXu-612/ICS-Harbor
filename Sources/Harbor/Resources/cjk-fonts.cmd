@echo off
reg add "HKLM\Software\Microsoft\Windows NT\CurrentVersion\Fonts" /v "Noto Sans CJK SC (OpenType)" /t REG_SZ /d "NotoSansCJKsc-Regular.otf" /f
if errorlevel 1 exit /b 1
reg add "HKLM\Software\Microsoft\Windows NT\CurrentVersion\FontSubstitutes" /v "Tahoma" /t REG_SZ /d "Noto Sans CJK SC" /f
if errorlevel 1 exit /b 1
reg add "HKLM\Software\Microsoft\Windows NT\CurrentVersion\FontSubstitutes" /v "MS Shell Dlg 2" /t REG_SZ /d "Noto Sans CJK SC" /f
if errorlevel 1 exit /b 1
reg add "HKLM\Software\Microsoft\Windows NT\CurrentVersion\FontSubstitutes" /v "SimSun" /t REG_SZ /d "Noto Sans CJK SC" /f
if errorlevel 1 exit /b 1
reg add "HKLM\Software\Microsoft\Windows NT\CurrentVersion\FontSubstitutes" /v "NSimSun" /t REG_SZ /d "Noto Sans CJK SC" /f
if errorlevel 1 exit /b 1
echo harbor-cjk-v1>C:\harbor-cjk-ready.txt
