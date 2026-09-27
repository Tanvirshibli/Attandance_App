import 'package:employee_attendance/models/payment_setup_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const alpha = SetupCompany(id: 1, nameEn: 'Alpha Feeds');
  const beta = SetupCompany(id: 2, nameEn: 'Beta Agro');

  SetupBank bankOf(int id, SetupCompany? company) =>
      SetupBank(id: id, bankName: 'Bank $id', company: company);

  PaymentSetupData setupOf(List<SetupBank> banks) => PaymentSetupData(
        banks: banks,
        employees: const [],
        paymentTypes: const [],
      );

  group('banksForCompany', () {
    test('returns only banks belonging to the selected company', () {
      final setup = setupOf([
        bankOf(10, alpha),
        bankOf(11, alpha),
        bankOf(20, beta),
      ]);

      final scoped = setup.banksForCompany(alpha.id);

      expect(scoped.map((b) => b.id), <int>[10, 11]);
      expect(scoped.every((b) => b.company?.id == alpha.id), isTrue);
    });

    // The stale-selection bug: a company-A bank could previously be submitted
    // alongside a displayed company B because the list was never filtered.
    test('excludes a bank belonging to a different company', () {
      final setup = setupOf([
        bankOf(10, alpha),
        bankOf(20, beta),
      ]);

      expect(setup.banksForCompany(alpha.id).map((b) => b.id), <int>[10]);
      expect(setup.banksForCompany(beta.id).map((b) => b.id), <int>[20]);
    });

    test('returns every bank when no company is selected yet', () {
      final banks = [bankOf(10, alpha), bankOf(20, beta)];
      final setup = setupOf(banks);

      expect(setup.banksForCompany(null).map((b) => b.id), <int>[10, 20]);
      expect(setup.banksForCompany(0).map((b) => b.id), <int>[10, 20]);
    });

    test('returns empty when the company owns no bank but others do', () {
      final setup = setupOf([bankOf(10, alpha), bankOf(20, beta)]);

      expect(setup.banksForCompany(99), isEmpty);
    });

    test('falls back to all banks when no bank carries a company', () {
      final setup = setupOf([
        const SetupBank(id: 10, bankName: 'Bank 10'),
        const SetupBank(id: 20, bankName: 'Bank 20'),
      ]);

      expect(setup.banksForCompany(alpha.id).map((b) => b.id), <int>[10, 20]);
    });

    test('is empty for an empty setup', () {
      expect(setupOf(const []).banksForCompany(alpha.id), isEmpty);
      expect(setupOf(const []).banksForCompany(null), isEmpty);
    });
  });

  group('uniqueCompanies', () {
    test('derives companies from the bank list', () {
      final setup = setupOf([bankOf(10, alpha), bankOf(20, beta)]);

      expect(
        setup.uniqueCompanies.map((c) => c.id).toList()..sort(),
        <int>[1, 2],
      );
    });

    test('is empty when no bank carries a company', () {
      final setup = setupOf([const SetupBank(id: 10, bankName: 'Bank 10')]);

      expect(setup.uniqueCompanies, isEmpty);
    });
  });
}
