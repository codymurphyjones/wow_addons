@echo off
python "%~dp0addon_sync.py" %*
if "%~1"=="" pause
