import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../config/theme.dart';
import '../models/auth_wise_payment_post_models.dart';
import '../models/dealer_list_models.dart';
import '../models/payment_setup_models.dart';
import '../services/auth_service.dart';
import '../services/payment_service.dart';
import '../services/sales_service.dart';
import '../widgets/gradient_screen_header.dart';
import '../widgets/searchable_select_field.dart';
import '../widgets/section_card.dart';

class _PaymentModeOption {
  const _PaymentModeOption(this.id, this.label);

  final int id;
  final String label;
}

class _QueuedPayment {
  const _QueuedPayment({
    required this.input,
    required this.receiverName,
    required this.recTypeName,
    required this.paymentForName,
    required this.invoiceTypeName,
    required this.paymentModeName,
    required this.bankName,
  });

  final AuthWisePaymentLineInput input;
  final String receiverName;
  final String recTypeName;
  final String paymentForName;
  final String invoiceTypeName;
  final String paymentModeName;
  final String bankName;
}

class PostAuthWisePaymentScreen extends StatefulWidget {
  const PostAuthWisePaymentScreen({super.key});

  @override
  State<PostAuthWisePaymentScreen> createState() =>
      _PostAuthWisePaymentScreenState();
}

class _PostAuthWisePaymentScreenState extends State<PostAuthWisePaymentScreen> {
  static const _paymentModes = <_PaymentModeOption>[
    _PaymentModeOption(1, 'Cash'),
    _PaymentModeOption(2, 'Online Banking'),
    _PaymentModeOption(3, 'Online Transfer'),
    _PaymentModeOption(4, 'Mobile Banking'),
    _PaymentModeOption(5, 'Pay Order'),
    _PaymentModeOption(6, 'Check'),
    _PaymentModeOption(7, 'DD'),
    _PaymentModeOption(8, 'TT'),
  ];

  final PaymentService _paymentService = PaymentService();
  final SalesService _salesService = SalesService();
  final AuthService _authService = AuthService();
  final _formKey = GlobalKey<FormState>();

  DateTime _recDate = DateTime.now();
  bool _isSubmitting = false;
  bool _loadingSetup = true;
  String? _setupError;
  PaymentSetupData? _setup;
  AllDealerLists? _dealerLists;
  int? _employeeId;

  SetupCompany? _company;
  SetupPaymentType? _paymentFor;
  int _recType = 1;
  int? _invoiceType;
  _PaymentModeOption? _paymentMode;
  SetupBank? _bank;
  DealerListItem? _dealer;
  SetupEmployee? _employee;

  final _amount = TextEditingController();
  final _note = TextEditingController();
  final _trxId = TextEditingController();
  final _ref = TextEditingController();
  final _checkNo = TextEditingController();
  DateTime? _checkDate;

  final List<_QueuedPayment> _queue = [];

  bool get _isDealer => _recType == 1;

  bool get _hasReceiver =>
      _isDealer ? _dealer != null : _employee != null;

  bool get _invoiceEnabled => _hasReceiver;

  bool get _isCheck => _paymentMode?.id == 6;

  bool get _usesTrx {
    final id = _paymentMode?.id;
    return id == 2 || id == 3 || id == 4 || id == 5 || id == 7 || id == 8;
  }

