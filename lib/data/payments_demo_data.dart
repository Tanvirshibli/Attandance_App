import '../models/payment_models.dart';
import '../models/payment_setup_models.dart';

class PaymentsDemoData {
  PaymentsDemoData._();

  static List<PayrollRecord> payslips() => const [
        PayrollRecord(
          id: 501,
          month: 'June 2026',
          netPay: 42500,
          netSalary: 43000,
          netReceivable: 42500,
          status: 'approved',
          grossPay: 52000,
          basics: 28000,
          houses: 12000,
          medicals: 3000,
          foods: 4000,
          sGross: 47000,
          mess: 1500,
          absentDays: 1,
          holidays: 2,
          leaves: 1,
          presentDays: 25,
          absenceDeduction: 1000,
          providentFund: 1400,
          punishment: 0,
          serviceBill: 200,
          tax: 500,
          loan: 3000,
          messDeposit: 500,
          others: 0,
          othersPayable: 0,
          adjustment: 0,
          paymentMethod: 'Bank',
          designation: 'Sales Officer',
          sectorName: 'Dhaka Sales',
        ),
        PayrollRecord(
          id: 500,
          month: 'May 2026',
          netPay: 43800,
          netSalary: 44000,
          netReceivable: 43800,
          status: 'approved',
          grossPay: 52000,
          basics: 28000,
          houses: 12000,
          medicals: 3000,
          foods: 4000,
          sGross: 47000,
          mess: 1500,
          absentDays: 0,
          holidays: 3,
          leaves: 0,
          presentDays: 26,
          absenceDeduction: 0,
          providentFund: 1400,
          punishment: 0,
          serviceBill: 200,
          tax: 500,
          loan: 3000,
          messDeposit: 500,
          paymentMethod: 'Bank',
          designation: 'Sales Officer',
          sectorName: 'Dhaka Sales',
        ),
        PayrollRecord(
          id: 499,
          month: 'April 2026',
          netPay: 41200,
          netSalary: 42000,
          netReceivable: 41200,
          status: 'approved',
          grossPay: 52000,
          basics: 28000,
          houses: 12000,
          medicals: 3000,
          foods: 4000,
          sGross: 47000,
          mess: 1500,
          absentDays: 2,
          holidays: 1,
          leaves: 0,
          presentDays: 24,
          absenceDeduction: 2000,
          providentFund: 1400,
          tax: 500,
          loan: 3000,
          messDeposit: 500,
          paymentMethod: 'Bank',
          designation: 'Sales Officer',
          sectorName: 'Dhaka Sales',
        ),
      ];

  static List<EmployeeLoan> loans() => const [
        EmployeeLoan(
          id: 12,
          loanCode: 'lon-012',
          amount: 50000,
          status: 'ongoing',
          loanType: 'Personal',
          paidAmount: 20000,
          remainingAmount: 30000,
          installmentAmount: 5000,
          installmentCount: 10,
          deadlineDate: '2026-12-31',
          loanAddDate: '2025-01-10',
          interestPercentage: 0,
          installmentType: 'Monthly Installment - Salary',
          note: 'Emergency loan',
        ),
        EmployeeLoan(
          id: 8,
          loanCode: 'lon-008',
          amount: 20000,
          status: 'approved',
          loanType: 'Festival',
          paidAmount: 5000,
          remainingAmount: 15000,
          installmentAmount: 2500,
          installmentCount: 8,
          deadlineDate: '2026-10-31',
          loanAddDate: '2026-02-01',
          interestPercentage: 0,
          installmentType: 'Monthly Installment - Salary',
        ),
      ];

  static List<LoanPayment> loanPayments() => const [
        LoanPayment(
          id: 301,
          amount: 5000,
          date: '2026-06-01',
          status: 'approved',
          loanId: 12,
          loanCode: 'lon-012',
          amountPaidSoFar: 20000,
          paymentMethod: 'Salary Deduction',
        ),
        LoanPayment(
          id: 298,
          amount: 5000,
          date: '2026-05-01',
          status: 'approved',
          loanId: 12,
          loanCode: 'lon-012',
          amountPaidSoFar: 15000,
          paymentMethod: 'Salary Deduction',
        ),
        LoanPayment(
          id: 290,
          amount: 2500,
          date: '2026-06-05',
          status: 'approved',
          loanId: 8,
          loanCode: 'lon-008',
          amountPaidSoFar: 5000,
          paymentMethod: 'Cash',
        ),
      ];

  static ProvidentFundRecord providentFund() => const ProvidentFundRecord(
        id: 77,
        month: '2026-06',
        openingBalance: 85000,
        monthlyPfAmount: 1400,
        pfAmountTotal: 92000,
        pfInterestTotal: 4200,
        closingBalance: 96200,
        closingBalanceWithProfit: 100400,
        status: 'approved',
        addDate: '2026-06-30',
      );

  static List<ProvidentFundRecord> providentFundHistory() => [
        providentFund(),
        const ProvidentFundRecord(
          id: 76,
          month: '2026-05',
          openingBalance: 83600,
          monthlyPfAmount: 1400,
          pfAmountTotal: 90600,
          pfInterestTotal: 4100,
          closingBalance: 94700,
          closingBalanceWithProfit: 98800,
          status: 'approved',
          addDate: '2026-05-31',
        ),
      ];

  static MessDepositRecord messDeposit() => const MessDepositRecord(
        id: 44,
        messDepositId: 'MD-044',
        dAmount: 500,
        totalDepAmount: 12500,
        tType: 'Deposit',
        tDate: '2026-06-15',
        note: 'Monthly mess contribution',
        status: 'approved',
        department: 'Sales & Marketing',
      );

  static CompensationFacility compensation() => const CompensationFacility(
        basics: 28000,
        houses: 12000,
        medicals: 3000,
        foods: 4000,
        sGross: 47000,
        mobileBill: 500,
        mess: 1500,
        quarter: 0,
        serviceBill: 200,
        loanF: 3000,
        tax: 500,
        paymentMethod: 'Bank',
        designationName: 'Sales Officer',
        departmentName: 'Sales & Marketing',
        sectorName: 'Dhaka Sales',
        jDate: '2021-03-15',
      );

  static PaymentsHubSummary summary() {
    final slips = payslips();
    final openLoans = loans();
    final remaining = openLoans.fold<double>(
      0,
      (sum, loan) => sum + (loan.remainingAmount ?? 0),
    );
    return PaymentsHubSummary(
      latestNetPay: slips.first.netReceivable ?? slips.first.netPay,
      latestPayslipMonth: slips.first.month,
      openLoanRemaining: remaining,
      pfClosingBalance: providentFund().closingBalanceWithProfit ??
          providentFund().closingBalance,
    );
  }

  static PaymentSetupData paymentSetup() => PaymentSetupData(
        banks: const [
          SetupBank(
            id: 65,
            bankName: 'Bkash -PPHL',
            shortName: 'Bkash-PPHL',
            company: SetupCompany(id: 3, nameEn: 'Peoples poultry'),
          ),
        ],
        employees: const [
          SetupEmployee(
            id: 235,
            employeeId: 110,
            employeeName: 'Demo Receiver (emp-110)',
            phoneNumber: '01700000000',
          ),
        ],
        paymentTypes: const [
          SetupPaymentType(id: 1, name: 'Feed'),
          SetupPaymentType(id: 5, name: 'Egg'),
        ],
      );
}
