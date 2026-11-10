import 'package:flutter/material.dart';

import '../config/app_design.dart';
import '../utils/marketing_filters.dart';
import 'filter_chip_row.dart';
import 'ui/app_button.dart';

/// The filter section shared by every marketing list.
///
/// One row of pills — one per dimension the screen offers — instead of several
/// stacked chip rows, because the detail tabs have no vertical room for those.
/// Each pill carries its selected value and opens a bottom sheet for that
/// dimension; the active-filter count and a one-tap clear sit on the same row.
class MarketingFilterBar extends StatelessWidget {
  const MarketingFilterBar({
    super.key,
    required this.filters,
    required this.dimensions,
    required this.onChanged,
    this.options = const {},
  });

  final MarketingFilters filters;
  final List<MarketingFilterDimension> dimensions;

  /// Choices for the `status`, `type` and `area` dimensions. `date` takes its
  /// options from [MarketingDateRange.presetLabels].
  final Map<MarketingFilterDimension, List<String>> options;

  final ValueChanged<MarketingFilters> onChanged;

  static const Map<MarketingFilterDimension, String> _labels = {
    MarketingFilterDimension.status: 'Status',
    MarketingFilterDimension.type: 'Type',
    MarketingFilterDimension.date: 'Date',
    MarketingFilterDimension.area: 'Area',
  };

