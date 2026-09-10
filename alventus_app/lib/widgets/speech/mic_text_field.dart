import 'package:flutter/material.dart';
import 'speech_service.dart';
import 'tts_service.dart';
import 'dictation_formatter.dart';

/// Campo de texto con botón de micrófono integrado.
///
/// Se comporta como un [TextFormField] normal (acepta controller, decoration,
/// validator, etc.) y añade un icono de micrófono en el `suffixIcon`. Al
/// pulsarlo, dicta e **inserta** el texto reconocido en la posición donde
/// estaba el cursor, sin sobrescribir el resto del contenido del campo.
///
/// Uso típico (sustituyendo un TextFormField existente):
/// ```dart
/// MicTextField(
///   controller: miController,
///   decoration: const InputDecoration(labelText: 'Descripción'),
///   maxLines: 3,
/// )
/// ```
class MicTextField extends StatefulWidget {
  const MicTextField({
    super.key,
    required this.controller,
    this.decoration,
    this.focusNode,
    this.keyboardType,
    this.maxLines = 1,
    this.minLines,
    this.readOnly = false,
    this.enabled = true,
    this.validator,
    this.onChanged,
    this.onFieldSubmitted,
    this.style,
    this.textInputAction,
    this.localeId,
    this.enableReadAloud = true,
    this.iconsAbove = false,
    this.iconsAboveLeadingOffset = 0,
    this.micColor = Colors.teal,
    this.micActiveColor = Colors.red,
    this.speakerColor = Colors.indigo,
    this.speakerActiveColor = Colors.deepPurple,
  });

  final TextEditingController controller;
  final InputDecoration? decoration;
  final FocusNode? focusNode;
  final TextInputType? keyboardType;
  final int? maxLines;
  final int? minLines;
  final bool readOnly;
  final bool enabled;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;
  final void Function(String)? onFieldSubmitted;
  final TextStyle? style;
  final TextInputAction? textInputAction;

  /// Ej: 'es_ES', 'en_US'. Si es null, se usa español ('es_ES') por
  /// defecto, en vez del idioma del sistema del teléfono.
  final String? localeId;

  /// Si es true (por defecto), muestra también un botón de altavoz para
  /// leer en voz alta el contenido actual del campo.
  final bool enableReadAloud;

  /// Si es true, los botones de altavoz y micrófono se muestran en una
  /// fila ENCIMA del campo (siempre visibles), en vez de incrustados
  /// dentro de él como prefixIcon/suffixIcon. Útil en campos de texto
  /// largo (como una descripción), donde los iconos dentro del campo
  /// quitan espacio útil para el propio texto. Por defecto es false,
  /// para no cambiar el aspecto de los campos ya existentes en la app.
  final bool iconsAbove;

  /// Espacio vacío a añadir ANTES del botón de altavoz cuando [iconsAbove]
  /// es true, para poder alinearlo en vertical con el icono de otro campo
  /// de la misma pantalla (por ejemplo, si ese otro campo tiene un icono
  /// propio delante del altavoz, aquí se reserva el mismo hueco).
  final double iconsAboveLeadingOffset;

  /// Color del icono de micrófono en reposo.
  final Color micColor;

  /// Color del icono de micrófono mientras está escuchando.
  final Color micActiveColor;

  /// Color del icono de altavoz en reposo.
  final Color speakerColor;

  /// Color del icono de altavoz mientras está leyendo.
  final Color speakerActiveColor;

  @override
  State<MicTextField> createState() => _MicTextFieldState();
}

class _MicTextFieldState extends State<MicTextField> {
  // Identificadores únicos de esta instancia para los servicios.
  late final Object _listenerId = this;
  late final Object _speakerId = MapEntry(this, 'tts');

  bool _isListening = false;
  bool _isSpeaking = false;
  bool _hasFocus = false;

  // Si no nos pasan un FocusNode propio, creamos uno interno: lo
  // necesitamos para saber cuándo el campo tiene el foco (y así mostrar
  // el botón de "ocultar teclado" solo mientras se está escribiendo).
  FocusNode? _internalFocusNode;
  FocusNode get _effectiveFocusNode => widget.focusNode ?? (_internalFocusNode ??= FocusNode());

  // Posición y longitud del texto dictado en la sesión actual, para poder
  // reemplazarlo (no duplicarlo) cada vez que llega un resultado parcial,
  // sin tocar el resto del texto que ya hubiera en el campo.
  int _insertStart = 0;
  int _lastDictatedLength = 0;

  @override
  void initState() {
    super.initState();
    // Precalienta el motor de reconocimiento (y pide el permiso de
    // micrófono si hace falta) en cuanto aparece el campo, para que la
    // primera pulsación del botón ya escuche desde el primer momento.
    SpeechService.instance.warmUp();
    _effectiveFocusNode.addListener(_handleFocusChange);
  }

