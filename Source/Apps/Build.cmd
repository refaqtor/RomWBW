@echo off
setlocal

set TOOLS=../../Tools

set PATH=%TOOLS%\tasm32;%TOOLS%\zx;%PATH%

set TASMTABS=%TOOLS%\tasm32

set ZXBINDIR=%TOOLS%/cpm/bin/
set ZXLIBDIR=%TOOLS%/cpm/lib/
set ZXINCDIR=%TOOLS%/cpm/include/

call :asm SysCopy || goto :eof
call :asm Assign || goto :eof
call :asm Format || goto :eof
call :asm Talk || goto :eof
call :asm OSLdr || goto :eof
call :asm Mode || goto :eof

zx Z80ASM -SYSGEN/F

zx MAC SURVEY.ASM -$PO
zx MLOAD25 -SURVEY.COM=SURVEY.HEX

setlocal & cd XM && call Build || exit /b 1 & endlocal
setlocal & cd FDU && call Build || exit /b 1 & endlocal

goto :eof

:asm
echo.
echo Building %1...
tasm -t80 -g3 -fFF %1.asm %1.com %1.lst
goto :eof