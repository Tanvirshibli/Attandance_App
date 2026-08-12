import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../config/theme.dart';
import '../models/auth_wise_payment_post_models.dart';
import '../models/payment_setup_models.dart';
import '../services/auth_service.dart';
import '../services/payment_service.dart';
import '../widgets/gradient_screen_header.dart';
import '../widgets/searchable_select_field.dart';
import '../widgets/section_card.dart';

class PostAuthWisePaymentScreen extends StatefulWidget {
  const PostAuthWisePaymentScreen({super.key});

  @override
  State<PostAuthWisePaymentScreen> createState() =>
      _PostAuthWisePaymentScreenState();
}

class _PostAuthWisePaymentScreenState extends State<PostAuthWisePaymentScreen> {
  final PaymentService _paymentService = PaymentService();
  final AuthService _authService = AuthService();
  final _formKey = GlobalKey<FormState>();

  DateTime _recDate = DateTime.now();
  bool _isSubmitting = false;
  bool _loadingSetup = true;
  String? _setupError;
  PaymentSetupData? _setup;
  int? _employeeId;

  SetupEmployee? _receiver;
  SetupPaymentType? _paymentType;
  SetupBank? _bank;

  final _companyId = TextEditingController();
  final _recType = TextEditingController(text: '1');
  final _amount = TextEditingController();
  final _paymentFor = TextEditingController(text: '2');
  final _invoiceType = TextEditingController(text: '2');
  final _note = TextEditingController(text: 'Payment received from mobile app');
  final _trxId = TextEditingController();
  final _ref = TextEditingController(text: 'Mobile App');
  final _checkNo = TextEditingController();
  final _checkDate = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadSetup();
    _trxId.text = 'APP-TRX-${DateTime.now().millisecondsSinceEpoch % 100000}';
  }

  Future<void> _loadSetup() async {
    setState(() {
      _loadingSetup = true;
      _setupError = null;
    });
    final result = await _paymentService.fetchPaymentSetupData();
    if (!mounted) return;
    if (!result.success || result.data == null) {
      setState(() {
        _loadingSetup = false;
        _setupError = result.message ?? 'Could not load payment setup.';
      });
      return;
    }

    final setup = result.data!;
    final emptyLists = <String>[];
    if (setup.banks.isEmpty) emptyLists.add('banks');
    if (setup.employees.isEmpty) emptyLists.add('receivers');
    if (setup.paymentTypes.isEmpty) emptyLists.add('payment types');

    if (emptyLists.isNotEmpty) {
      setState(() {
        _loadingSetup = false;
        _setupError =
            'Payment setup returned no ${emptyLists.join(', ')}. Try again later or contact admin.';
      });
      return;
    }

    setState(() {
      _loadingSetup = false;
      _setup = setup;
    });
  }

  Future<void> _loadProfile() async {
    final profile = await _authService.getCurrentUserProfile();
    if (!mounted) return;
    setState(() => _employeeId = profile?.canonicalEmployeeId);
  }

  @override
  void dispose() {
    _companyId.dispose();
    _recType.dispose();
    _amount.dispose();
    _paymentFor.dispose();
    _invoiceType.dispose();
    _note.dispose();
    _trxId.dispose();
    _ref.dispose();
    _checkNo.dispose();
    _checkDate.dispose();
    super.dispose();
  }

  Future<void> _pickRecDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _recDate,
      firstDate: DateTime.now().subtract(const Duration(days: 90)),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (picked != null) setState(() => _recDate = picked);
  }

  int? _intField(TextEditingController c, String label) {
    final n = int.tryParse(c.text.trim());
    if (n == null) {
      _snack('Enter a valid $label.');
      return null;
    }
    return n;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final employeeId = _employeeId;
    if (employeeId == null || employeeId <= 0) {
      _snack('Please login again.');
      return;
    }

    if (_receiver == null) {
      _snack('Select a receiver.');
      return;
    }
    if (_paymentType == null) {
      _snack('Select a payment type.');
      return;
    }
    if (_bank == null) {
      _snack('Select a bank.');
      return;
    }

    final bankCompany = _bank!.company;
    if (bankCompany == null || bankCompany.id <= 0) {
      _snack('Selected bank has no company mapping. Choose another bank.');
      return;
    }

    final amount = double.tryParse(_amount.text.trim());
    if (amount == null || amount <= 0) {
      _snack('Enter a valid amount.');
      return;
    }

    final companyId = _intField(_companyId, 'company ID') ?? bankCompany.id;
    final recType = _intField(_recType, 'rec type');
    final paymentFor = _intField(_paymentFor, 'payment for');
    final invoiceType = _intField(_invoiceType, 'invoice type');

    if (recType == null ||
        paymentFor == null ||
        invoiceType == null) {
      return;
    }

    setState(() => _isSubmitting = true);

    final request = CreateAuthWisePaymentRequest(
      employeeId: employeeId,
      payments: [
        AuthWisePaymentLineInput(
          companyId: companyId,
          recType: recType,
          receiverId: _receiver!.id,
          amount: amount,
          recDate: DateFormat('yyyy-MM-dd').format(_recDate),
          paymentType: _paymentType!.id,
          paymentMode: _bank!.id,
          paymentFor: paymentFor,
          invoiceType: invoiceType,
          note: _note.text.trim(),
          trxId: _trxId.text.trim(),
          ref: _ref.text.trim(),
          checkNo: _checkNo.text.trim(),
          checkDate: _checkDate.text.trim(),
        ),
      ],
    );

    final result = await _paymentService.postAuthWisePayment(request);
    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (!result.success || result.data == null) {
      _snack(result.message ?? 'Could not submit payment.');
      return;
    }

    final created = result.data!;
    final vouchers = created.voucherNos.isNotEmpty
        ? created.voucherNos.join(', ')
        : '${created.createdPaymentCount} payment(s)';
    _snack('${created.message} Voucher: $vouchers');
    Navigator.of(context).pop(true);
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message, style: GoogleFonts.poppins())),
    );
  }

  void _onBankSelected(SetupBank? bank) {
    setState(() {
      _bank = bank;
      final company = bank?.company;
      if (company != null && company.id > 0) {
        _companyId.text = '${company.id}';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final setup = _setup;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          const SliverToBoxAdapter(
            child: GradientScreenHeader(
              title: 'Receive payment',
              subtitle: 'Auth-wise dealer payment (sales backend)',
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            sliver: SliverToBoxAdapter(
              child: FadeInUp(
                child: SectionCard(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_employeeId != null)
                          Text(
                            'Employee ID: $_employeeId',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        if (_loadingSetup) ...[
                          const SizedBox(height: 16),
                          const Center(child: CircularProgressIndicator()),
                          const SizedBox(height: 8),
                          Text(
                            'Loading banks, receivers, and payment types…',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ] else if (_setupError != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _setupError!,
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              color: AppColors.error,
                            ),
                          ),
                          TextButton(
                            onPressed: _loadSetup,
                            child: const Text('Retry'),
                          ),
                        ] else if (setup != null) ...[
                          const SizedBox(height: 12),
                          InkWell(
                            onTap: _pickRecDate,
                            borderRadius: BorderRadius.circular(12),
                            child: InputDecorator(
                              decoration: _dec(
                                'Receive date',
                                Icons.calendar_today_outlined,
                              ),
                              child: Text(
                                DateFormat('dd MMM yyyy').format(_recDate),
                                style: GoogleFonts.poppins(fontSize: 14),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          SearchableSelectField<SetupEmployee>(
                            label: 'Receiver',
                            icon: Icons.person_outline,
                            options: setup.employees,
                            selected: _receiver,
                            displayString: (e) => e.employeeName,
                            searchText: (e) => e.searchText,
                            subtitleFor: (e) =>
                                'ID ${e.id} · emp ${e.employeeId}',
                            onSelected: (v) => setState(() => _receiver = v),
                            validator: (v) =>
                                v == null ? 'Select a receiver' : null,
                          ),
                          const SizedBox(height: 12),
                          SearchableSelectField<SetupBank>(
                            label: 'Bank (payment mode)',
                            icon: Icons.account_balance_outlined,
                            options: setup.banks,
                            selected: _bank,
                            displayString: (b) => b.displayLabel,
                            searchText: (b) => b.searchText,
                            subtitleFor: (b) =>
                                b.company?.nameEn ?? 'ID ${b.id}',
                            onSelected: _onBankSelected,
                            validator: (v) =>
                                v == null ? 'Select a bank' : null,
                          ),
                          const SizedBox(height: 12),
                          _id(_companyId, 'Company ID'),
                          const SizedBox(height: 12),
                          _money(_amount, 'Amount (৳)'),
                          const SizedBox(height: 12),
                          SearchableSelectField<SetupPaymentType>(
                            label: 'Payment type',
                            icon: Icons.category_outlined,
                            options: setup.paymentTypes,
                            selected: _paymentType,
                            displayString: (t) => t.name,
                            searchText: (t) => t.searchText,
                            subtitleFor: (t) => 'ID ${t.id}',
                            onSelected: (v) =>
                                setState(() => _paymentType = v),
                            validator: (v) =>
                                v == null ? 'Select payment type' : null,
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(child: _id(_recType, 'Rec type')),
                              const SizedBox(width: 10),
                              Expanded(child: _id(_paymentFor, 'Payment for')),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _id(_invoiceType, 'Invoice type'),
                          const SizedBox(height: 12),
                          _text(_note, 'Note', Icons.notes_outlined,
                              required: false),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _text(
                                  _trxId,
                                  'Transaction ID',
                                  Icons.receipt_outlined,
                                  required: false,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _text(
                                  _ref,
                                  'Reference',
                                  Icons.link_outlined,
                                  required: false,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _text(
                                  _checkNo,
                                  'Check no (optional)',
                                  Icons.numbers_outlined,
                                  required: false,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _text(
                                  _checkDate,
                                  'Check date (optional)',
                                  Icons.event_outlined,
                                  required: false,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            height: 52,
                            child: ElevatedButton(
                              onPressed: _isSubmitting ? null : _submit,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.success,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: _isSubmitting
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Text(
                                      'Submit payment',
                                      style: GoogleFonts.poppins(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 15,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _dec(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.poppins(fontSize: 13),
      prefixIcon: Icon(icon, size: 20),
      filled: true,
      fillColor: AppColors.background,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    );
  }

  Widget _id(TextEditingController c, String label) {
    return TextFormField(
      controller: c,
      keyboardType: TextInputType.number,
      validator: (v) {
        if (int.tryParse(v?.trim() ?? '') == null) return 'Required';
        return null;
      },
      style: GoogleFonts.poppins(fontSize: 14),
      decoration: _dec(label, Icons.tag_outlined),
    );
  }

  Widget _money(TextEditingController c, String label) {
    return TextFormField(
      controller: c,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      validator: (v) {
        final n = double.tryParse(v?.trim() ?? '');
        if (n == null || n <= 0) return 'Required';
        return null;
      },
      style: GoogleFonts.poppins(fontSize: 14),
      decoration: _dec(label, Icons.payments_outlined),
    );
  }

  Widget _text(
    TextEditingController c,
    String label,
    IconData icon, {
    bool required = true,
  }) {
    return TextFormField(
      controller: c,
      validator: required
          ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null
          : null,
      style: GoogleFonts.poppins(fontSize: 14),
      decoration: _dec(label, icon),
    );
  }
}
