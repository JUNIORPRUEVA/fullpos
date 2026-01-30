import 'package:flutter/material.dart';

class ConfirmPhraseResult {
  ConfirmPhraseResult({
    required this.phrase,
    required this.pin,
  });

  final String phrase;
  final String pin;
}

class ConfirmPhraseDialog extends StatefulWidget {
  const ConfirmPhraseDialog({
    super.key,
    required this.title,
    required this.message,
    required this.phraseHint,
    required this.confirmText,
  });

  final String title;
  final String message;
  final String phraseHint;
  final String confirmText;

  @override
  State<ConfirmPhraseDialog> createState() => _ConfirmPhraseDialogState();
}

class _ConfirmPhraseDialogState extends State<ConfirmPhraseDialog> {
  final _phraseCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();

  @override
  void dispose() {
    _phraseCtrl.dispose();
    _pinCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.message),
          const SizedBox(height: 12),
          TextField(
            controller: _phraseCtrl,
            decoration: InputDecoration(
              labelText: widget.phraseHint,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pinCtrl,
            decoration: const InputDecoration(labelText: 'PIN admin'),
            obscureText: true,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            ConfirmPhraseResult(
              phrase: _phraseCtrl.text.trim(),
              pin: _pinCtrl.text.trim(),
            ),
          ),
          child: Text(widget.confirmText),
        ),
      ],
    );
  }
}
