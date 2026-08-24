import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/theme.dart';

/// Free-text field with type-to-search suggestions (custom values allowed).
/// Options render inline under the field so selection and page scroll work.
class SearchableTextField extends StatefulWidget {
  const SearchableTextField({
    super.key,
    required this.label,
    required this.controller,
    this.suggestions = const [],
    this.hintText = 'Type or pick…',
    this.keyboardType = TextInputType.text,
    this.enabled = true,
    this.icon = Icons.edit_outlined,
  });

  final String label;
  final TextEditingController controller;
  final List<String> suggestions;
  final String hintText;
  final TextInputType keyboardType;
  final bool enabled;
  final IconData icon;

  @override
  State<SearchableTextField> createState() => _SearchableTextFieldState();
}

class _SearchableTextFieldState extends State<SearchableTextField> {
  final FocusNode _focusNode = FocusNode();
  final GlobalKey _rootKey = GlobalKey();
  bool _open = false;
  bool _pointerRouteActive = false;
  int? _outsidePointer;
  Offset? _outsideDownPos;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(SearchableTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onTextChanged);
      widget.controller.addListener(_onTextChanged);
    }
  }

  @override
  void dispose() {
    _detachPointerRoute();
    _focusNode.removeListener(_onFocusChange);
    widget.controller.removeListener(_onTextChanged);
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (mounted) setState(() {});
  }

  void _onTextChanged() {
    if (_open && mounted) setState(() {});
  }

  List<String> _filtered() {
    final q = widget.controller.text.trim().toLowerCase();
    if (q.isEmpty) return widget.suggestions.take(80).toList();
    return widget.suggestions
        .where((s) => s.toLowerCase().contains(q))
        .take(80)
        .toList();
  }

  void _setOpen(bool value) {
    if (_open == value) return;
    setState(() => _open = value);
    if (value) {
      _attachPointerRoute();
    } else {
      _detachPointerRoute();
    }
  }

  void _attachPointerRoute() {
    if (_pointerRouteActive) return;
    GestureBinding.instance.pointerRouter.addGlobalRoute(_handleGlobalPointer);
    _pointerRouteActive = true;
  }

  void _detachPointerRoute() {
    if (!_pointerRouteActive) return;
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_handleGlobalPointer);
    _pointerRouteActive = false;
    _outsidePointer = null;
    _outsideDownPos = null;
  }

  bool _isOutside(Offset globalPosition) {
    final box = _rootKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return true;
    final local = box.globalToLocal(globalPosition);
    return !(Offset.zero & box.size).contains(local);
  }

  void _handleGlobalPointer(PointerEvent event) {
    if (!_open) return;
    if (event is PointerDownEvent) {
      if (_isOutside(event.position)) {
        _outsidePointer = event.pointer;
        _outsideDownPos = event.position;
      } else {
        _outsidePointer = null;
        _outsideDownPos = null;
      }
      return;
    }
    if (_outsidePointer != event.pointer || _outsideDownPos == null) return;
    if (event is PointerMoveEvent) {
      if ((event.position - _outsideDownPos!).distance > kTouchSlop) {
        _outsidePointer = null;
        _outsideDownPos = null;
      }
      return;
    }
    if (event is PointerCancelEvent) {
      _outsidePointer = null;
      _outsideDownPos = null;
      return;
    }
    if (event is PointerUpEvent) {
      final moved = (event.position - _outsideDownPos!).distance;
      _outsidePointer = null;
      _outsideDownPos = null;
      if (moved <= kTouchSlop) {
        _setOpen(false);
        _focusNode.unfocus();
      }
    }
  }

  void _toggleSuffix() {
    if (!widget.enabled || widget.suggestions.isEmpty) return;
    if (_open) {
      _setOpen(false);
    } else {
      _setOpen(true);
      if (!_focusNode.hasFocus) _focusNode.requestFocus();
    }
  }

  Widget _optionsPanel(List<String> options) {
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 240),
        child: options.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'No matches',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              )
            : ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                primary: false,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final option = options[index];
                  return ListTile(
                    dense: true,
                    title: Text(
                      option,
                      style: GoogleFonts.poppins(fontSize: 13),
                    ),
                    onTap: () {
                      widget.controller.text = option;
                      _setOpen(false);
                      _focusNode.unfocus();
                    },
                  );
                },
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canOpen = widget.enabled && widget.suggestions.isNotEmpty;
    final showList = _open && canOpen;
    final options = showList ? _filtered() : const <String>[];

    return Column(
      key: _rootKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: widget.controller,
          focusNode: _focusNode,
          enabled: widget.enabled,
          keyboardType: widget.keyboardType,
          onTap: () {
            if (!canOpen) return;
            _setOpen(true);
            if (!_focusNode.hasFocus) _focusNode.requestFocus();
          },
          style: GoogleFonts.poppins(fontSize: 14),
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: widget.hintText,
            labelStyle: GoogleFonts.poppins(fontSize: 13),
            prefixIcon: Icon(widget.icon, size: 20),
            suffixIcon: widget.suggestions.isNotEmpty
                ? IconButton(
                    tooltip: 'Suggestions',
                    icon: Icon(
                      showList ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                      size: 22,
                    ),
                    onPressed: widget.enabled ? _toggleSuffix : null,
                  )
                : null,
            filled: true,
            fillColor: AppColors.background,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        if (showList) ...[
          const SizedBox(height: 6),
          _optionsPanel(options),
        ],
        const SizedBox(height: 12),
      ],
    );
  }
}
