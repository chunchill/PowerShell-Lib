@echo off
set base_dir=%~dp0 
%base_dir:~0,2% 
cd %base_dir%
mode con cols=120
powershell -nologo -noprofile  -executionpolicy "remotesigned" -sta  ".\bin\ps_start_main.ps1"
pause