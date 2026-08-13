import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../config/theme.dart';
import '../models/dealer_list_models.dart';
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
    ('egg', 'Egg'),
    ('fertilizer', 'Fertilizer'),
    ('liveBird', 'Live Bird'),
    ('cullBird', 'Cull Bird'),
  ];

  static const _saleTypes = ['Cash', 'Credit'];

  String _module = 'egg';
  String _saleType = 'Cash';
  DateTime _invoiceDate = DateTime.now();
  DateTime _dueDate = DateTime.now();

  final _salesPointId = TextEditingController();
  final _companyId = TextEditingController();
  final _totalAmount = TextEditingController();

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
    _productId.dispose();
    _tradePrice.dispose();
    _salePrice.dispose();
    _qty.dispose();
    _unitId.dispose();
    _unitBatchNo.dispose();
    super.dispose();
  }

  Future<void> _pickDate({bool due = false}) async {
    final initial = due ? _dueDate : _invoiceDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 90)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      if (due) {
        _dueDate = picked;
      } else {
        _invoiceDate = picked;
      }
    });
  }

  int? _parseInt(String? v, String label) {
    final n = int.tryParse(v?.trim() ?? '');
    if (n == null || n <= 0) {
      _snack('Enter a valid $label.');
      return null;
    }
    return n;
  }

  double? _parseDouble(String? v, String label) {
    final n = double.tryParse(v?.trim() ?? '');
    if (n == null || n <= 0) {
      _snack('Enter a valid $label.');
      return null;
    }
    return n;
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
      dealerId: dealer.id,
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

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message, style: GoogleFonts.poppins())),
    );
  }

  @override
  Widget build(BuildContext context) {
    final demo = _salesService.useCreateDemo;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: GradientScreenHeader(
              title: 'Post sale',
              subtitle: demo
                  ? 'Demo mode — enable live sales to post to server'
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
                            'Sales person ID: $_salesPersonId',
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
                              .map(
                                (m) => DropdownMenuItem(
                                  value: m.$1,
                                  child: Text(m.$2),
                                ),
                              )
                              .toList(),
                          onChanged: _onModuleChanged,
                        ),
                        const SizedBox(height: 12),
                        _dropdown(
                          label: 'Sale type',
                          value: _saleType,
                          items: _saleTypes
                              .map(
                                (t) => DropdownMenuItem(
                                  value: t,
                                  child: Text(t),
                                ),
                              )
                              .toList(),
                          onChanged: (v) =>
                              setState(() => _saleType = v ?? _saleType),
                        ),
                        const SizedBox(height: 12),
                        _idField(_companyId, 'Company ID', Icons.business_outlined),
                        const SizedBox(height: 12),
                        _dealerSection(),
                        const SizedBox(height: 12),
                        _idField(
                          _salesPointId,
                          'Sales point ID',
                          Icons.place_outlined,
                        ),
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
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _idField(
                          _productId,
                          'Product ID',
                          Icons.inventory_2_outlined,
                        ),
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
                              child: _idField(
                                _unitId,
                                'Unit ID',
                                Icons.straighten_outlined,
                              ),
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
                                    'Submit order',
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

  Widget _dropdown({
    required String label,
    required String value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      key: ValueKey('$label-$value'),
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
