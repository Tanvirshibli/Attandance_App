import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../config/theme.dart';
import '../models/dealer_list_models.dart';
import '../models/sales_booking_post_models.dart';
import '../models/sales_post_models.dart';
import '../services/auth_service.dart';
import '../services/sales_service.dart';
import '../widgets/gradient_screen_header.dart';
import '../widgets/searchable_select_field.dart';
import '../widgets/section_card.dart';

class PostSaleScreen extends StatefulWidget {
  const PostSaleScreen({super.key});

  @override
  State<PostSaleScreen> createState() => _PostSaleScreenState();
}

class _PostSaleScreenState extends State<PostSaleScreen> {
  final SalesService _salesService = SalesService();
  final AuthService _authService = AuthService();
  final _formKey = GlobalKey<FormState>();

  static const _modules = [
    ('feed', 'Feed'),
    ('egg', 'Egg'),
    ('fertilizer', 'Fertilizer'),
    ('chicks', 'Chicks'),
    ('liveBird', 'Live Bird'),
    ('cullBird', 'Cull Bird'),
  ];

  static const _saleTypes = ['Cash', 'Credit'];
  static const _bookingTypes = ['regular'];

  String _module = 'feed';
  String _saleType = 'Cash';
  String _bookingType = 'regular';
  bool _isBookingMoney = false;
  bool _isMultiDelivery = false;
  DateTime _invoiceDate = DateTime.now();
  DateTime _dueDate = DateTime.now();
  DateTime _bookingDate = DateTime.now();

  final _salesPointId = TextEditingController();
  final _companyId = TextEditingController();
  final _totalAmount = TextEditingController();

  final _categoryId = TextEditingController();
  final _subCategoryId = TextEditingController();
  final _childCategoryId = TextEditingController();
  final _bookingPointId = TextEditingController();
  final _cZoneId = TextEditingController();
  final _chicksPriceId = TextEditingController();
  final _commissionId = TextEditingController();
  final _discount = TextEditingController(text: '0');
  final _advanceAmount = TextEditingController(text: '0');
  final _bookingNote =
      TextEditingController(text: 'Created from mobile app');
  final _lineNote = TextEditingController();
  final _cdPriceId = TextEditingController();
  final _mrp = TextEditingController();
  final _settingIds = TextEditingController();
  final _flockIds = TextEditingController();

  AllDealerLists? _dealerLists;
  bool _loadingDealers = true;
  String? _dealerLoadError;
  DealerListItem? _selectedDealer;

  final _productId = TextEditingController();
  final _tradePrice = TextEditingController();
  final _salePrice = TextEditingController();
  final _qty = TextEditingController();
  final _unitId = TextEditingController(text: '1');
  final _unitBatchNo = TextEditingController();

  bool _isSubmitting = false;
  int? _salesPersonId;