  void _handleFocusChange() {
    if (!mounted) return;
    setState(() => _hasFocus = _effectiveFocusNode.hasFocus);
  }

  @override
  void dispose() {
    _effectiveFocusNode.removeListener(_handleFocusChange);
    _internalFocusNode?.dispose();
    SpeechService.instance.stopListening(_listenerId);
    TtsService.instance.stop(_speakerId);
    super.dispose();
  }

  Future<void> _toggleReadAloud() async {
    if (_isSpeaking) {
      await TtsService.instance.stop(_speakerId);
      setState(() => _isSpeaking = false);
      return;
    }

    // No tiene sentido leer en voz alta mientras se está dictando.
    if (_isListening) {
      await SpeechService.instance.stopListening(_listenerId);
      setState(() => _isListening = false);
    }

    final text = widget.controller.text;
    if (text.trim().isEmpty) return;

    final started = await TtsService.instance.speak(
      speakerId: _speakerId,
      text: text,
      // Si no se especifica un idioma concreto, se fuerza español en vez
      // de dejar que el motor use el idioma del sistema (que en algunos
      // teléfonos no coincide con el idioma real que habla el usuario).
      localeId: widget.localeId ?? 'es_ES',
      onDone: () {
        if (mounted) setState(() => _isSpeaking = false);
      },
    );

    if (started && mounted) {
      setState(() => _isSpeaking = true);
    }
  }

