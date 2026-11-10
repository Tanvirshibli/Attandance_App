import '../models/zone_scope.dart';

/// The filter axes a marketing list can offer. Each screen passes only the ones
/// that make sense for its rows, so a party list never shows a visit-date pill.
enum MarketingFilterDimension { status, type, date, area }

/// The quick date choices plus the custom range.
enum MarketingDatePreset { all, today, week, month, custom }

/// A date filter: a preset, or an explicit inclusive range for [custom].
///
/// Marketing dates arrive as unparsed API strings, so every comparison goes
/// through [marketingParseDate] instead of reading the raw text.
class MarketingDateRange {
  const MarketingDateRange({
    this.preset = MarketingDatePreset.all,
    this.from,
    this.to,
  });

  static const MarketingDateRange all = MarketingDateRange();

  final MarketingDatePreset preset;
  final DateTime? from;
  final DateTime? to;

  bool get isActive => preset != MarketingDatePreset.all;

  String get label {
    switch (preset) {
      case MarketingDatePreset.all:
        return 'All dates';
      case MarketingDatePreset.today:
        return 'Today';
      case MarketingDatePreset.week:
        return 'This week';
      case MarketingDatePreset.month:
        return 'This month';
      case MarketingDatePreset.custom:
        if (from == null || to == null) return 'Custom';
        return '${_short(from!)} – ${_short(to!)}';
    }
  }

  /// The preset labels the sheet offers, in order.
  static const List<String> presetLabels = [
    'All',
    'Today',
    'This week',
    'This month',
    'Custom',
  ];

  /// Builds a range from a [presetLabels] entry.
  static MarketingDateRange fromLabel(
    String label, {
    DateTime? from,
    DateTime? to,
  }) {
    switch (label) {
      case 'Today':
        return MarketingDateRange(preset: MarketingDatePreset.today);
      case 'This week':
        return MarketingDateRange(preset: MarketingDatePreset.week);
      case 'This month':
        return MarketingDateRange(preset: MarketingDatePreset.month);
      case 'Custom':
        return MarketingDateRange(
          preset: MarketingDatePreset.custom,
          from: from,
          to: to,
        );
      default:
        return MarketingDateRange.all;
    }
  }

  /// True when [value]'s calendar day falls inside this range.
  ///
  /// [now] is injectable so the presets can be pinned in tests.
  bool contains(DateTime value, {DateTime? now}) {
    final current = now ?? DateTime.now();
    final day = DateTime(value.year, value.month, value.day);

    switch (preset) {
      case MarketingDatePreset.all:
        return true;
      case MarketingDatePreset.today:
        return day == DateTime(current.year, current.month, current.day);
      case MarketingDatePreset.week:
        final startOfWeek = DateTime(
          current.year,
          current.month,
          current.day,
        ).subtract(Duration(days: current.weekday - 1));
        final endOfWeek = startOfWeek.add(const Duration(days: 6));
        return !day.isBefore(startOfWeek) && !day.isAfter(endOfWeek);
      case MarketingDatePreset.month:
        return day.year == current.year && day.month == current.month;
      case MarketingDatePreset.custom:
        if (from == null || to == null) return true;
        final start = DateTime(from!.year, from!.month, from!.day);
        final end = DateTime(to!.year, to!.month, to!.day);
        return !day.isBefore(start) && !day.isAfter(end);
    }
  }

  MarketingDateRange copyWith({
    MarketingDatePreset? preset,
    DateTime? from,
    DateTime? to,
  }) {
    return MarketingDateRange(
      preset: preset ?? this.preset,
      from: from ?? this.from,
      to: to ?? this.to,
    );
  }

  static String _short(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${date.day} ${months[date.month - 1]}';
  }

  @override
  bool operator ==(Object other) =>
      other is MarketingDateRange &&
      other.preset == preset &&
      other.from == from &&
      other.to == to;

  @override
  int get hashCode => Object.hash(preset, from, to);
}

/// The filter state shared by every marketing list screen.
///
/// `All` (and [MarketingDateRange.all]) means "do not narrow on this axis", so a
/// fresh instance never hides a row.
class MarketingFilters {
  const MarketingFilters({
    this.status = 'All',
    this.type = 'All',
    this.date = MarketingDateRange.all,
    this.area = 'All',
  });

  final String status;
  final String type;
  final MarketingDateRange date;
  final String area;

  bool get isActive => activeCount > 0;

  int get activeCount {
    var count = 0;
    if (status != 'All') count++;
    if (type != 'All') count++;
    if (date.isActive) count++;
    if (area != 'All') count++;
    return count;
  }

  String valueFor(MarketingFilterDimension dimension) {
    switch (dimension) {
      case MarketingFilterDimension.status:
        return status;
      case MarketingFilterDimension.type:
        return type;
      case MarketingFilterDimension.date:
        return date.isActive ? date.label : 'All';
      case MarketingFilterDimension.area:
        return area;
    }
  }

  bool isDimensionActive(MarketingFilterDimension dimension) {
    switch (dimension) {
      case MarketingFilterDimension.status:
        return status != 'All';
      case MarketingFilterDimension.type:
        return type != 'All';
      case MarketingFilterDimension.date:
        return date.isActive;
      case MarketingFilterDimension.area:
        return area != 'All';
    }
  }