  static const Map<MarketingFilterDimension, IconData> _icons = {
    MarketingFilterDimension.status: Icons.do_not_disturb_on_outlined,
    MarketingFilterDimension.type: Icons.category_outlined,
    MarketingFilterDimension.date: Icons.event_outlined,
    MarketingFilterDimension.area: Icons.place_outlined,
  };

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _pill(
            context,
            icon: AppIcons.filter,
            label: 'Filters',
            active: filters.isActive,
            badge: filters.isActive ? filters.activeCount : null,
            onTap: () => _openSheet(context, null),
          ),
          for (final dimension in dimensions)
            _pill(
              context,
              icon: _icons[dimension]!,
              label: _labels[dimension]!,
              value: filters.isDimensionActive(dimension)
                  ? filters.valueFor(dimension)
                  : null,
              active: filters.isDimensionActive(dimension),
              onTap: () => _openSheet(context, dimension),
            ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: filters.isActive
                ? Padding(
                    key: const ValueKey('clear-all'),
                    padding: const EdgeInsets.only(right: AppSpace.xs),
                    child: _pill(
                      context,
                      icon: Icons.close_rounded,
                      label: 'Clear all',
                      active: false,
                      onTap: () => onChanged(filters.cleared),
                    ),
                  )
                : const SizedBox.shrink(key: ValueKey('clear-none')),
          ),
        ],
      ),
    );
  }

  Widget _pill(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
    String? value,
    int? badge,
  }) {
    final foreground = active ? Colors.white : AppColors.ink;
    return Padding(
      padding: const EdgeInsets.only(right: AppSpace.xs),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.sm,
              vertical: AppSpace.xs,
            ),
            decoration: BoxDecoration(
              color: active ? AppColors.primary : AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(color: active ? AppColors.primary : AppColors.line),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 15,
                  color: active ? Colors.white : AppColors.inkMuted,
                ),
                const SizedBox(width: 6),
                Text(
                  value == null ? label : '$label · $value',
                  style: AppType.meta.copyWith(color: foreground),
                ),
                if (badge != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    constraints: const BoxConstraints(minWidth: 16),
                    height: 16,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text(
                      '$badge',
                      style: AppType.micro.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openSheet(
    BuildContext context,
    MarketingFilterDimension? focus,
  ) async {
    final result = await showModalBottomSheet<MarketingFilters>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _MarketingFilterSheet(
        initial: filters,
        dimensions: dimensions,
        options: options,
        focus: focus,
      ),
    );
    if (result != null && result != filters) {
      onChanged(result);
    }
  }
}

class _MarketingFilterSheet extends StatefulWidget {
  const _MarketingFilterSheet({
    required this.initial,
    required this.dimensions,
    required this.options,
    this.focus,
  });

  final MarketingFilters initial;
  final List<MarketingFilterDimension> dimensions;
  final Map<MarketingFilterDimension, List<String>> options;

  /// When set, only this dimension is shown — the per-pill entry point.
  final MarketingFilterDimension? focus;

  @override
  State<_MarketingFilterSheet> createState() => _MarketingFilterSheetState();
}

class _MarketingFilterSheetState extends State<_MarketingFilterSheet> {
  late MarketingFilters _working = widget.initial;

  List<MarketingFilterDimension> get _visible =>
      widget.focus == null ? widget.dimensions : [widget.focus!];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.xxl),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        AppSpace.gutter,
        AppSpace.xs,
        AppSpace.gutter,
        AppSpace.md + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: AppSpace.md),
                  decoration: BoxDecoration(
                    color: AppColors.line,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.focus == null
                          ? 'Filters'
                          : MarketingFilterBar._labels[widget.focus]!,
                      style: AppType.h3,
                    ),
                  ),
                  if (_working.isActive)
                    TextButton(
                      onPressed: () =>
                          setState(() => _working = _working.cleared),
                      child: Text(
                        'Reset',
                        style: AppType.meta.copyWith(color: AppColors.primary),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSpace.sm),
              for (final dimension in _visible) ...[
                _section(dimension),
                const SizedBox(height: AppSpace.md),
              ],
              AppButton(
                label: 'Apply',
                onPressed: () => Navigator.of(context).pop(_working),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(MarketingFilterDimension dimension) {
    if (dimension == MarketingFilterDimension.date) {
      return _dateSection();
    }

    final choices = widget.options[dimension] ?? const ['All'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          MarketingFilterBar._labels[dimension]!,
          style: AppType.bodyStrong,
        ),
        const SizedBox(height: AppSpace.xs),
        FilterChipRow(
          options: choices,
          selected: _working.valueFor(dimension),
          onSelected: (value) =>
              setState(() => _working = _working.withValue(dimension, value)),
        ),
      ],
    );
  }

  Widget _dateSection() {
    final selected = _working.date.isActive ? _working.date.label : 'All';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Date', style: AppType.bodyStrong),
        const SizedBox(height: AppSpace.xs),
        FilterChipRow(
          options: MarketingDateRange.presetLabels,
          selected: MarketingDateRange.presetLabels.contains(selected)
              ? selected
              : 'Custom',
          onSelected: (value) => setState(() {
            _working = _working.copyWith(
              date: MarketingDateRange.fromLabel(value),
            );
          }),
        ),
        if (_working.date.preset == MarketingDatePreset.custom) ...[
          const SizedBox(height: AppSpace.sm),
          Row(
            children: [
              Expanded(
                child: _dateTile(
                  label: 'From',
                  value: _working.date.from,
                  onTap: () => _pickRange(context, true),
                ),
              ),
              const SizedBox(width: AppSpace.xs),
              Expanded(
                child: _dateTile(
                  label: 'To',
                  value: _working.date.to,
                  onTap: () => _pickRange(context, false),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _pickRange(BuildContext context, bool isFrom) async {
    final now = DateTime.now();
    final initial = (isFrom ? _working.date.from : _working.date.to) ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year + 2, 12, 31),
    );
    if (picked == null) return;
    setState(() {
      final current = _working.date;
      var from = isFrom ? picked : current.from;
      var to = isFrom ? current.to : picked;
      if (from != null && to != null && to.isBefore(from)) {
        final swap = from;
        from = to;
        to = swap;
      }
      _working = _working.copyWith(
        date: MarketingDateRange(
          preset: MarketingDatePreset.custom,
          from: from,
          to: to,
        ),
      );
    });
  }

  Widget _dateTile({
    required String label,
    required DateTime? value,
    required VoidCallback onTap,
  }) {
    final text = value == null
        ? 'Select'
        : '${value.day.toString().padLeft(2, '0')}/'
            '${value.month.toString().padLeft(2, '0')}/${value.year}';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.sm,
          vertical: AppSpace.xs + 2,
        ),
        decoration: BoxDecoration(
          color: AppColors.surfaceSunk,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppType.micro.copyWith(color: AppColors.inkMuted)),
            const SizedBox(height: 2),
            Text(text, style: AppType.bodyStrong),
          ],
        ),
      ),
    );
  }
}