  Future<void> _toggleListening() async {
    if (_isListening) {
      await SpeechService.instance.stopListening(_listenerId);
      setState(() => _isListening = false);
      return;
    }

    // No tiene sentido escuchar dictado y leer en voz alta a la vez.
    if (_isSpeaking) {
      await TtsService.instance.stop(_speakerId);
      setState(() => _isSpeaking = false);
    }

    final controller = widget.controller;
    final selection = controller.selection;

    // Si no hay selección válida (p.ej. el campo no tenía foco), se dicta
    // al final del texto actual. Si la había, se inserta justo ahí.
    _insertStart = selection.isValid ? selection.start : controller.text.length;
    _lastDictatedLength = 0;

    // Pide el foco explícitamente (por si el campo no lo tenía), usando
    // el FocusNode efectivo para que funcione también cuando no se nos ha
    // pasado uno propio desde fuera.
    _effectiveFocusNode.requestFocus();

    final started = await SpeechService.instance.startListening(
      listenerId: _listenerId,
      // Igual que en la lectura en voz alta: se fuerza español por
      // defecto en vez de fiarse del idioma del sistema del teléfono.
      localeId: widget.localeId ?? 'es_ES',
      onPartial: (text, isFinal) {
        _applyDictatedText(text, isFinal: isFinal);
        if (isFinal && mounted) {
          setState(() => _isListening = false);
        }
      },
      onDone: () {
        if (mounted) setState(() => _isListening = false);
      },
    );

    if (started && mounted) {
      setState(() => _isListening = true);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No se pudo iniciar el reconocimiento de voz. '
            'Revisa los permisos de micrófono.',
          ),
        ),
      );
    }
  }

  /// Aplica el fragmento dictado, reemplazando únicamente la "ventana"
  /// interina de esta sesión (el texto provisional que aún puede cambiar).
  ///
  /// Cuando [isFinal] es true, el fragmento se da por definitivo: se fija
  /// en el texto y la ventana interina se reinicia vacía justo después.
  /// Esto es importante porque algunos motores (sobre todo en Android)
  /// reinician la escucha por dentro tras una pausa natural (p.ej. al decir
  /// "cambio de línea" entre párrafos), y en ese reinicio el siguiente
  /// fragmento que llega deja de ser "todo el texto dictado hasta ahora"
  /// y pasa a ser solo el trozo nuevo. Si no fijáramos lo anterior, ese
  /// trozo nuevo pisaría y borraría lo ya dictado.
  void _applyDictatedText(String rawDictated, {required bool isFinal}) {
    final controller = widget.controller;
    final fullText = controller.text;

    final before = fullText.substring(0, _insertStart);
    final afterStart = (_insertStart + _lastDictatedLength).clamp(0, fullText.length);
    final after = fullText.substring(afterStart);

    String formatted;
    if (isFinal && rawDictated.trim().isEmpty) {
      // Resultado final vacío: no había nada nuevo que confirmar. Dejamos
      // tal cual el último texto interino que ya se había mostrado, en
      // vez de sustituirlo por nada.
      formatted = fullText.substring(_insertStart, afterStart);
    } else {
      formatted = DictationFormatter.format(rawDictated, before);
    }

    final newText = '$before$formatted$after';
    final newCursorPos = _insertStart + formatted.length;

    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newCursorPos),
    );
    widget.onChanged?.call(newText);

    if (isFinal) {
      // Se fija este fragmento como definitivo: la próxima ventana
      // interina empieza vacía justo después, para no volver a tocarlo.
      _insertStart = newCursorPos;
      _lastDictatedLength = 0;
    } else {
      _lastDictatedLength = formatted.length;
    }
  }

  @override
  Widget build(BuildContext context) {
    final baseDecoration = widget.decoration ?? const InputDecoration();

    final showSpeaker = widget.enableReadAloud && widget.enabled;
    final showMic = widget.enabled && !widget.readOnly;

    final field = TextFormField(
      controller: widget.controller,
      focusNode: _effectiveFocusNode,
      keyboardType: widget.keyboardType,
      maxLines: _isListening ? (widget.maxLines ?? 1) : widget.maxLines,
      minLines: widget.minLines,
      readOnly: widget.readOnly,
      enabled: widget.enabled,
      validator: widget.validator,
      onChanged: widget.onChanged,
      onFieldSubmitted: widget.onFieldSubmitted,
      style: widget.style,
      textInputAction: widget.textInputAction,
      decoration: widget.iconsAbove
          ? baseDecoration
          : baseDecoration.copyWith(
              prefixIcon: showSpeaker ? _buildPrefixIcon(baseDecoration) : baseDecoration.prefixIcon,
              suffixIcon: showMic ? _buildSuffixIcon(baseDecoration) : baseDecoration.suffixIcon,
            ),
    );

    if (!widget.iconsAbove) {
      return field;
    }

    // Modo "iconos arriba": altavoz a la izquierda, micrófono a la
    // derecha (alineado con la posición del icono de micrófono en un
    // campo normal), y el botón de ocultar teclado junto al micrófono
    // cuando el campo tiene el foco.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.iconsAboveLeadingOffset > 0)
                  SizedBox(width: widget.iconsAboveLeadingOffset),
                if (showSpeaker)
                  IconButton(
                    tooltip: _isSpeaking ? 'Detener lectura' : 'Escuchar el texto',
                    icon: Icon(
                      _isSpeaking ? Icons.volume_up : Icons.volume_up_outlined,
                      color: _isSpeaking ? widget.speakerActiveColor : widget.speakerColor,
                    ),
                    onPressed: _toggleReadAloud,
                  )
                else
                  const SizedBox.shrink(),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_hasFocus)
                  IconButton(
                    tooltip: 'Ocultar teclado',
                    icon: const Icon(Icons.keyboard_hide),
                    onPressed: () => _effectiveFocusNode.unfocus(),
                  ),
                if (showMic)
                  IconButton(
                    tooltip: _isListening ? 'Detener dictado' : 'Dictar por voz',
                    icon: Icon(
                      _isListening ? Icons.mic : Icons.mic_none,
                      color: _isListening ? widget.micActiveColor : widget.micColor,
                    ),
                    onPressed: _toggleListening,
                  ),
              ],
            ),
          ],
        ),
        field,
      ],
    );
  }

  /// Botón de altavoz (escuchar), a la izquierda. Si el campo ya tenía un
  /// prefixIcon propio (p.ej. un icono de categoría), se muestra junto a él
  /// en vez de sustituirlo.
  Widget _buildPrefixIcon(InputDecoration baseDecoration) {
    final speakerButton = IconButton(
      tooltip: _isSpeaking ? 'Detener lectura' : 'Escuchar el texto',
      icon: Icon(
        _isSpeaking ? Icons.volume_up : Icons.volume_up_outlined,
        color: _isSpeaking ? widget.speakerActiveColor : widget.speakerColor,
      ),
      onPressed: _toggleReadAloud,
    );

    final original = baseDecoration.prefixIcon;
    if (original == null) return speakerButton;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [original, speakerButton],
    );
  }

  /// Botón de micrófono (dictar), a la derecha. Si el campo ya tenía un
  /// suffixIcon propio, se muestra junto a él en vez de sustituirlo.
  /// Cuando el campo tiene el foco (el teclado está visible), se añade
  /// también un botón para ocultarlo sin tener que tocar fuera del campo.
  Widget _buildSuffixIcon(InputDecoration baseDecoration) {
    final micButton = IconButton(
      tooltip: _isListening ? 'Detener dictado' : 'Dictar por voz',
      icon: Icon(
        _isListening ? Icons.mic : Icons.mic_none,
        color: _isListening ? widget.micActiveColor : widget.micColor,
      ),
      onPressed: _toggleListening,
    );

    final hideKeyboardButton = _hasFocus
        ? IconButton(
            tooltip: 'Ocultar teclado',
            icon: const Icon(Icons.keyboard_hide),
            onPressed: () => _effectiveFocusNode.unfocus(),
          )
        : null;

    final original = baseDecoration.suffixIcon;

    final buttons = <Widget>[
      if (original != null) original,
      if (hideKeyboardButton != null) hideKeyboardButton,
      micButton,
    ];

    if (buttons.length == 1) return buttons.first;

    return Row(mainAxisSize: MainAxisSize.min, children: buttons);
  }
}