  MarketingFilters copyWith({
    String? status,
    String? type,
    MarketingDateRange? date,
    String? area,
  }) {
    return MarketingFilters(
      status: status ?? this.status,
      type: type ?? this.type,
      date: date ?? this.date,
      area: area ?? this.area,
    );
  }

  /// One dimension changed, matching the bar's per-pill editing.
  MarketingFilters withValue(MarketingFilterDimension dimension, String value) {
    switch (dimension) {
      case MarketingFilterDimension.status:
        return copyWith(status: value);
      case MarketingFilterDimension.type:
        return copyWith(type: value);
      case MarketingFilterDimension.area:
        return copyWith(area: value);
      case MarketingFilterDimension.date:
        return copyWith(date: MarketingDateRange.fromLabel(value));
    }
  }

  MarketingFilters resetDimension(MarketingFilterDimension dimension) {
    switch (dimension) {
      case MarketingFilterDimension.status:
        return copyWith(status: 'All');
      case MarketingFilterDimension.type:
        return copyWith(type: 'All');
      case MarketingFilterDimension.date:
        return copyWith(date: MarketingDateRange.all);
      case MarketingFilterDimension.area:
        return copyWith(area: 'All');
    }
  }

  /// Everything back to permissive.
  MarketingFilters get cleared => const MarketingFilters();

  @override
  bool operator ==(Object other) =>
      other is MarketingFilters &&
      other.status == status &&
      other.type == type &&
      other.date == date &&
      other.area == area;

  @override
  int get hashCode => Object.hash(status, type, date, area);
}

/// Parses an API date string, tolerating `yyyy-MM-dd` and ISO datetimes.
///
/// Returns null for blank, `'null'` and unparseable values: a row with no date
/// is only dropped when a date filter is actually active.
DateTime? marketingParseDate(String? raw) {
  final text = raw?.trim() ?? '';
  if (text.isEmpty || text.toLowerCase() == 'null') return null;
  return DateTime.tryParse(text);
}

/// Status comparison shared by every entity. `All` is permissive; a blank
/// entity value never satisfies an active filter.
///
/// `done` and `completed` are the same terminal state on follow-ups — the app
/// writes `completed` while older rows carry `done`, and a filter must match
/// both or the list silently reads as empty.
bool marketingStatusMatches(String? status, String filter) {
  if (filter == 'All') return true;
  final value = _normaliseStatus(status);
  if (value.isEmpty) return false;
  return value == _normaliseStatus(filter);
}

String _normaliseStatus(String? status) {
  final value = (status ?? '').trim().toLowerCase().replaceAll('_', ' ');
  if (value == 'done') return 'completed';
  return value;
}

/// Type comparison for single-valued fields (party type, visit type, market
/// product type). Multi-valued fields use [marketingTypeListMatches].
bool marketingTypeMatches(String? type, String filter) {
  if (filter == 'All') return true;
  final value = (type ?? '').trim().toLowerCase();
  if (value.isEmpty) return false;
  return value == filter.trim().toLowerCase();
}

/// Type comparison for fields carrying several values, such as a market's
/// product types.
bool marketingTypeListMatches(List<String> types, String filter) {
  if (filter == 'All') return true;
  final wanted = filter.trim().toLowerCase();
  if (wanted.isEmpty) return true;
  return types.any((type) => type.trim().toLowerCase() == wanted);
}

/// Date comparison for an opaque API date string.
bool marketingDateMatches(
  String? raw,
  MarketingDateRange range, {
  DateTime? now,
}) {
  if (!range.isActive) return true;
  final parsed = marketingParseDate(raw);
  if (parsed == null) return false;
  return range.contains(parsed, now: now);
}

/// Area comparison: the selected zone name or district, against what the row
/// carries. `All` is permissive.
///
/// The option list is built from the employee's [ZoneScope], so a screen with no
/// scope never offers this dimension.
bool marketingAreaMatches({
  int? zoneId,
  String? zoneName,
  String? district,
  required String area,
}) {
  if (area == 'All') return true;
  final wanted = area.trim().toLowerCase();
  if (wanted.isEmpty) return true;
  if (zoneId != null && zoneId <= 0) zoneId = null;
  return (zoneName ?? '').trim().toLowerCase() == wanted ||
      (district ?? '').trim().toLowerCase() == wanted;
}

/// Area options for the bar: the zones the employee is assigned to, in their
/// original casing. `All` is always first.
List<String> marketingAreaOptions(ZoneScope? scope) {
  if (scope == null || scope.isEmpty) return const ['All'];
  return ['All', ...scope.displayNames];
}

/// Choices taken from the rows themselves, for an axis whose values the server
/// does not fix (party types inside a pool, market product types, visit types).
///
/// Blanks and duplicates drop out, `All` leads, and the rest sort
/// case-insensitively so the order never shuffles between loads.
List<String> marketingDerivedOptions(Iterable<String?> values) {
  final unique = <String>{};
  for (final value in values) {
    final text = (value ?? '').trim();
    if (text.isNotEmpty) unique.add(text);
  }
  final sorted = unique.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return ['All', ...sorted];
}

