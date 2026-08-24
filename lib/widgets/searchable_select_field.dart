import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/theme.dart';

typedef SearchableItemFilter<T> = bool Function(T item, String query);

/// Type-to-search dropdown styled like other form fields in the app.
class SearchableSelectField<T extends Object> extends StatefulWidget {
  const SearchableSelectField({
    super.key,
    required this.label,
    required this.icon,
    required this.options,
    required this.displayString,
    required this.onSelected,
    this.selected,
    this.subtitleFor,
    this.searchText,
    this.filter,
    this.enabled = true,
    this.validator,
    this.hintText = 'Tap to pick or type…',
  });

  final String label;
  final IconData icon;
  final List<T> options;
  final T? selected;
  final String Function(T item) displayString;
  final String Function(T item)? searchText;
  final String? Function(T item)? subtitleFor;
  final SearchableItemFilter<T>? filter;
  final ValueChanged<T?> onSelected;
  final bool enabled;
  final String? Function(T? value)? validator;
  final String hintText;

  @override
  State<SearchableSelectField<T>> createState() =>
      _SearchableSelectFieldState<T>();
}

class _SearchableSelectFieldState<T extends Object>
    extends State<SearchableSelectField<T>> {
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

  bool _matches(T item, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    if (widget.filter != null) return widget.filter!(item, q);
    final text =
        widget.searchText?.call(item) ?? widget.displayString(item).toLowerCase();
    return text.contains(q);
  }

  Iterable<T> _filtered(String query) {
    if (widget.options.isEmpty) return const Iterable.empty();
    final q = query.trim();
    if (q.isEmpty && _fieldFocusNode?.hasFocus != true) {
      return const Iterable.empty();
    }
    return widget.options.where((o) => _matches(o, q)).take(80);
  }

  void _bumpController(TextEditingController c) {
    final text = c.text;
    c.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _toggleSuffix(FocusNode focusNode, TextEditingController controller) {
    if (focusNode.hasFocus) {
      focusNode.unfocus();
      return;
    }
    focusNode.requestFocus();
    _bumpController(controller);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return FormField<T>(
      validator: widget.validator,
      initialValue: widget.selected,
      builder: (field) {
        final current = field.value ?? widget.selected;
        final display =
            current != null ? widget.displayString(current) : '';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Autocomplete<T>(
              optionsBuilder: (textEditingValue) =>
                  _filtered(textEditingValue.text),
              displayStringForOption: widget.displayString,
              initialValue: TextEditingValue(text: display),
              fieldViewBuilder:
                  (context, controller, focusNode, onFieldSubmitted) {
                _bindFocusNode(focusNode);
                if (current != null && controller.text != display) {
                  controller.value = TextEditingValue(
                    text: display,
                    selection:
                        TextSelection.collapsed(offset: display.length),
                  );
                }
                final listOpen = focusNode.hasFocus;
                return TextFormField(
                  controller: controller,
                  focusNode: focusNode,
                  enabled: widget.enabled && widget.options.isNotEmpty,
                  onFieldSubmitted: (_) => onFieldSubmitted(),
                  onTap: () {
                    if (!focusNode.hasFocus) {
                      focusNode.requestFocus();
                    }
                    setState(() {});
                    _bumpController(controller);
                  },
                  onTapOutside: (_) => focusNode.unfocus(),
                  style: GoogleFonts.poppins(fontSize: 14),
                  decoration: InputDecoration(
                    labelText: widget.label,
                    hintText: widget.options.isEmpty
                        ? 'No options loaded'
                        : widget.hintText,
                    labelStyle: GoogleFonts.poppins(fontSize: 13),
                    prefixIcon: Icon(widget.icon, size: 20),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (current != null)
                          IconButton(
                            icon: const Icon(Icons.clear, size: 20),
                            onPressed: widget.enabled
                                ? () {
                                    controller.clear();
                                    field.didChange(null);
                                    widget.onSelected(null);
                                    focusNode.unfocus();
                                  }
                                : null,
                          ),
                        IconButton(
                          tooltip: 'Show options',
                          icon: Icon(
                            listOpen
                                ? Icons.arrow_drop_up
                                : Icons.arrow_drop_down,
                            size: 22,
                          ),
                          onPressed: !widget.enabled ||
                                  widget.options.isEmpty
                              ? null
                              : () => _toggleSuffix(focusNode, controller),
                        ),
                      ],
                    ),
                    filled: true,
                    fillColor: AppColors.background,
                    errorText: field.errorText,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                );
              },
              onSelected: (value) {
                field.didChange(value);
                widget.onSelected(value);
                _fieldFocusNode?.unfocus();
              },
              optionsViewBuilder: (context, onSelected, optionsList) {
                if (optionsList.isEmpty) return const SizedBox.shrink();
                return Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    elevation: 4,
                    borderRadius: BorderRadius.circular(12),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxHeight: 280,
                        minWidth: 280,
                      ),
                      child: ListView.builder(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        itemCount: optionsList.length,
                        itemBuilder: (context, index) {
                          final option = optionsList.elementAt(index);
                          final subtitle = widget.subtitleFor?.call(option);
                          return ListTile(
                            dense: true,
                            title: Text(
                              widget.displayString(option),
                              style: GoogleFonts.poppins(fontSize: 13),
                            ),
                            subtitle: subtitle != null && subtitle.isNotEmpty
                                ? Text(
                                    subtitle,
                                    style: GoogleFonts.poppins(
                                      fontSize: 11,
                                      color: AppColors.textSecondary,
                                    ),
                                  )
                                : null,
                            onTap: () => onSelected(option),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }
}
