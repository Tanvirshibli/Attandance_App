import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/theme.dart';

typedef SearchableItemFilter<T> = bool Function(T item, String query);

/// Type-to-search dropdown styled like other form fields in the app.
class SearchableSelectField<T extends Object> extends StatelessWidget {
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
    this.hintText = 'Type to search…',
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

  bool _matches(T item, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    if (filter != null) return filter!(item, q);
    final text = searchText?.call(item) ?? displayString(item).toLowerCase();
    return text.contains(q);
  }

  @override
  Widget build(BuildContext context) {
    return FormField<T>(
      validator: validator,
      initialValue: selected,
      builder: (field) {
        final current = field.value ?? selected;
        final display = current != null ? displayString(current) : '';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Autocomplete<T>(
              key: ValueKey('${label}_${options.length}_${current.hashCode}'),
              optionsBuilder: (textEditingValue) {
                final query = textEditingValue.text;
                if (options.isEmpty) return Iterable<T>.empty();
                final filtered = options.where((o) => _matches(o, query));
                return filtered.take(80);
              },
              displayStringForOption: displayString,
              initialValue: TextEditingValue(text: display),
              fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                if (current != null && controller.text != display) {
                  controller.text = display;
                }
                return TextFormField(
                  controller: controller,
                  focusNode: focusNode,
                  enabled: enabled && options.isNotEmpty,
                  onFieldSubmitted: (_) => onFieldSubmitted(),
                  style: GoogleFonts.poppins(fontSize: 14),
                  decoration: InputDecoration(
                    labelText: label,
                    hintText: options.isEmpty ? 'No options loaded' : hintText,
                    labelStyle: GoogleFonts.poppins(fontSize: 13),
                    prefixIcon: Icon(icon, size: 20),
                    suffixIcon: current != null
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 20),
                            onPressed: enabled
                                ? () {
                                    controller.clear();
                                    field.didChange(null);
                                    onSelected(null);
                                  }
                                : null,
                          )
                        : const Icon(Icons.search, size: 20),
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
                onSelected(value);
              },
              optionsViewBuilder: (context, onSelected, optionsList) {
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
                          final subtitle = subtitleFor?.call(option);
                          return ListTile(
                            dense: true,
                            title: Text(
                              displayString(option),
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
