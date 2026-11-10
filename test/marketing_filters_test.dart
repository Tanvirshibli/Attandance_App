import 'package:employee_attendance/utils/marketing_filters.dart';
import 'package:flutter_test/flutter_test.dart';

/// The marketing filter bar is only as good as its predicates: a wrong `All`
/// would hide rows on every screen at once, and a wrong date boundary would
/// silently drop today's visits. These pin the logic the six lists share.
void main() {
  group('MarketingDateRange presets', () {
    // A Wednesday, so the week preset has days on both sides of it.
    final now = DateTime(2026, 3, 11, 9, 30);

    test('All keeps every date, including one that will not parse', () {
      expect(MarketingDateRange.all.isActive, isFalse);
      expect(MarketingDateRange.all.contains(now), isTrue);
      expect(marketingDateMatches('2026-03-11', MarketingDateRange.all), isTrue);
      expect(marketingDateMatches(null, MarketingDateRange.all), isTrue);
      expect(marketingDateMatches('not-a-date', MarketingDateRange.all), isTrue);
    });

    test('Today matches the calendar day only', () {
      const range = MarketingDateRange(preset: MarketingDatePreset.today);
      expect(range.contains(now, now: now), isTrue);
      expect(range.contains(DateTime(2026, 3, 11, 23, 59), now: now), isTrue);
      expect(range.contains(DateTime(2026, 3, 12), now: now), isFalse);
      expect(range.contains(DateTime(2026, 3, 10), now: now), isFalse);
    });

    test('This week spans Monday to Sunday around now', () {
      const range = MarketingDateRange(preset: MarketingDatePreset.week);
      expect(range.contains(DateTime(2026, 3, 9), now: now), isTrue); // Monday
      expect(range.contains(DateTime(2026, 3, 15), now: now), isTrue); // Sunday
      expect(range.contains(DateTime(2026, 3, 8), now: now), isFalse); // Sun before
      expect(range.contains(DateTime(2026, 3, 16), now: now), isFalse); // Mon after
    });

    test('This month stays inside the month of now', () {
      const range = MarketingDateRange(preset: MarketingDatePreset.month);
      expect(range.contains(DateTime(2026, 3, 1), now: now), isTrue);
      expect(range.contains(DateTime(2026, 3, 31), now: now), isTrue);
      expect(range.contains(DateTime(2026, 2, 28), now: now), isFalse);
      expect(range.contains(DateTime(2026, 4, 1), now: now), isFalse);
    });

    test('Custom is inclusive on both ends', () {
      final range = MarketingDateRange(
        preset: MarketingDatePreset.custom,
        from: DateTime(2026, 3, 2),
        to: DateTime(2026, 3, 6),
      );
      expect(range.contains(DateTime(2026, 3, 2), now: now), isTrue);
      expect(range.contains(DateTime(2026, 3, 6), now: now), isTrue);
      expect(range.contains(DateTime(2026, 3, 7), now: now), isFalse);
      expect(range.contains(DateTime(2026, 3, 1), now: now), isFalse);
    });

    test('a custom range with no bounds yet matches everything', () {
      const range = MarketingDateRange(preset: MarketingDatePreset.custom);
      expect(range.isActive, isTrue);
      expect(range.contains(DateTime(1999, 1, 1)), isTrue);
      expect(range.label, 'Custom');
    });

    test('labels name the range', () {
      expect(
        MarketingDateRange(
          preset: MarketingDatePreset.custom,
          from: DateTime(2026, 3, 2),
          to: DateTime(2026, 3, 6),
        ).label,
        '2 Mar – 6 Mar',
      );
      expect(MarketingDateRange.fromLabel('Today').preset,
          MarketingDatePreset.today);
      expect(MarketingDateRange.fromLabel('Custom').preset,
          MarketingDatePreset.custom);
      expect(MarketingDateRange.fromLabel('All').isActive, isFalse);
    });
  });

  group('marketingParseDate', () {
    test('accepts date-only and ISO datetime strings', () {
      expect(marketingParseDate('2026-03-11'), DateTime(2026, 3, 11));
      expect(
        marketingParseDate('2026-03-11T08:15:00'),
        DateTime(2026, 3, 11, 8, 15),
      );
      expect(
        marketingParseDate('2026-03-11 08:15:00'),
        DateTime(2026, 3, 11, 8, 15),
      );
    });

    test('returns null for blank, literal null and garbage', () {
      expect(marketingParseDate(null), isNull);
      expect(marketingParseDate(''), isNull);
      expect(marketingParseDate('  '), isNull);
      expect(marketingParseDate('null'), isNull);
      expect(marketingParseDate('not-a-date'), isNull);
    });

    test('a row without a date drops out only when a date filter is active', () {
      expect(marketingDateMatches(null, MarketingDateRange.all), isTrue);
      expect(
        marketingDateMatches(
          null,
          const MarketingDateRange(preset: MarketingDatePreset.today),
        ),
        isFalse,
      );
    });
  });

  group('status and type matching', () {
    test('All is permissive, a blank value is not', () {
      expect(marketingStatusMatches(null, 'All'), isTrue);
      expect(marketingTypeMatches(null, 'All'), isTrue);
      expect(marketingStatusMatches(null, 'active'), isFalse);
      expect(marketingStatusMatches('', 'active'), isFalse);
      expect(marketingTypeMatches('', 'farm'), isFalse);
    });

    test('matching is case-insensitive and ignores underscores', () {
      expect(marketingStatusMatches('in_progress', 'in_progress'), isTrue);
      expect(marketingStatusMatches('IN_PROGRESS', 'in_progress'), isTrue);
      expect(marketingTypeMatches('Farm', 'farm'), isTrue);
      expect(marketingTypeMatches('dealer', 'farm'), isFalse);
    });

    test('done and completed are the same terminal follow-up state', () {
      expect(marketingStatusMatches('done', 'completed'), isTrue);
      expect(marketingStatusMatches('completed', 'done'), isTrue);
      expect(marketingStatusMatches('open', 'completed'), isFalse);
    });

    test('multi-valued types match when any entry matches', () {
      expect(marketingTypeListMatches(['Feed', 'Chicks'], 'chicks'), isTrue);
      expect(marketingTypeListMatches(['Feed', 'Chicks'], 'broiler'), isFalse);
      expect(marketingTypeListMatches(const [], 'feed'), isFalse);
      expect(marketingTypeListMatches(const [], 'All'), isTrue);
    });
  });

  group('area matching', () {
    test('All is permissive and matches any row', () {
      expect(marketingAreaMatches(area: 'All'), isTrue);
      expect(
        marketingAreaMatches(zoneName: 'Zone A', district: 'Gazipur', area: 'All'),
        isTrue,
      );
    });

    test('matches a zone name or a district, case-insensitively', () {
      expect(
        marketingAreaMatches(zoneName: 'Zone A', area: 'zone a'),
        isTrue,
      );
      expect(
        marketingAreaMatches(district: 'Gazipur', area: 'GAZIPUR'),
        isTrue,
      );
      expect(
        marketingAreaMatches(zoneName: 'Zone B', district: 'Tangail', area: 'Zone A'),
        isFalse,
      );
    });

    test('no options beyond All when the employee has no scope', () {
      expect(marketingAreaOptions(null), ['All']);
    });
  });

  group('MarketingFilters', () {
    test('a fresh instance is inactive and permissive', () {
      const filters = MarketingFilters();
      expect(filters.isActive, isFalse);
      expect(filters.activeCount, 0);
      expect(filters.cleared, filters);
    });

    test('counts every active dimension', () {
      final filters = MarketingFilters(
        status: 'active',
        date: const MarketingDateRange(preset: MarketingDatePreset.week),
      );
      expect(filters.activeCount, 2);
      expect(filters.isActive, isTrue);
      expect(filters.isDimensionActive(MarketingFilterDimension.date), isTrue);
      expect(filters.isDimensionActive(MarketingFilterDimension.type), isFalse);
      expect(filters.valueFor(MarketingFilterDimension.date), 'This week');
      expect(filters.valueFor(MarketingFilterDimension.status), 'active');
    });

    test('withValue and resetDimension touch one axis at a time', () {
      var filters = const MarketingFilters();
      filters = filters.withValue(MarketingFilterDimension.status, 'inactive');
      filters = filters.withValue(MarketingFilterDimension.area, 'Zone A');
      expect(filters.status, 'inactive');
      expect(filters.area, 'Zone A');

      filters = filters.resetDimension(MarketingFilterDimension.status);
      expect(filters.status, 'All');
      expect(filters.area, 'Zone A');
      expect(filters.activeCount, 1);
    });

    test('withValue on date maps the preset label back to a preset', () {
      final filters =
          const MarketingFilters().withValue(MarketingFilterDimension.date, 'This month');
      expect(filters.date.preset, MarketingDatePreset.month);
      expect(filters.date.isActive, isTrue);
    });

    test('cleared drops every axis', () {
      final filters = MarketingFilters(
        status: 'active',
        type: 'farm',
        area: 'Zone A',
        date: const MarketingDateRange(preset: MarketingDatePreset.today),
      );
      expect(filters.activeCount, 4);
      expect(filters.cleared.activeCount, 0);
    });
  });
}
