/// Convierte comandos de voz en español a signos de puntuación, y aplica
/// mayúscula automática al inicio de frase.
///
/// Los motores de reconocimiento nativos (Android/iOS) no añaden puntuación
/// de forma fiable, así que este es el truco estándar usado por apps de
/// dictado: el usuario dice "coma", "punto", etc. y aquí se sustituye por
/// el símbolo correspondiente.
class DictationFormatter {
  DictationFormatter._();

  // Orden importante: las frases más largas van primero para que
  // "punto y aparte" no se confunda con "punto".
  static final List<MapEntry<RegExp, String>> _replacements = [
    _word('punto y aparte', '.\n\n'),
    _word('punto y seguido', '. '),
    _word('punto y coma', '; '),
    _word('dos puntos', ': '),
    _word('abre interrogación', '¿'),
    _word('abre interrogacion', '¿'),
    _word('cierra interrogación', '?'),
    _word('cierra interrogacion', '?'),
    _word('signo de interrogación', '?'),
    _word('signo de interrogacion', '?'),
    _word('abre exclamación', '¡'),
    _word('abre exclamacion', '¡'),
    _word('cierra exclamación', '!'),
    _word('cierra exclamacion', '!'),
    _word('signo de exclamación', '!'),
    _word('signo de exclamacion', '!'),
    _word('nueva línea', '\n'),
    _word('nueva linea', '\n'),
    _word('salto de línea', '\n'),
    _word('salto de linea', '\n'),
    _word('cambio de línea', '\n'),
    _word('cambio de linea', '\n'),
    _word('comillas', '"'),
    _word('coma', ', '),
    _word('punto', '. '),
  ];

  static MapEntry<RegExp, String> _word(String phrase, String symbol) {
    // \b no funciona bien con acentos en Dart regex, así que usamos
    // espacios/inicio-fin de cadena como límites de palabra.
    final pattern = RegExp(
      r'(^|\s)' + RegExp.escape(phrase) + r'(?=\s|$)',
      caseSensitive: false,
    );
    return MapEntry(pattern, symbol);
  }

  /// Aplica los reemplazos de comandos de voz y limpia espacios sobrantes
  /// alrededor de la puntuación resultante.
  static String applyVoiceCommands(String text) {
    var result = text;

    for (final entry in _replacements) {
      result = result.replaceAllMapped(entry.key, (match) {
        final leadingSpace = match.group(1) ?? '';
        // Si el comando estaba al principio del texto, no añadimos espacio
        // antes del símbolo.
        return leadingSpace.isEmpty ? entry.value : leadingSpace + entry.value;
      });
    }

    // Quita espacios justo antes de . , ; : ! ?
    result = result.replaceAllMapped(
      RegExp(r'\s+([.,;:!?])'),
      (m) => m.group(1)!,
    );

    // Colapsa espacios múltiples en uno solo (pero conserva saltos de línea).
    result = result.replaceAll(RegExp(r'[ \t]{2,}'), ' ');

    return result;
  }

  /// Pone en mayúscula la primera letra de [dictated] si, según el texto
  /// que le precede ([precedingText]), estamos al inicio de una frase
  /// (inicio absoluto del campo, o tras '.', '!', '?' o salto de línea).
  static String applySentenceCase(String dictated, String precedingText) {
    if (dictated.isEmpty) return dictated;

    final trimmedBefore = precedingText.trimRight();
    final startsNewSentence = trimmedBefore.isEmpty ||
        RegExp(r'[.!?\n]$').hasMatch(trimmedBefore);

    if (!startsNewSentence) return dictated;

    // Busca el primer carácter alfabético para capitalizarlo (por si el
    // texto dictado empieza con un espacio o símbolo).
    final firstLetterIndex = dictated.indexOf(RegExp(r'[a-zA-ZñÑáéíóúÁÉÍÓÚ]'));
    if (firstLetterIndex == -1) return dictated;

    return dictated.substring(0, firstLetterIndex) +
        dictated[firstLetterIndex].toUpperCase() +
        dictated.substring(firstLetterIndex + 1);
  }

  /// Aplica ambas transformaciones en el orden correcto: primero los
  /// comandos de voz, luego la mayúscula de inicio de frase.
  static String format(String dictated, String precedingText) {
    final withPunctuation = applyVoiceCommands(dictated);
    return applySentenceCase(withPunctuation, precedingText);
  }
}
