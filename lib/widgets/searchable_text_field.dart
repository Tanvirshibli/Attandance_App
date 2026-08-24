import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/theme.dart';

/// Free-text field with type-to-search suggestions (custom values allowed).
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
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlay;
  final GlobalKey _fieldKey = GlobalKey();
  final Object _tapRegionGroupId = Object();

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
    _hideOverlay();
    _focusNode.removeListener(_onFocusChange);
    widget.controller.removeListener(_onTextChanged);
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _focusNode.hasFocus) _showOverlay();
      });
    } else {
      _hideOverlay();
    }
    if (mounted) setState(() {});
  }

  void _onTextChanged() {
    if (_focusNode.hasFocus) {
      _showOverlay();
    }
  }

  List<String> _filtered() {
    final q = widget.controller.text.trim().toLowerCase();
    if (q.isEmpty) return widget.suggestions.take(80).toList();
    return widget.suggestions
        .where((s) => s.toLowerCase().contains(q))
        .take(80)
        .toList();
  }

  double _fieldWidth() {
    final box = _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    return box?.size.width ?? 280;
  }

  void _showOverlay() {
    if (!widget.enabled || widget.suggestions.isEmpty) {
      _hideOverlay();
      return;
    }
    _overlay?.remove();
    final options = _filtered();
    _overlay = OverlayEntry(
      builder: (context) {
        return Positioned(
          width: _fieldWidth(),
          child: CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            offset: const Offset(0, 56),
            child: TextFieldTapRegion(
              groupId: _tapRegionGroupId,
              child: Material(
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
                                _hideOverlay();
                                _focusNode.unfocus();
                              },
                            );
                          },
                        ),
                ),
              ),
            ),
          ),
        );
      },
    );
    Overlay.of(context).insert(_overlay!);
  }

  void _hideOverlay() {
    _overlay?.remove();
    _overlay = null;
  }

  void _toggleSuffix() {
    if (!widget.enabled || widget.suggestions.isEmpty) return;
    if (_focusNode.hasFocus) {
      _focusNode.unfocus();
    } else {
      _focusNode.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final listOpen = _focusNode.hasFocus;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFieldTapRegion(
          groupId: _tapRegionGroupId,
          child: CompositedTransformTarget(
            link: _layerLink,
            child: TextFormField(
              key: _fieldKey,
              controller: widget.controller,
              focusNode: _focusNode,
              enabled: widget.enabled,
              keyboardType: widget.keyboardType,
              onTap: () {
                if (!_focusNode.hasFocus) {
                  _focusNode.requestFocus();
                } else {
                  _showOverlay();
                }
              },
              onTapOutside: (_) => _focusNode.unfocus(),
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
                          listOpen ? Icons.arrow_drop_up : Icons.arrow_drop_down,
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
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}
