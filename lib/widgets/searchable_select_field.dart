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
  final FocusNode _focusNode = FocusNode();
  final LayerLink _layerLink = LayerLink();
  final TextEditingController _controller = TextEditingController();
  final GlobalKey _fieldKey = GlobalKey();
  OverlayEntry? _overlay;
  bool _userEditing = false;
  FormFieldState<T>? _formField;

  @override
  void initState() {
    super.initState();
    _syncDisplay(widget.selected);
    _focusNode.addListener(_onFocusChange);
    _controller.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(SearchableSelectField<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_userEditing && widget.selected != oldWidget.selected) {
      _syncDisplay(widget.selected);
    }
  }

  @override
  void dispose() {
    _hideOverlay();
    _focusNode.removeListener(_onFocusChange);
    _controller.removeListener(_onTextChanged);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _syncDisplay(T? value) {
    final text = value != null ? widget.displayString(value) : '';
    if (_controller.text != text) {
      _controller.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus) {
      _userEditing = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _focusNode.hasFocus) _showOverlay();
      });
    } else {
      _userEditing = false;
      _syncDisplay(widget.selected);
      _hideOverlay();
    }
    if (mounted) setState(() {});
  }

  void _onTextChanged() {
    if (!_focusNode.hasFocus) return;
    final selectedLabel =
        widget.selected != null ? widget.displayString(widget.selected as T) : '';
    if (_controller.text != selectedLabel) {
      _userEditing = true;
    }
    _showOverlay();
  }

  bool _matches(T item, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    if (widget.filter != null) return widget.filter!(item, q);
    final text =
        widget.searchText?.call(item) ?? widget.displayString(item).toLowerCase();
    return text.contains(q);
  }

  List<T> _filtered() {
    if (widget.options.isEmpty) return const [];
    final selectedLabel =
        widget.selected != null ? widget.displayString(widget.selected as T) : '';
    final q = _controller.text.trim();
    final filterQuery =
        (!_userEditing || q.isEmpty || q == selectedLabel) ? '' : q;
    return widget.options.where((o) => _matches(o, filterQuery)).take(80).toList();
  }

  double _fieldWidth() {
    final box = _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    return box?.size.width ?? 280;
  }

  void _showOverlay() {
    if (!widget.enabled || widget.options.isEmpty) {
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
            child: Material(
              elevation: 6,
              borderRadius: BorderRadius.circular(12),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
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
                            onTap: () {
                              _userEditing = false;
                              _syncDisplay(option);
                              _formField?.didChange(option);
                              widget.onSelected(option);
                              _focusNode.unfocus();
                            },
                          );
                        },
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
    if (!widget.enabled || widget.options.isEmpty) return;
    if (_focusNode.hasFocus) {
      _focusNode.unfocus();
    } else {
      _focusNode.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FormField<T>(
      validator: widget.validator,
      initialValue: widget.selected,
      builder: (field) {
        _formField = field;
        final current = field.value ?? widget.selected;
        final listOpen = _focusNode.hasFocus;
        return CompositedTransformTarget(
          link: _layerLink,
          child: TextFormField(
            key: _fieldKey,
            controller: _controller,
            focusNode: _focusNode,
            enabled: widget.enabled && widget.options.isNotEmpty,
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
                              _userEditing = false;
                              _controller.clear();
                              field.didChange(null);
                              widget.onSelected(null);
                              _focusNode.unfocus();
                            }
                          : null,
                    ),
                  IconButton(
                    tooltip: 'Show options',
                    icon: Icon(
                      listOpen ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                      size: 22,
                    ),
                    onPressed: !widget.enabled || widget.options.isEmpty
                        ? null
                        : _toggleSuffix,
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
          ),
        );
      },
    );
  }
}
