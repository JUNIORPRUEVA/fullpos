import 'dart:async';

import 'package:flutter/services.dart';

/// Controlador reutilizable para lectores de códigos que actúan como teclado.
class ScannerInputController {
  final bool enabled;
  final String suffix;
  final String? prefix;
  final Duration timeout;
  final bool emitOnTimeout;
  final void Function(String data)? onScan;

  final StringBuffer _buffer = StringBuffer();
  Timer? _timer;

  ScannerInputController({
    required this.enabled,
    required this.suffix,
    required this.timeout,
    this.prefix,
    this.emitOnTimeout = true,
    this.onScan,
  });

  String? _resolvePrintableCharacter(RawKeyEvent event) {
    final c = event.character;
    if (c != null && c.isNotEmpty) return c;

    // En desktop (Windows) es común que `character` venga null cuando no hay
    // un TextField enfocado. En ese caso, usamos `keyLabel` para teclas
    // imprimibles (letras/números/símbolos).
    final label = event.logicalKey.keyLabel;
    if (label.length == 1) return label;
    return null;
  }

  bool _isEnterSuffix() {
    // Muchos lectores envían ENTER como final de lectura (\n / \r / \r\n).
    // En Windows, a veces ENTER no llega como `event.character`, sino como
    // LogicalKeyboardKey.enter.
    return suffix == '\n' || suffix == '\r' || suffix == '\r\n';
  }

  void handleKeyEvent(RawKeyEvent event) {
    if (!enabled) return;
    if (event is! RawKeyDownEvent) return;

    // ENTER (o NUMPAD ENTER) como terminador: emitir el buffer aunque
    // `event.character` venga nulo.
    final logical = event.logicalKey;
    final isEnterKey =
        logical == LogicalKeyboardKey.enter ||
        logical == LogicalKeyboardKey.numpadEnter;
    if (isEnterKey && _buffer.isNotEmpty && _isEnterSuffix()) {
      _emitBuffer(trimSuffix: false);
      return;
    }

    final character = _resolvePrintableCharacter(event);
    if (character == null || character.isEmpty) return;

    // Algunos escáneres envían salto de línea como caracter (\r / \n).
    // Si el sufijo está configurado como terminador de línea, emitir.
    if ((character == '\n' || character == '\r') &&
        _buffer.isNotEmpty &&
        _isEnterSuffix()) {
      _emitBuffer(trimSuffix: false);
      return;
    }

    _buffer.write(character);
    _restartTimer();

    final text = _buffer.toString();
    if (text.endsWith(suffix)) {
      _emitBuffer(trimSuffix: true);
    }
  }

  void _restartTimer() {
    _timer?.cancel();
    _timer = Timer(timeout, () {
      if (emitOnTimeout) {
        _emitBuffer(trimSuffix: false);
      } else {
        _buffer.clear();
      }
    });
  }

  void _emitBuffer({required bool trimSuffix}) {
    if (_buffer.isEmpty) return;
    var data = _buffer.toString();
    if (trimSuffix && data.endsWith(suffix)) {
      data = data.substring(0, data.length - suffix.length);
    }
    if (prefix != null && prefix!.isNotEmpty && data.startsWith(prefix!)) {
      data = data.substring(prefix!.length);
    }

    // Evitar emisiones vacías (p.ej. si solo llegó ENTER).
    if (data.trim().isEmpty) {
      _buffer.clear();
      _timer?.cancel();
      return;
    }

    _buffer.clear();
    _timer?.cancel();
    onScan?.call(data);
  }

  void dispose() {
    _timer?.cancel();
  }
}
