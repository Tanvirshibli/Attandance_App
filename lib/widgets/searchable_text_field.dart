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
  FocusNode? _fieldFocusNode;

  @override
  void dispose() {
    _fieldFocusNode?.removeListener(_onFocusChange);
    super.dispose();
  }

  void _bindFocusNode(FocusNode node) {
    if (_fieldFocusNode == node) return;
    _fieldFocusNode?.removeListener(_onFocusChange);
    _fieldFocusNode = node;
    _fieldFocusNode!.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (mounted) setState(() {});
  }

  Iterable<String> _filtered(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) {
      if (_fieldFocusNode?.hasFocus != true) {
        return const Iterable<String>.empty();
      }
      return widget.suggestions.take(80);
    }
    return widget.suggestions
        .where((s) => s.toLowerCase().contains(q))
        .take(80);
  }

  void _bumpController(TextEditingController c) {
    final text = c.text;
    c.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _toggleSuffix(FocusNode focusNode, TextEditingController fieldController) {
    if (focusNode.hasFocus) {
      focusNode.unfocus();
      return;
    }
    focusNode.requestFocus();
    _bumpController(fieldController);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Autocomplete<String>(
          optionsBuilder: (value) => _filtered(value.text),
          displayStringForOption: (option) => option,
          fieldViewBuilder:
              (context, fieldController, focusNode, onFieldSubmitted) {
            _bindFocusNode(focusNode);
            if (fieldController.text != widget.controller.text) {
              fieldController.value = TextEditingValue(
                text: widget.controller.text,
                selection: TextSelection.collapsed(
                  offset: widget.controller.text.length,
                ),
              );
            }
            final listOpen = focusNode.hasFocus;
            return TextFormField(
              controller: fieldController,
              focusNode: focusNode,
              enabled: widget.enabled,
              keyboardType: widget.keyboardType,
              onFieldSubmitted: (_) => onFieldSubmitted(),
              onTap: () {
                if (!focusNode.hasFocus) {
                  focusNode.requestFocus();
                }
                setState(() {});
                _bumpController(fieldController);
              },
              onTapOutside: (_) => focusNode.unfocus(),
              onChanged: (v) {
                if (widget.controller.text != v) widget.controller.text = v;
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
                          listOpen
                              ? Icons.arrow_drop_up
                              : Icons.arrow_drop_down,
                          size: 22,
                        ),
                        onPressed: !widget.enabled
                            ? null
                            : () => _toggleSuffix(focusNode, fieldController),
                      )
                    : null,
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            );
          },
          onSelected: (value) {
            widget.controller.text = value;
            _fieldFocusNode?.unfocus();
          },
          optionsViewBuilder: (context, onSelected, options) {
            if (options.isEmpty) return const SizedBox.shrink();
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(12),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxHeight: 240,
                    minWidth: 280,
                  ),
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: options.length,
                    itemBuilder: (context, index) {
                      final option = options.elementAt(index);
                      return ListTile(
                        dense: true,
                        title: Text(
                          option,
                          style: GoogleFonts.poppins(fontSize: 13),
                        ),
                        onTap: () => onSelected(option),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}