  List<DealerListItem> get _dealersForPaymentFor {
    final lists = _dealerLists;
    if (lists == null) return const [];
    return lists.listForPaymentFor(
      id: _paymentFor?.id,
      name: _paymentFor?.name,
    );
  }

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadMasters();
  }

  Future<void> _loadMasters() async {
    setState(() {
      _loadingSetup = true;
      _setupError = null;
    });

    final setupResult = await _paymentService.fetchPaymentSetupData();
    final dealerResult = await _salesService.fetchAllDealerLists();
    if (!mounted) return;

    if (!setupResult.success || setupResult.data == null) {
      setState(() {
        _loadingSetup = false;
        _setupError = setupResult.message ?? 'Could not load payment setup.';
      });
      return;
    }

    final setup = setupResult.data!;
    if (setup.banks.isEmpty || setup.paymentTypes.isEmpty) {
      setState(() {
        _loadingSetup = false;
        _setupError =
            'Payment setup returned no banks or payment types. Try again later.';
      });
      return;
    }

    final companies = setup.uniqueCompanies;
    setState(() {
      _loadingSetup = false;
      _setup = setup;
      _dealerLists = dealerResult.data;
      _company ??= companies.isNotEmpty ? companies.first : null;
      if (dealerResult.success != true || dealerResult.data == null) {
        _setupError = dealerResult.message ??
            'Dealer lists could not be loaded. Employee receive still works.';
      }
    });
  }

  Future<void> _loadProfile() async {
    final profile = await _authService.getCurrentUserProfile();
    if (!mounted) return;
    setState(() => _employeeId = profile?.canonicalEmployeeId);
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    _trxId.dispose();
    _ref.dispose();
    _checkNo.dispose();
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

  Future<void> _pickCheckDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _checkDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _checkDate = picked);
  }

  void _onPaymentForChanged(SetupPaymentType? value) {
    setState(() {
      _paymentFor = value;
      _dealer = null;
      _employee = null;
      _invoiceType = null;
    });
  }

  void _onRecTypeChanged(int? value) {
    if (value == null) return;
    setState(() {
      _recType = value;
      _dealer = null;
      _employee = null;
      _invoiceType = null;
    });
  }

  void _onPaymentModeChanged(_PaymentModeOption? value) {
    setState(() {
      _paymentMode = value;
      _bank = null;
      _checkNo.clear();
      _checkDate = null;
      _trxId.clear();
      _ref.clear();
    });
  }

  int? _companyId() {
    if (_company != null && _company!.id > 0) return _company!.id;
    final fromBank = _bank?.company?.id;
    if (fromBank != null && fromBank > 0) return fromBank;
    return null;
  }

  int? _receiverId() {
    if (_isDealer) {
      final id = _dealer?.id;
      if (id != null && id > 0) return id;
      return null;
    }
    final id = _employee?.employeeId;
    if (id != null && id > 0) return id;
    return null;
  }

  String _receiverName() {
    if (_isDealer) return _dealer?.tradeName ?? 'Dealer';
    return _employee?.employeeName ?? 'Employee';
  }

  AuthWisePaymentLineInput? _buildLine() {
    if (!_formKey.currentState!.validate()) return null;

    final employeeId = _employeeId;
    if (employeeId == null || employeeId <= 0) {
      _snack('Please login again.');
      return null;
    }
    final paymentFor = _paymentFor;
    if (paymentFor == null) {
      _snack('Select Payment For.');
      return null;
    }
    final receiverId = _receiverId();
    if (receiverId == null) {
      _snack('Select a receiver.');
      return null;
    }
    if (_invoiceType == null) {
      _snack('Select invoice type.');
      return null;
    }
    final mode = _paymentMode;
    if (mode == null) {
      _snack('Select payment mode.');
      return null;
    }
    final bank = _bank;
    if (bank == null) {
      _snack('Select payment type (bank / account).');
      return null;
    }
    final companyId = _companyId();
    if (companyId == null) {
      _snack('Select a company.');
      return null;
    }
    final amount = double.tryParse(_amount.text.trim());
    if (amount == null || amount <= 0) {
      _snack('Enter a valid amount.');
      return null;
    }
    if (_isCheck && (_checkNo.text.trim().isEmpty || _checkDate == null)) {
      _snack('Enter check no and check date.');
      return null;
    }

    var trxId = _trxId.text.trim();
    if (_usesTrx && trxId.isEmpty) trxId = '0';
    var ref = _ref.text.trim();
    if (ref.isEmpty) ref = '0';

    return AuthWisePaymentLineInput(
      companyId: companyId,
      recType: _recType,
      receiverId: receiverId,
      amount: amount,
      recDate: DateFormat('yyyy-MM-dd').format(_recDate),
      paymentType: bank.id,
      paymentMode: mode.id,
      paymentFor: paymentFor.id,
      invoiceType: _invoiceType!,
      note: _note.text.trim(),
      trxId: _usesTrx ? trxId : null,
      ref: ref,
      checkNo: _isCheck ? _checkNo.text.trim() : null,
      checkDate: _isCheck && _checkDate != null
          ? DateFormat('yyyy-MM-dd').format(_checkDate!)
          : null,
    );
  }

  void _addToQueue() {
    final line = _buildLine();
    if (line == null) return;

    setState(() {
      _queue.add(
        _QueuedPayment(
          input: line,
          receiverName: _receiverName(),
          recTypeName: _isDealer ? 'Dealer' : 'Employee',
          paymentForName: _paymentFor?.name ?? '',
          invoiceTypeName:
              _invoiceType == 1 ? 'With voucher' : 'Without voucher',
          paymentModeName: _paymentMode?.label ?? '',
          bankName: _bank?.displayLabel ?? '',
        ),
      );
      _dealer = null;
      _employee = null;
      _invoiceType = null;
      _paymentMode = null;
      _bank = null;
      _amount.clear();
      _note.clear();
      _trxId.clear();
      _ref.clear();
      _checkNo.clear();
      _checkDate = null;
    });
    _snack('Payment added. Add another or tap Save.');
  }

  Future<void> _saveQueue() async {
    if (_queue.isEmpty) {
      _snack('Please add at least one payment receive entry.');
      return;
    }
    final employeeId = _employeeId;
    if (employeeId == null || employeeId <= 0) {
      _snack('Please login again.');
      return;
    }

    setState(() => _isSubmitting = true);
    final request = CreateAuthWisePaymentRequest(
      employeeId: employeeId,
      payments: _queue.map((e) => e.input).toList(),
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
              subtitle: 'Create payment receive (sales backend)',
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
                            'Loading payment setup…',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ] else if (_setup == null && _setupError != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _setupError!,
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              color: AppColors.error,
                            ),
                          ),
                          TextButton(
                            onPressed: _loadMasters,
                            child: const Text('Retry'),
                          ),
                        ] else if (setup != null) ...[
                          if (_setupError != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              _setupError!,
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                color: AppColors.warning,
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          _dateTile('Voucher date', _recDate, _pickRecDate),
                          const SizedBox(height: 12),
                          SearchableSelectField<SetupCompany>(
                            label: 'Company',
                            icon: Icons.business_outlined,
                            options: setup.uniqueCompanies,
                            selected: _company,
                            displayString: (c) => c.displayLabel,
                            searchText: (c) => c.searchText,
                            onSelected: (v) => setState(() => _company = v),
                            validator: (v) =>
                                v == null && _companyId() == null
                                    ? 'Select a company'
                                    : null,
                          ),
                          const SizedBox(height: 12),
                          SearchableSelectField<SetupPaymentType>(
                            label: 'Payment For',
                            icon: Icons.category_outlined,
                            options: setup.paymentTypes,
                            selected: _paymentFor,
                            displayString: (t) => t.name,
                            searchText: (t) => t.searchText,
                            onSelected: _onPaymentForChanged,
                            validator: (v) =>
                                v == null ? 'Select Payment For' : null,
                          ),
                          const SizedBox(height: 12),
                          _intDropdown(
                            label: 'Payment Receiver Type',
                            icon: Icons.people_outline,
                            value: _recType,
                            items: const [
                              (1, 'Dealer'),
                              (2, 'Employee'),
                            ],
                            onChanged: _onRecTypeChanged,
                          ),
                          const SizedBox(height: 12),
                          if (_isDealer)
                            SearchableSelectField<DealerListItem>(
                              key: ValueKey(
                                'dealer_${_paymentFor?.id}_${_dealersForPaymentFor.length}',
                              ),
                              label: 'Select Receiver',
                              icon: Icons.store_outlined,
                              options: _dealersForPaymentFor,
                              selected: _dealer,
                              displayString: (d) => d.tradeName,
                              searchText: (d) => d.searchText,
                              subtitleFor: (d) => d.subtitle,
                              onSelected: (v) => setState(() {
                                _dealer = v;
                                _invoiceType = null;
                              }),
                              validator: (v) =>
                                  v == null ? 'Select a receiver' : null,
                            )
                          else
                            SearchableSelectField<SetupEmployee>(
                              label: 'Select Receiver',
                              icon: Icons.person_outline,
                              options: setup.employees,
                              selected: _employee,
                              displayString: (e) => e.employeeName,
                              searchText: (e) => e.searchText,
                              subtitleFor: (e) => e.subtitle,
                              onSelected: (v) => setState(() {
                                _employee = v;
                                _invoiceType = null;
                              }),
                              validator: (v) =>
                                  v == null ? 'Select a receiver' : null,
                            ),
                          const SizedBox(height: 12),
                          _intDropdown(
                            label: 'Invoice Type',
                            icon: Icons.receipt_long_outlined,
                            value: _invoiceType,
                            enabled: _invoiceEnabled,
                            items: const [
                              (1, 'With voucher'),
                              (2, 'Without voucher'),
                            ],
                            onChanged: _invoiceEnabled
                                ? (v) => setState(() => _invoiceType = v)
                                : null,
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<_PaymentModeOption>(
                            key: ValueKey(_paymentMode?.id),
                            initialValue: _paymentMode,
                            decoration: _dec(
                              'Payment Mode',
                              Icons.payments_outlined,
                            ),
                            items: _paymentModes
                                .map(
                                  (m) => DropdownMenuItem(
                                    value: m,
                                    child: Text(
                                      m.label,
                                      style: GoogleFonts.poppins(fontSize: 14),
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: _onPaymentModeChanged,
                            validator: (v) =>
                                v == null ? 'Select payment mode' : null,
                          ),
                          if (_paymentMode != null) ...[
                            const SizedBox(height: 12),
                            SearchableSelectField<SetupBank>(
                              label: 'Payment Type',
                              icon: Icons.account_balance_outlined,
                              options: setup.banks,
                              selected: _bank,
                              displayString: (b) => b.displayLabel,
                              searchText: (b) => b.searchText,
                              subtitleFor: (b) =>
                                  b.company?.nameEn ?? 'ID ${b.id}',
                              onSelected: (v) => setState(() {
                                _bank = v;
                                final company = v?.company;
                                if (company != null &&
                                    company.id > 0 &&
                                    _company == null) {
                                  _company = company;
                                }
                              }),
                              validator: (v) =>
                                  v == null ? 'Select payment type' : null,
                            ),
                            const SizedBox(height: 12),
                            if (_isCheck) ...[
                              _text(
                                _checkNo,
                                'Check No',
                                Icons.numbers_outlined,
                              ),
                              const SizedBox(height: 12),
                              _dateTile(
                                'Check Date',
                                _checkDate,
                                _pickCheckDate,
                              ),
                              const SizedBox(height: 12),
                            ],
                            if (_usesTrx) ...[
                              _text(
                                _trxId,
                                'Transaction Id',
                                Icons.receipt_outlined,
                                required: false,
                              ),
                              const SizedBox(height: 12),
                            ],
                            _text(
                              _ref,
                              'Ref',
                              Icons.link_outlined,
                              required: false,
                            ),
                            const SizedBox(height: 12),
                            _money(_amount, 'Amount (৳)'),
                          ],
                          const SizedBox(height: 12),
                          _text(
                            _note,
                            'Note',
                            Icons.notes_outlined,
                            required: false,
                            maxLines: 3,
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            height: 48,
                            child: OutlinedButton.icon(
                              onPressed: _isSubmitting ? null : _addToQueue,
                              icon: const Icon(Icons.add),
                              label: Text(
                                'ADD',
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          if (_queue.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            Text(
                              'Queued payments (${_queue.length})',
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 8),
                            ...List.generate(_queue.length, (index) {
                              final row = _queue[index];
                              return Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                child: ListTile(
                                  dense: true,
                                  title: Text(
                                    '${row.receiverName} · ৳${_fmtAmount(row.input.amount)}',
                                    style: GoogleFonts.poppins(fontSize: 13),
                                  ),
                                  subtitle: Text(
                                    '${row.recTypeName} · ${row.paymentForName}\n'
                                    '${row.paymentModeName} · ${row.bankName}',
                                    style: GoogleFonts.poppins(fontSize: 11),
                                  ),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.close),
                                    onPressed: () => setState(
                                      () => _queue.removeAt(index),
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ],
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 52,
                            child: ElevatedButton(
                              onPressed: _isSubmitting ? null : _saveQueue,
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
                                      'SAVE',
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

  String _fmtAmount(double amount) {
    if (amount == amount.roundToDouble()) return amount.round().toString();
    return amount.toStringAsFixed(2);
  }

  Widget _intDropdown({
    required String label,
    required IconData icon,
    required int? value,
    required List<(int, String)> items,
    required ValueChanged<int?>? onChanged,
    bool enabled = true,
  }) {
    return DropdownButtonFormField<int>(
      key: ValueKey('$label-$value-$enabled'),
      initialValue: value,
      decoration: _dec(label, icon),
      items: items
          .map(
            (item) => DropdownMenuItem(
              value: item.$1,
              child: Text(item.$2, style: GoogleFonts.poppins(fontSize: 14)),
            ),
          )
          .toList(),
      onChanged: enabled ? onChanged : null,
      validator: (v) => v == null ? 'Required' : null,
    );
  }

  Widget _dateTile(String label, DateTime? date, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: _dec(label, Icons.calendar_today_outlined),
        child: Text(
          date == null ? 'Select date' : DateFormat('dd MMM yyyy').format(date),
          style: GoogleFonts.poppins(
            fontSize: 14,
            color: date == null ? AppColors.textHint : AppColors.textPrimary,
          ),
        ),
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
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: c,
      maxLines: maxLines,
      validator: required
          ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null
          : null,
      style: GoogleFonts.poppins(fontSize: 14),
      decoration: _dec(label, icon),
    );
  }
}
