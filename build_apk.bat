@echo off
chcp 65001 >nul
title Compilador Automatico de APK - SwipeClean

echo ==============================================================================
echo   Iniciando compilador automatico de APK para SwipeClean (Android)
echo ==============================================================================
echo.

where flutter >nul 2>nul
if %errorlevel% neq 0 (
    echo [ERROR] Flutter no esta en el PATH del sistema.
    echo Instala Flutter SDK y agregalo a tus variables de entorno.
    echo Descarga: https://docs.flutter.dev/get-started/install/windows
    pause
    exit /b 1
)

echo [1/3] Completando archivos de Android que faltan (no sobrescribe los existentes)...
call flutter create . --platforms=android --org com.personal --project-name swipe_clean
if %errorlevel% neq 0 (
    echo [ERROR] Fallo al completar el proyecto Android.
    pause
    exit /b 1
)

echo.
echo [2/3] Descargando dependencias...
call flutter pub get
if %errorlevel% neq 0 (
    echo [ERROR] Fallo la descarga de dependencias.
    pause
    exit /b 1
)

echo.
echo Generando icono de la app...
call dart run flutter_launcher_icons

echo.
echo [3/3] Compilando APK Release (puede tardar unos minutos la primera vez)...
call flutter build apk --release
if %errorlevel% neq 0 (
    echo [ERROR] Ocurrio un error al compilar el APK.
    pause
    exit /b 1
)

echo.
echo ==============================================================================
echo  EXITO. APK generado en:
echo  %CD%\build\app\outputs\flutter-apk\app-release.apk
echo ==============================================================================
echo.
pause