  bool get _usesBooking => _module == 'feed' || _module == 'chicks';

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadDealers();
    _salePrice.addListener(_syncTotalFromLine);
    _qty.addListener(_syncTotalFromLine);
  }

  Future<void> _loadDealers() async {
    setState(() {
      _loadingDealers = true;
      _dealerLoadError = null;
    });
    final result = await _salesService.fetchAllDealerLists();
    if (!mounted) return;
    if (!result.success || result.data == null) {
      setState(() {
        _loadingDealers = false;
        _dealerLoadError = result.message ?? 'Could not load dealers.';
      });
      return;
    }
    setState(() {
      _loadingDealers = false;
      _dealerLists = result.data;
    });
  }

  List<DealerListItem> get _dealersForModule {
    final lists = _dealerLists;
    if (lists == null) return const [];
    return lists.listForModule(_module);
  }

  void _onModuleChanged(String? value) {
    if (value == null) return;
    setState(() {
      _module = value;
      final dealers = _dealersForModule;
      if (_selectedDealer != null &&
          !dealers.any((d) => d.id == _selectedDealer!.id)) {
        _selectedDealer = null;
      }
    });
  }

  Future<void> _loadProfile() async {
    final profile = await _authService.getCurrentUserProfile();
    if (!mounted) return;
    setState(() {
      _salesPersonId = profile?.canonicalEmployeeId;
    });
  }

  void _syncTotalFromLine() {
    final q = double.tryParse(_qty.text.trim());
    final p = double.tryParse(_salePrice.text.trim());
    if (q != null && p != null && q > 0 && p > 0) {
      final total = q * p;
      _totalAmount.text = total == total.roundToDouble()
          ? total.round().toString()
          : total.toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    _salesPointId.dispose();
    _companyId.dispose();
    _totalAmount.dispose();
    _categoryId.dispose();
    _subCategoryId.dispose();
    _childCategoryId.dispose();
    _bookingPointId.dispose();
    _cZoneId.dispose();
    _chicksPriceId.dispose();
    _commissionId.dispose();
    _discount.dispose();
    _advanceAmount.dispose();
    _bookingNote.dispose();
    _lineNote.dispose();
    _cdPriceId.dispose();
    _mrp.dispose();
    _settingIds.dispose();
    _flockIds.dispose();
    _productId.dispose();
    _tradePrice.dispose();
    _salePrice.dispose();
    _qty.dispose();
    _unitId.dispose();
    _unitBatchNo.dispose();
    super.dispose();
  }

  Future<void> _pickDate({bool due = false, bool booking = false}) async {
    final initial = booking
        ? _bookingDate
        : due
            ? _dueDate
            : _invoiceDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 90)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      if (booking) {
        _bookingDate = picked;
      } else if (due) {
        _dueDate = picked;
      } else {
        _invoiceDate = picked;
      }
    });
  }

  int? _parseInt(String? v, String label, {bool allowZero = false}) {
    final n = int.tryParse(v?.trim() ?? '');
    if (n == null || (!allowZero && n <= 0)) {
      _snack('Enter a valid $label.');
      return null;
    }
    return n;
  }

  double? _parseDouble(String? v, String label, {bool allowZero = false}) {
    final n = double.tryParse(v?.trim() ?? '');
    if (n == null || (!allowZero && n <= 0)) {
      _snack('Enter a valid $label.');
      return null;
    }
    return n;
  }

  List<int> _parseIdList(String raw) {
    return raw
        .split(RegExp(r'[,\s]+'))
        .map((s) => int.tryParse(s.trim()))
        .whereType<int>()
        .where((id) => id > 0)
        .toList();
  }

  Future<void> _submitBooking(int bookingPerson, int dealerId) async {
    final categoryId = _parseInt(_categoryId.text, 'category ID');
    final subCategoryId = _parseInt(_subCategoryId.text, 'sub category ID');
    final childCategoryId = _parseInt(_childCategoryId.text, 'child category ID');
    final bookingPointId = _parseInt(_bookingPointId.text, 'booking point ID');
    final productId = _parseInt(_productId.text, 'product ID');
    final unitId = _parseInt(_unitId.text, 'unit ID');
    final qty = _parseDouble(_qty.text, 'quantity');
    final price = _parseDouble(_salePrice.text, 'price');
    final totalAmount = _parseDouble(_totalAmount.text, 'total amount');
    final discount = _parseDouble(_discount.text, 'discount', allowZero: true);
    final advanceAmount =
        _parseDouble(_advanceAmount.text, 'advance amount', allowZero: true);

    if (categoryId == null ||
        subCategoryId == null ||
        childCategoryId == null ||
        bookingPointId == null ||
        productId == null ||
        unitId == null ||
        qty == null ||
        price == null ||
        totalAmount == null ||
        discount == null ||
        advanceAmount == null) {
      return;
    }

    int? cZoneId;
    int? chicksPriceId;
    int? cdPriceId;
    double? mrp;
    if (_module == 'chicks') {
      cZoneId = _parseInt(_cZoneId.text, 'zone ID');
      if (cZoneId == null) return;
      final chicksRaw = _chicksPriceId.text.trim();
      if (chicksRaw.isNotEmpty) {
        chicksPriceId = _parseInt(chicksRaw, 'chicks price ID');
        if (chicksPriceId == null) return;
      }
      final cdRaw = _cdPriceId.text.trim();
      if (cdRaw.isNotEmpty) {
        cdPriceId = _parseInt(cdRaw, 'cd price ID');
        if (cdPriceId == null) return;
      }
      final mrpRaw = _mrp.text.trim();
      if (mrpRaw.isNotEmpty) {
        mrp = _parseDouble(mrpRaw, 'MRP');
        if (mrp == null) return;
      }
    }

    int? commissionId;
    final commRaw = _commissionId.text.trim();
    if (commRaw.isNotEmpty) {
      commissionId = _parseInt(commRaw, 'commission ID');
      if (commissionId == null) return;
    }

    final fmt = DateFormat('yyyy-MM-dd');
    final request = CreateBookingPersonBookRequest(
      module: _module,
      dealerId: dealerId,
      categoryId: categoryId,
      subCategoryId: subCategoryId,
      childCategoryId: childCategoryId,
      bookingPointId: bookingPointId,
      bookingPerson: bookingPerson,
      bookingType: _bookingType,
      isBookingMoney: _isBookingMoney,
      isMultiDelivery: _isMultiDelivery,
      discount: discount,
      discountType: 'fixed',
      advanceAmount: advanceAmount,
      totalAmount: totalAmount,
      bookingDate: fmt.format(_bookingDate),
      invoiceDate: fmt.format(_invoiceDate),
      cZoneId: cZoneId,
      chicksPriceId: chicksPriceId,
      commissionId: commissionId,
      note: _bookingNote.text.trim(),
      lines: [
        BookingLineInput(
          productId: productId,
          unitId: unitId,
          qty: qty,
          price: price,
          note: _lineNote.text.trim().isEmpty ? null : _lineNote.text.trim(),
          cdPriceId: cdPriceId,
          mrp: mrp,
          settingIds: _module == 'chicks'
              ? _parseIdList(_settingIds.text)
              : const [],
          flockIds:
              _module == 'chicks' ? _parseIdList(_flockIds.text) : const [],
        ),
      ],
    );

    setState(() => _isSubmitting = true);
    final result = await _salesService.createBookingPersonBook(request);
    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (!result.success || result.data == null) {
      _snack(result.message ?? 'Could not submit booking.');
      return;
    }

    final created = result.data!;
    final ref = created.bookingNo.isNotEmpty
        ? created.bookingNo
        : '#${created.id}';
    _snack(
      created.message?.isNotEmpty == true
          ? '${created.message} Booking: $ref'
          : 'Booking submitted. No: $ref',
    );
    Navigator.of(context).pop(true);
  }

  Future<void> _submitOrder(int salesPersonId, int dealerId) async {
    final salesPointId = _parseInt(_salesPointId.text, 'sales point ID');
    final companyId = _parseInt(_companyId.text, 'company ID');
    final productId = _parseInt(_productId.text, 'product ID');
    final unitId = _parseInt(_unitId.text, 'unit ID');
    final tradePrice = _parseDouble(_tradePrice.text, 'trade price');
    final salePrice = _parseDouble(_salePrice.text, 'sale price');
    final qty = _parseDouble(_qty.text, 'quantity');
    final totalAmount = _parseDouble(_totalAmount.text, 'total amount');

    if (salesPointId == null ||
        companyId == null ||
        productId == null ||
        unitId == null ||
        tradePrice == null ||
        salePrice == null ||
        qty == null ||
        totalAmount == null) {
      return;
    }

    setState(() => _isSubmitting = true);

    final fmt = DateFormat('yyyy-MM-dd');
    final request = CreateSalesPersonOrderRequest(
      module: _module,
      salesPersonId: salesPersonId,
      dealerId: dealerId,
      salesPointId: salesPointId,
      companyId: companyId,
      totalAmount: totalAmount,
      invoiceDate: fmt.format(_invoiceDate),
      dueDate: fmt.format(_dueDate),
      saleType: _saleType,
      lines: [
        SalesOrderLineInput(
          productId: productId,
          tradePrice: tradePrice,
          salePrice: salePrice,
          qty: qty,
          unitId: unitId,
          unitBatchNo: _unitBatchNo.text.trim().isEmpty
              ? null
              : _unitBatchNo.text.trim(),
        ),
      ],
    );

    final result = await _salesService.createSalesPersonOrder(request);
    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (!result.success || result.data == null) {
      _snack(result.message ?? 'Could not submit sale.');
      return;
    }

    final created = result.data!;
    final ref = created.referenceNo.isNotEmpty
        ? created.referenceNo
        : '#${created.id}';
    _snack(
      created.message?.isNotEmpty == true
          ? '${created.message} Ref: $ref'
          : 'Sale submitted. Ref: $ref',
    );
    Navigator.of(context).pop(true);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final salesPersonId = _salesPersonId;
    if (salesPersonId == null || salesPersonId <= 0) {
      _snack('Please login again.');
      return;
    }

    final dealer = _selectedDealer;
    if (dealer == null || dealer.id <= 0) {
      _snack('Select a dealer.');
      return;
    }

    if (_usesBooking) {
      await _submitBooking(salesPersonId, dealer.id);
    } else {
      await _submitOrder(salesPersonId, dealer.id);
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message, style: GoogleFonts.poppins())),
    );
  }

  Widget _dealerSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_loadingDealers)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else if (_dealerLoadError != null)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _dealerLoadError!,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: AppColors.error,
                ),
              ),
              TextButton(
                onPressed: _loadDealers,
                child: const Text('Retry dealers'),
              ),
            ],
          ),
        const SizedBox(height: 12),
        SearchableSelectField<DealerListItem>(
          label: 'Dealer',
          icon: Icons.store_outlined,
          options: _dealersForModule,
          selected: _selectedDealer,
          enabled: !_loadingDealers && _dealerLists != null,
          displayString: (d) => d.tradeName,
          searchText: (d) => d.searchText,
          subtitleFor: (d) => d.subtitle,
          onSelected: (d) => setState(() => _selectedDealer = d),
          validator: (v) => v == null ? 'Select a dealer' : null,
        ),
      ],
    );
  }

  Widget _buildBookingFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _dealerSection(),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _idField(_categoryId, 'Category ID')),
            const SizedBox(width: 10),
            Expanded(child: _idField(_subCategoryId, 'Sub category ID')),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _idField(_childCategoryId, 'Child category ID')),
            const SizedBox(width: 10),
            Expanded(child: _idField(_bookingPointId, 'Booking point ID')),
          ],
        ),
        const SizedBox(height: 12),
        _dropdown(
          label: 'Booking type',
          value: _bookingType,
          items: _bookingTypes
              .map((t) => DropdownMenuItem(value: t, child: Text(t)))
              .toList(),
          onChanged: (v) => setState(() => _bookingType = v ?? _bookingType),
        ),
        if (_module == 'chicks') ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _idField(_cZoneId, 'Zone ID (cZoneId)')),
              const SizedBox(width: 10),
              Expanded(
                child: _optionalIdField(_chicksPriceId, 'Chicks price ID'),
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            'Booking money',
            style: GoogleFonts.poppins(fontSize: 14),
          ),
          value: _isBookingMoney,
          onChanged: (v) => setState(() => _isBookingMoney = v),
        ),
        if (_module == 'chicks')
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              'Multi delivery',
              style: GoogleFonts.poppins(fontSize: 14),
            ),
            value: _isMultiDelivery,
            onChanged: (v) => setState(() => _isMultiDelivery = v),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _moneyField(
                _discount,
                'Discount',
                validator: (v) {
                  if (double.tryParse(v?.trim() ?? '') == null) {
                    return 'Required';
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _moneyField(
                _advanceAmount,
                'Advance',
                validator: (v) {
                  if (double.tryParse(v?.trim() ?? '') == null) {
                    return 'Required';
                  }
                  return null;
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _optionalIdField(_commissionId, 'Commission ID (optional)'),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _dateTile(
                'Booking date',
                _bookingDate,
                () => _pickDate(booking: true),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _dateTile(
                'Invoice date',
                _invoiceDate,
                () => _pickDate(due: false),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _field(
          _bookingNote,
          'Note',
          Icons.notes_outlined,
          required: false,
        ),
        const SizedBox(height: 20),
        Text(
          'Line item',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        const SizedBox(height: 10),
        _idField(_productId, 'Product ID'),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _moneyField(_salePrice, 'Price')),
            const SizedBox(width: 10),
            Expanded(child: _moneyField(_qty, 'Quantity')),
          ],
        ),
        const SizedBox(height: 12),
        _idField(_unitId, 'Unit ID', Icons.straighten_outlined),
        const SizedBox(height: 12),
        _field(
          _lineNote,
          'Line note (optional)',
          Icons.tag_outlined,
          required: false,
        ),
        if (_module == 'chicks') ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _optionalIdField(_cdPriceId, 'CD price ID')),
              const SizedBox(width: 10),
              Expanded(
                child: _moneyField(
                  _mrp,
                  'MRP (optional)',
                  validator: (v) {
                    final t = v?.trim() ?? '';
                    if (t.isEmpty) return null;
                    if (double.tryParse(t) == null) return 'Invalid';
                    return null;
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _field(
            _settingIds,
            'Setting IDs (comma-separated)',
            Icons.list_alt_outlined,
            required: false,
          ),
          const SizedBox(height: 12),
          _field(
            _flockIds,
            'Flock IDs (comma-separated)',
            Icons.list_alt_outlined,
            required: false,
          ),
        ],
        const SizedBox(height: 12),
        _moneyField(
          _totalAmount,
          'Total amount (৳)',
          validator: (v) {
            final n = double.tryParse(v?.trim() ?? '');
            if (n == null || n <= 0) return 'Required';
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildOrderFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _dropdown(
          label: 'Sale type',
          value: _saleType,
          items: _saleTypes
              .map((t) => DropdownMenuItem(value: t, child: Text(t)))
              .toList(),
          onChanged: (v) => setState(() => _saleType = v ?? _saleType),
        ),
        const SizedBox(height: 12),
        _idField(_companyId, 'Company ID', Icons.business_outlined),
        const SizedBox(height: 12),
        _dealerSection(),
        const SizedBox(height: 12),
        _idField(_salesPointId, 'Sales point ID', Icons.place_outlined),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _dateTile(
                'Invoice date',
                _invoiceDate,
                () => _pickDate(due: false),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _dateTile(
                'Due date',
                _dueDate,
                () => _pickDate(due: true),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          'Line item',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        const SizedBox(height: 10),
        _idField(_productId, 'Product ID', Icons.inventory_2_outlined),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _moneyField(_tradePrice, 'Trade price')),
            const SizedBox(width: 10),
            Expanded(child: _moneyField(_salePrice, 'Sale price')),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _moneyField(_qty, 'Quantity')),
            const SizedBox(width: 10),
            Expanded(
              child: _idField(_unitId, 'Unit ID', Icons.straighten_outlined),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _field(
          _unitBatchNo,
          'Unit batch no (optional)',
          Icons.tag_outlined,
          required: false,
        ),
        const SizedBox(height: 12),
        _moneyField(
          _totalAmount,
          'Total amount (৳)',
          validator: (v) {
            final n = double.tryParse(v?.trim() ?? '');
            if (n == null || n <= 0) return 'Required';
            return null;
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final demo = _salesService.useCreateDemo;
    final booking = _usesBooking;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: GradientScreenHeader(
              title: booking ? 'Post booking' : 'Post sale',
              subtitle: demo
                  ? 'Demo mode — enable live sales to post to server'
                  : booking
                      ? 'Feed / chicks → booking-person-books'
                      : 'Submit order to sales.peoplesitsolution.online',
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
                        if (_salesPersonId != null)
                          Text(
                            booking
                                ? 'Booking person ID: $_salesPersonId'
                                : 'Sales person ID: $_salesPersonId',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        const SizedBox(height: 12),
                        _dropdown(
                          label: 'Module',
                          value: _module,
                          items: _modules
                              .map((m) => DropdownMenuItem(
                                    value: m.$1,
                                    child: Text(m.$2),
                                  ))
                              .toList(),
                          onChanged: _onModuleChanged,
                        ),
                        const SizedBox(height: 12),
                        if (booking) _buildBookingFields() else _buildOrderFields(),
                        const SizedBox(height: 24),
                        SizedBox(
                          height: 52,
                          child: ElevatedButton(
                            onPressed: _isSubmitting ? null : _submit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
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
                                    booking ? 'Submit booking' : 'Submit order',
                                    style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                    ),
                                  ),
                          ),
                        ),
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

  Widget _dropdown({
    required String label,
    required String value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: _decoration(label, Icons.category_outlined),
      items: items,
      onChanged: onChanged,
    );
  }

  Widget _dateTile(String label, DateTime date, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: _decoration(label, Icons.calendar_today_outlined),
        child: Text(
          DateFormat('dd MMM yyyy').format(date),
          style: GoogleFonts.poppins(fontSize: 14),
        ),
      ),
    );
  }

  InputDecoration _decoration(String label, IconData icon) {
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

  Widget _field(
    TextEditingController controller,
    String label,
    IconData icon, {
    bool required = true,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.text,
      validator: required
          ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null
          : null,
      style: GoogleFonts.poppins(fontSize: 14),
      decoration: _decoration(label, icon),
    );
  }

  Widget _idField(
    TextEditingController controller,
    String label, [
    IconData icon = Icons.tag_outlined,
  ]) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      validator: (v) {
        final n = int.tryParse(v?.trim() ?? '');
        if (n == null || n <= 0) return 'Required';
        return null;
      },
      style: GoogleFonts.poppins(fontSize: 14),
      decoration: _decoration(label, icon),
    );
  }

  Widget _optionalIdField(TextEditingController controller, String label) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      validator: (v) {
        final t = v?.trim() ?? '';
        if (t.isEmpty) return null;
        if (int.tryParse(t) == null) return 'Invalid ID';
        return null;
      },
      style: GoogleFonts.poppins(fontSize: 14),
      decoration: _decoration(label, Icons.tag_outlined),
    );
  }

  Widget _moneyField(
    TextEditingController controller,
    String label, {
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      validator: validator ??
          (v) {
            final n = double.tryParse(v?.trim() ?? '');
            if (n == null || n <= 0) return 'Required';
            return null;
          },
      style: GoogleFonts.poppins(fontSize: 14),
      decoration: _decoration(label, Icons.payments_outlined),
    );
  }
}
