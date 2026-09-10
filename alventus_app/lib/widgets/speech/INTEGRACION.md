# Integrar dictado por voz en alventus_app

Estos dos archivos son un módulo autocontenido que puedes copiar tal cual a
tu proyecto:

- `speech_service.dart` → un singleton que gestiona el motor de
  reconocimiento (solo un campo puede escuchar a la vez; si activas el
  micrófono en un campo mientras otro estaba dictando, el anterior se
  detiene automáticamente).
- `mic_text_field.dart` → el widget `MicTextField`, un reemplazo directo de
  `TextFormField` con un botón de micrófono en el `suffixIcon`. Al dictar,
  **inserta** el texto en la posición del cursor sin tocar el resto del
  contenido (no sobrescribe).

## 1. Copiar archivos

Colócalos, por ejemplo, en:
```
C:\Flutter\alventus_app\lib\widgets\speech\speech_service.dart
C:\Flutter\alventus_app\lib\widgets\speech\mic_text_field.dart
```

## 2. Añadir dependencias

En tu `pubspec.yaml` ya existente, añade (sin borrar lo que ya tengas):

```yaml
dependencies:
  speech_to_text: ^7.0.0
```

(`permission_handler` es opcional: `speech_to_text` ya gestiona los
permisos de micrófono internamente vía `initialize()`.)

Luego:
```bash
flutter pub get
```

## 3. Permisos nativos

**Android** — en `android/app/src/main/AndroidManifest.xml`, dentro de
`<manifest>` (junto a los permisos que ya tengas, sin borrarlos):
```xml
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.INTERNET" />
```

**iOS** — en `ios/Runner/Info.plist`, dentro de `<dict>`:
```xml
<key>NSMicrophoneUsageDescription</key>
<string>Esta app necesita acceso al micrófono para dictar texto por voz.</string>
<key>NSSpeechRecognitionUsageDescription</key>
<string>Esta app usa reconocimiento de voz para convertir lo que dices en texto.</string>
```

## 4. Sustituir tus campos de texto

Donde tengas algo así:
```dart
TextFormField(
  controller: descripcionController,
  decoration: const InputDecoration(labelText: 'Descripción'),
)
```

Cámbialo por:
```dart
MicTextField(
  controller: descripcionController,
  decoration: const InputDecoration(labelText: 'Descripción'),
)
```

`MicTextField` acepta los mismos parámetros que usas normalmente
(`validator`, `onChanged`, `maxLines`, `readOnly`, `enabled`, `keyboardType`,
etc.), así que en la mayoría de los casos el cambio es solo el nombre del
widget.

### Si tus campos se generan dinámicamente según el tipo de Odoo

Si tienes (como es habitual) un widget tipo `OdooFieldRenderer` o similar
que decide qué widget mostrar según `field.type` (`char`, `text`, `many2one`,
`boolean`...), lo más limpio es tocar solo el `case` de `char`/`text` para
que use `MicTextField` en lugar de `TextFormField`. Así el micrófono aparece
automáticamente en todos los campos de texto de todos los formularios, sin
tener que tocar cada formulario uno a uno.

Si me pegas ese fragmento de código (el que decide el widget por tipo de
campo), te lo adapto exacto para que encaje sin más cambios.

## Notas de comportamiento

- El dictado siempre inserta en la posición del cursor; si el campo no
  tenía foco al pulsar el micrófono, se inserta al final del texto
  existente.
- Solo un campo escucha a la vez en toda la app (evita conflictos de
  micrófono entre formularios).
- El botón cambia de color (rojo) mientras está escuchando activamente.
- Si el reconocimiento falla (sin permisos, sin servicio disponible), se
  muestra un `SnackBar` con el aviso.
