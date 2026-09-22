@echo off
setlocal
where cl.exe >nul 2>nul
if errorlevel 1 call "%ProgramFiles(x86)%\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat" >nul
where cl.exe >nul 2>nul
if errorlevel 1 exit /b 1
set "KYBER_TEST_OUT=%TEMP%\kyber-localization-tests"
if not exist "%KYBER_TEST_OUT%" mkdir "%KYBER_TEST_OUT%"
cl.exe /nologo /EHsc /std:c++17 /utf-8 /I"%~dp0..\Module\Public" "%~dp0..\Module\Tests\LocalizationCodecTest.cpp" /Fe:"%KYBER_TEST_OUT%\localization-test.exe" /Fo:"%KYBER_TEST_OUT%\localization-test.obj"
if errorlevel 1 exit /b 1
"%KYBER_TEST_OUT%\localization-test.exe"
exit /b %ERRORLEVEL%
