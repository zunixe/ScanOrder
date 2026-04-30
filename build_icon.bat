@echo off
echo === Building ScanOrder Icon === > build_icon_log.txt 2>&1

powershell -ExecutionPolicy Bypass -File assets\logo\generate_icon.ps1 >> build_icon_log.txt 2>&1
echo PowerShell done, errorlevel=%ERRORLEVEL% >> build_icon_log.txt 2>&1

dir assets\logo\scanorder_icon.png >> build_icon_log.txt 2>&1

flutter pub get >> build_icon_log.txt 2>&1
flutter pub run flutter_launcher_icons >> build_icon_log.txt 2>&1

echo === Done === >> build_icon_log.txt 2>&1
