@echo off
setlocal
set KYBER_LAN_ONLY=1
set KYBER_ONLINE_MODE=0
set KYBER_API_TOKEN=
start "" /D "%~dp0" "%~dp0kyber_launcher.exe"
