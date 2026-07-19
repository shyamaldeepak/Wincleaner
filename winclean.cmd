@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0winclean.ps1" %*
