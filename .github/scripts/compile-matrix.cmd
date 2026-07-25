@echo off
rem Compile-check the headers across every PHNT_VERSION, as both C and C++.
rem
rem This is the gate that guards `master`: if upstream lands headers that do not
rem compile, the merge is held back and the next sync retries. It catches syntax
rem errors, missing types and broken version guards -- NOT a struct field at the
rem wrong offset, which is the failure mode these headers actually have.
rem
rem Locates MSVC itself via vswhere, so it runs identically on a GitHub runner
rem and on a developer box.
rem
rem The workflow fans out over arch/compiler as a job matrix -- those are a
rem handful of genuinely parallel cells, each needing its own vcvars. The
rem PHNT_VERSION loop stays in here: 58 cells of ~0.6s each would otherwise pay
rem ~50s of runner startup apiece to do less than a second of work.
rem
rem Usage:  compile-matrix.cmd [include-dir] [arch] [compiler]
rem           include-dir  defaults to the repo root (two levels up)
rem           arch         x64 (default) | x86 | arm64
rem           compiler     cl (default) | clang-cl

setlocal enabledelayedexpansion

set "HDRS=%~1"
if "%HDRS%"=="" for %%i in ("%~dp0..\..") do set "HDRS=%%~fi"

set "ARCH=%~2"
if "%ARCH%"=="" set "ARCH=x64"

set "CC=%~3"
if "%CC%"=="" set "CC=cl"
rem CC may be rewritten to a full path below; keep a short label for reporting.
set "CCNAME=%CC%"

rem clang-cl takes its target from the flag, not from vcvars.
set "CCFLAGS="
if /i "%CC%"=="clang-cl" (
  if /i "%ARCH%"=="x86"   set "CCFLAGS=-m32"
  if /i "%ARCH%"=="arm64" set "CCFLAGS=--target=aarch64-pc-windows-msvc"
)

if /i "%ARCH%"=="x64"   set "VCVARS=vcvars64.bat"
if /i "%ARCH%"=="x86"   set "VCVARS=vcvars32.bat"
if /i "%ARCH%"=="arm64" set "VCVARS=vcvarsamd64_arm64.bat"
if not defined VCVARS (
  echo ERROR: unknown arch "%ARCH%" ^(expected x64, x86 or arm64^)
  exit /b 2
)

set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%VSWHERE%" (
  echo ERROR: vswhere not found; is Visual Studio installed?
  exit /b 2
)
for /f "usebackq tokens=*" %%i in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VSPATH=%%i"
if not defined VSPATH (
  echo ERROR: no Visual Studio install with the C++ toolset
  exit /b 2
)

call "%VSPATH%\VC\Auxiliary\Build\%VCVARS%" >nul 2>&1
if errorlevel 1 (
  echo ERROR: %VCVARS% failed ^(toolset for %ARCH% not installed?^)
  exit /b 2
)

rem The runner ships standalone LLVM on PATH, but VS also bundles a clang-cl that
rem is not. Fall back to the bundled one rather than failing the gate over a PATH
rem detail -- a red gate should mean "the headers broke", never "no compiler".
if /i not "%CC%"=="clang-cl" goto :cc_ok
where clang-cl >nul 2>&1
if not errorlevel 1 goto :cc_ok
if exist "%VSPATH%\VC\Tools\Llvm\bin\clang-cl.exe" (
  set "CC=%VSPATH%\VC\Tools\Llvm\bin\clang-cl.exe"
  goto :cc_ok
)
echo ERROR: clang-cl found neither on PATH nor at "%VSPATH%\VC\Tools\Llvm\bin\"
exit /b 2
:cc_ok

set "WORK=%TEMP%\phnt-matrix-%ARCH%"
if not exist "%WORK%" mkdir "%WORK%"
> "%WORK%\tu.c" echo #include ^<phnt_windows.h^>
>>"%WORK%\tu.c" echo #include ^<phnt.h^>
copy /y "%WORK%\tu.c" "%WORK%\tu.cpp" >nul

echo Headers:  %HDRS%
echo Arch:     %ARCH%
echo Compiler: %CC% %CCFLAGS%
echo.

set /a FAILED=0
set /a TOTAL=0

rem PHNT_VERSION values from phnt.h, plus NEW (the default when undefined).
for %%V in (0 51 52 60 61 62 63 100 101 102 103 104 105 106 107 108 109 110 111 112 113 114 115 116 117 118 119 120 NEW) do (
  for %%L in (c cpp) do (
    set /a TOTAL+=1
    if "%%V"=="NEW" (
      %CC% /nologo /c /W3 %CCFLAGS% /I"%HDRS%" "%WORK%\tu.%%L" /Fo"%WORK%\o.obj" >"%WORK%\out.txt" 2>&1
    ) else (
      %CC% /nologo /c /W3 %CCFLAGS% /DPHNT_VERSION=%%V /I"%HDRS%" "%WORK%\tu.%%L" /Fo"%WORK%\o.obj" >"%WORK%\out.txt" 2>&1
    )
    if errorlevel 1 (
      set /a FAILED+=1
      echo FAIL  %ARCH%/%CC%  PHNT_VERSION=%%V  %%L
      type "%WORK%\out.txt"
      echo.
    ) else (
      echo ok    %ARCH%/%CC%  PHNT_VERSION=%%V  %%L
    )
  )
)

echo.
echo %ARCH%/%CC%: !FAILED! failed of !TOTAL!

rem Surface the verdict on the workflow run page, not just in the job log.
if defined GITHUB_STEP_SUMMARY (
  if !FAILED! gtr 0 (
    echo - **%ARCH% / %CC%** - !FAILED! failed of !TOTAL!>>"%GITHUB_STEP_SUMMARY%"
  ) else (
    echo - **%ARCH% / %CC%** - all !TOTAL! configurations compiled>>"%GITHUB_STEP_SUMMARY%"
  )
)

if !FAILED! gtr 0 exit /b 1
exit /b 0
