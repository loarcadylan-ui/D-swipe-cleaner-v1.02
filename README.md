# 📱 SwipeClean - Limpiador de Galería Android en Flutter

Aplicación de uso personal estilo Tinder para limpiar fotos y capturas de pantalla rápidamente deslizando a la izquierda (papelera) o derecha (conservar).

---

## ⚡ Método 1: Compilación Automática en 1 Clic (Recomendado)

### En Windows:
Haz doble clic sobre el archivo:
```cmd
build_apk.bat
```
El script completará los archivos de Android que faltan, descargará las dependencias y compilará el `.apk` en:
`build/app/outputs/flutter-apk/app-release.apk`

### En Linux o macOS:
Abre una terminal en la carpeta del proyecto y ejecuta:
```bash
chmod +x build_apk.sh
./build_apk.sh
```

---

## ☁️ Método 2: Compilación 100% en la Nube (Sin instalar nada)

Si no tienes Flutter instalado en tu computadora:
1. Sube esta carpeta a un repositorio privado de **GitHub**.
2. Ve a la pestaña **Actions** en GitHub.
3. El workflow `Compilar APK Android SwipeClean` se ejecutará automáticamente.
4. En 2 minutos podrás descargar el archivo APK directamente en la sección **Artifacts** de GitHub.

---

## 📲 Cómo instalar el APK en tu teléfono Android

1. Envía el archivo `app-release.apk` a tu móvil mediante:
   - WhatsApp Web / Telegram a ti mismo.
   - O súbelo a Google Drive.
   - O por cable USB usando ADB:
     ```bash
     adb install -r build/app/outputs/flutter-apk/app-release.apk
     ```
2. En tu móvil, toca el archivo descargado.
3. Si Android muestra el aviso "Instalar aplicaciones desconocidas", pulsa **Configuración** y activa el interruptor para permitirlo (esto es normal en APKs personales sin firmar de Google Play).
4. Abre **SwipeClean**, concede el permiso de galería y ¡a limpiar fotos deslizando!
