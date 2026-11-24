@echo off
title piercer_errorwatch - painel web
rem 
rem 
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0server.ps1" -Open %*
pause
