#!/usr/bin/env bash
# ==============================================================================
# Script de compilación automática del APK de SwipeClean
# Compatible con Linux y macOS
# ==============================================================================
set -e

echo "[1/4] Verificando instalación de Flutter..."
if ! command -v flutter &> /dev/null; then
    echo "Error: Flutter no está instalado o no se encuentra en el PATH."
    echo "Descárgalo desde: https://docs.flutter.dev/get-started/install"
    exit 1
fi

echo "[2/4] Completando archivos de Android que faltan (no sobrescribe los existentes)..."
flutter create . --platforms=android --org com.personal --project-name swipe_clean

echo "[3/4] Descargando dependencias..."
flutter pub get

echo "Generando ícono de la app..."
dart run flutter_launcher_icons || echo "(No se pudo generar el ícono; se usará el de Flutter)"

echo "[4/4] Compilando APK Release..."
flutter build apk --release

echo ""
echo "=============================================================================="
echo "Compilación completada. Tu APK está en:"
echo "   build/app/outputs/flutter-apk/app-release.apk"
echo "=============================================================================="
echo ""
echo "Para instalarlo en tu teléfono conectado por USB:"
echo "   adb install -r build/app/outputs/flutter-apk/app-release.apk"
