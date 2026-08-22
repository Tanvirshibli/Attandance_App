import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/theme.dart';

/// Free-text field with type-to-search suggestions (custom values allowed).
class SearchableTextField extends StatelessWidget {
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

  Iterable<String> _filtered(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return suggestions.take(80);
    return suggestions
        .where((s) => s.toLowerCase().contains(q))
        .take(80);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Autocomplete<String>(
          key: ValueKey('${label}_${suggestions.length}'),
          optionsBuilder: (value) => _filtered(value.text),
          displayStringForOption: (option) => option,
          fieldViewBuilder: (context, fieldController, focusNode, onFieldSubmitted) {
            if (fieldController.text != controller.text) {
              fieldController.text = controller.text;
            }
            return TextFormField(
              controller: fieldController,
              focusNode: focusNode,
              enabled: enabled,
              keyboardType: keyboardType,
              onFieldSubmitted: (_) => onFieldSubmitted(),
              onChanged: (v) {
                if (controller.text != v) controller.text = v;
              },
              style: GoogleFonts.poppins(fontSize: 14),
              decoration: InputDecoration(
                labelText: label,
                hintText: hintText,
                labelStyle: GoogleFonts.poppins(fontSize: 13),
                prefixIcon: Icon(icon, size: 20),
                suffixIcon: suggestions.isNotEmpty
                    ? const Icon(Icons.arrow_drop_down, size: 22)
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
          onSelected: (value) => controller.text = value,
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
