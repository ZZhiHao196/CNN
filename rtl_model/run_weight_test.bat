 @echo off
echo ===== Weight ROM Testbench =====
echo Compiling weight.v and weight_tb.v...

iverilog -o weight_test.exe weight.v weight_tb.v
if %errorlevel% neq 0 (
    echo Compilation failed!
    pause
    exit /b 1
)

echo Compilation successful!
echo Running testbench...
vvp weight_test.exe

echo.
echo Testbench completed!
echo Check weight_tb.vcd for waveforms
pause