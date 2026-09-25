import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/theme.dart';
import '../services/voice_typing_service.dart';

/// Mic suffix button that dictates English or Bangla into a text field.
///
/// Tap → language popup (English / বাংলা) → live dictation fills the
/// controller. Tapping again stops listening. Use [VoiceTextField] as a
/// drop-in `TextFormField` replacement, or place this button inside an
/// `InputDecoration.suffixIcon` of an existing field.
class VoiceMicButton extends StatefulWidget {
  const VoiceMicButton({
    super.key,
    required this.controller,
    this.enabled = true,
    this.append = true,
    this.onListeningChanged,
  });

  final TextEditingController controller;
  final bool enabled;

  /// When true, dictated text is appended to existing text; when false it
  /// replaces the field contents.
  final bool append;
  final ValueChanged<bool>? onListeningChanged;

  @override
  State<VoiceMicButton> createState() => _VoiceMicButtonState();
}

class _VoiceMicButtonState extends State<VoiceMicButton> {
  final VoiceTypingService _service = VoiceTypingService();
  bool _listening = false;
  String _textBeforeSession = '';

  Future<void> _pickLanguageAndListen() async {
    if (_listening) {
      await _service.stop();
      _setListening(false);
      return;
    }

    final language = await showDialog<VoiceLanguage>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Voice typing language',
          style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: VoiceLanguage.values
              .map(
                (lang) => ListTile(
                  dense: true,
                  leading: const Icon(Icons.mic_none_rounded, size: 20),
                  title: Text(
                    lang.label,
                    style: GoogleFonts.poppins(fontSize: 14),
                  ),
                  onTap: () => Navigator.of(context).pop(lang),
                ),
              )
              .toList(),
        ),
      ),
    );
    if (language == null || !mounted) return;

    final started = await _service.listen(
      language: language,
      onResult: (result) {
        if (!mounted) return;
        final dictated = result.text.trim();
        final base = _textBeforeSession;
        final next = widget.append && base.isNotEmpty
            ? (dictated.isEmpty ? base : '$base $dictated')
            : dictated;
        widget.controller.text = next;
        widget.controller.selection = TextSelection.collapsed(
          offset: next.length,
        );
      },
      onDone: () => _setListening(false),
    );

    if (!started) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Voice typing is not available on this device. '
            'Check microphone permission and internet.',
          ),
        ),
      );
      return;
    }

    _textBeforeSession = widget.controller.text.trim();
    _setListening(true);
  }

  void _setListening(bool value) {
    if (!mounted || _listening == value) return;
    setState(() => _listening = value);
    widget.onListeningChanged?.call(value);
  }

  @override
  void dispose() {
    if (_listening) {
      _service.stop();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = _listening;
    return Tooltip(
      message: active ? 'Listening… tap to stop' : 'Voice typing (EN/বাংলা)',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: widget.enabled ? _pickLanguageAndListen : null,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(
              active ? Icons.mic_rounded : Icons.mic_none_rounded,
              size: 20,
              color: !widget.enabled
                  ? AppColors.textHint
                  : active
                      ? AppColors.error
                      : AppColors.primary,
            ),
          ),
        ),
      ),
    );
  }
}

/// `TextFormField` with a built-in English/Bangla voice-typing mic.
///
/// For numeric-only keyboards ([TextInputType.number]) leave [voiceEnabled]
/// false — dictation is meant for free text.
class VoiceTextField extends StatelessWidget {
  const VoiceTextField({
    super.key,
    required this.controller,
    this.label,
    this.hintText,
    this.prefixIcon,
    this.suffixIcon,
    this.keyboardType,
    this.maxLines = 1,
    this.minLines,
    this.enabled = true,
    this.validator,
    this.onChanged,
    this.textCapitalization = TextCapitalization.sentences,
    this.voiceEnabled = true,
    this.style,
    this.decoration,
  });

  final TextEditingController controller;
  final String? label;
  final String? hintText;
  final IconData? prefixIcon;
  final Widget? suffixIcon;
  final TextInputType? keyboardType;
  final int? maxLines;
  final int? minLines;
  final bool enabled;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final TextCapitalization textCapitalization;
  final bool voiceEnabled;
  final TextStyle? style;
  final InputDecoration? decoration;

  @override
  Widget build(BuildContext context) {
    final mic = voiceEnabled
        ? VoiceMicButton(controller: controller, enabled: enabled)
        : null;
    final combinedSuffix = mic == null
        ? suffixIcon
        : suffixIcon == null
            ? mic
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [mic, suffixIcon!],
              );

    final baseDecoration = decoration ??
        InputDecoration(
          labelText: label,
          hintText: hintText,
          labelStyle: GoogleFonts.poppins(fontSize: 13),
          prefixIcon: prefixIcon == null ? null : Icon(prefixIcon, size: 20),
          filled: true,
          fillColor: AppColors.background,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        );

    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      minLines: minLines,
      enabled: enabled,
      validator: validator,
      onChanged: onChanged,
      textCapitalization: textCapitalization,
      style: style ?? GoogleFonts.poppins(fontSize: 14),
      decoration: baseDecoration.copyWith(suffixIcon: combinedSuffix),
    );
  }
}
