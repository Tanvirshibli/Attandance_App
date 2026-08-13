import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../config/theme.dart';
import '../models/dealer_list_models.dart';
import '../models/sales_booking_post_models.dart';
import '../services/auth_service.dart';
import '../services/payment_service.dart';
import '../services/sales_service.dart';
import '../widgets/gradient_screen_header.dart';
import '../widgets/searchable_select_field.dart';
import '../widgets/section_card.dart';

class _LineDraft {
  _LineDraft()
      : price = TextEditingController(),
        qty = TextEditingController(),
        note = TextEditingController(),
        mrp = TextEditingController();

  BookingFormProductPrice? feedProduct;
  BookingFormChicksProduct? chicksProduct;
  final TextEditingController price;
  final TextEditingController qty;
  final TextEditingController note;
  final TextEditingController mrp;

  double get qtyValue => double.tryParse(qty.text.trim()) ?? 0;
  double get priceValue => double.tryParse(price.text.trim()) ?? 0;
  double get lineTotal => qtyValue * priceValue;

  void dispose() {
    price.dispose();
    qty.dispose();
    note.dispose();
    mrp.dispose();
  }
}

class _DeliveryDraft {
  _DeliveryDraft()
      : name = TextEditingController(),
        phone = TextEditingController(),
        roadNo = TextEditingController(),
        address = TextEditingController(),
        productDetails = TextEditingController();

  final TextEditingController name;
  final TextEditingController phone;
  final TextEditingController roadNo;
  final TextEditingController address;
  final TextEditingController productDetails;

  void dispose() {
    name.dispose();
    phone.dispose();
    roadNo.dispose();
    address.dispose();
    productDetails.dispose();
  }

  DeliveryDetailInput toInput() {
    return DeliveryDetailInput(
      name: name.text,
      phone: phone.text,
      roadNo: roadNo.text,
      address: address.text,
      productDetails: productDetails.text,
    );
  }
}

class PostBookingScreen extends StatefulWidget {
  const PostBookingScreen({super.key});

  @override
  State<PostBookingScreen> createState() => _PostBookingScreenState();
}

class _PostBookingScreenState extends State<PostBookingScreen> {
  final SalesService _salesService = SalesService();
  final PaymentService _paymentService = PaymentService();
  final AuthService _authService = AuthService();
  final _formKey = GlobalKey<FormState>();

  static const _discountTypes = ['Discount', 'Flat Discount'];

  String _module = 'feed';
  String _bookingType = 'Sale';
  String _discountType = 'Discount';
  bool _isBookingMoney = false;
  bool _isMultiDelivery = false;
  DateTime _bookingDate = DateTime.now();
  DateTime _invoiceDate = DateTime.now();

  bool _loading = true;
  bool _isSubmitting = false;
  String? _loadError;
  BookingFormData? _formData;
  AllDealerLists? _dealerLists;
  int? _canonicalEmployeeId;
  int? _chicksBookingPersonId;

  BookingFormSector? _bookingPoint;
  BookingFormCategory? _category;
  BookingFormSubCategory? _subCategory;
  BookingFormChildCategory? _childCategory;
  DealerListItem? _dealer;
  BookingFormZone? _zone;
  final _zoneId = TextEditingController();
  final _discount = TextEditingController(text: '0');
  final _advance = TextEditingController(text: '0');
  final _note = TextEditingController(text: 'Created from mobile app');

  final List<_LineDraft> _lines = [_LineDraft()];
  final List<_DeliveryDraft> _deliveries = [_DeliveryDraft()];

  bool get _isFeed => _module == 'feed';

  List<DealerListItem> get _dealers => _dealerLists?.feed ?? const [];

  List<BookingFormProductPrice> get _feedProducts {
    final data = _formData;
    if (data == null) return const [];
    return data.feedProductsFor(
      categoryId: _category?.id,
      subCategoryId: _subCategory?.id,
      childCategoryId: _childCategory?.id,
    );
  }

  double get _linesSum =>
      _lines.fold<double>(0, (sum, line) => sum + line.lineTotal);

  double get _computedTotal {
    var total = _linesSum;
    final discount = double.tryParse(_discount.text.trim()) ?? 0;
    if (_discountType == 'Discount') {
      total *= (1 - discount / 100);
    } else {
      total -= discount;
    }
    if (_isBookingMoney) {
      total -= double.tryParse(_advance.text.trim()) ?? 0;
    }
    return total.roundToDouble();
  }

  @override
  void initState() {
    super.initState();
    _discount.addListener(_onTotalsChanged);
    _advance.addListener(_onTotalsChanged);
    _lines.first.qty.addListener(_onTotalsChanged);
    _lines.first.price.addListener(_onTotalsChanged);
    _loadAll();
  }

  void _onTotalsChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    final profile = await _authService.getCurrentUserProfile();
    final formResult = await _salesService.fetchBookingFormData();
    final dealerResult = await _salesService.fetchAllDealerLists();
    final setupResult = await _paymentService.fetchPaymentSetupData();
    if (!mounted) return;

    final canonical = profile?.canonicalEmployeeId;
    int? chicksPerson;
    if (canonical != null &&
        setupResult.success &&
        setupResult.data != null) {
      for (final employee in setupResult.data!.employees) {
        if (employee.employeeId == canonical) {
          chicksPerson = employee.id;
          break;
        }
      }
    }

    if (!formResult.success || formResult.data == null) {
      setState(() {
        _loading = false;
        _loadError = formResult.message ?? 'Could not load booking form data.';
        _canonicalEmployeeId = canonical;
      });
      return;
    }

    setState(() {
      _loading = false;
      _formData = formResult.data;
      _dealerLists = dealerResult.data;
      _canonicalEmployeeId = canonical;
      _chicksBookingPersonId = chicksPerson;
      if (dealerResult.success != true) {
        _loadError = dealerResult.message;
      }
    });
  }

  @override
  void dispose() {
    _discount.removeListener(_onTotalsChanged);
    _advance.removeListener(_onTotalsChanged);
    _zoneId.dispose();
    _discount.dispose();
    _advance.dispose();
    _note.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    for (final row in _deliveries) {
      row.dispose();
    }
    super.dispose();
  }

  void _switchModule(String? value) {
    if (value == null || value == _module) return;
    setState(() {
      _module = value;
      _bookingPoint = null;
      _category = null;
      _subCategory = null;
      _childCategory = null;
      _dealer = null;
      _zone = null;
      _zoneId.clear();
      _isMultiDelivery = false;
      for (final line in _lines) {
        line.dispose();
      }
      _lines
        ..clear()
        ..add(_LineDraft()..qty.addListener(_onTotalsChanged)
          ..price.addListener(_onTotalsChanged));
    });
  }

  void _addLine() {
    setState(() {
      final line = _LineDraft();
      line.qty.addListener(_onTotalsChanged);
      line.price.addListener(_onTotalsChanged);
      _lines.add(line);
    });
  }

  void _removeLine(int index) {
    if (_lines.length <= 1) {
      _snack('Keep at least one item.');
      return;
    }
    setState(() {
      _lines.removeAt(index).dispose();
    });
  }

  void _addDelivery() {
    setState(() => _deliveries.add(_DeliveryDraft()));
  }

  void _removeDelivery(int index) {
    if (_deliveries.length <= 1) return;
    setState(() => _deliveries.removeAt(index).dispose());
  }

  Future<void> _pickDate({required bool booking}) async {
    final initial = booking ? _bookingDate : _invoiceDate;
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
        if (_invoiceDate.isBefore(_bookingDate)) {
          _invoiceDate = _bookingDate;
        }
      } else {
        _invoiceDate = picked;
      }
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final data = _formData;
    if (data == null) {
      _snack('Form data is not loaded.');
      return;
    }
    final bookingPerson = _isFeed
        ? _canonicalEmployeeId
        : (_chicksBookingPersonId ?? _canonicalEmployeeId);
    if (bookingPerson == null || bookingPerson <= 0) {
      _snack('Please login again.');
      return;
    }
    if (_dealer == null) {
      _snack('Select a dealer.');
      return;
    }
    if (_bookingPoint == null) {
      _snack('Please select sector!');
      return;
    }
    if (_invoiceDate.isBefore(
      DateTime(_bookingDate.year, _bookingDate.month, _bookingDate.day),
    )) {
      _snack('Invoice Date cannot be earlier than Booking Date!');
      return;
    }

    int categoryId;
    int subCategoryId;
    int childCategoryId;
    if (_isFeed) {
      if (_category == null || _subCategory == null || _childCategory == null) {
        _snack('Select sale category, subcategory, and child category.');
        return;
      }
      categoryId = _category!.id;
      subCategoryId = _subCategory!.id;
      childCategoryId = _childCategory!.id;
    } else {
      final ids = data.resolveChicksCategoryIds();
      if (ids == null) {
        _snack('Could not resolve chicks category IDs from form data.');
        return;
      }
      categoryId = ids.categoryId;
      subCategoryId = ids.subCategoryId;
      childCategoryId = ids.childCategoryId;
    }

    int? cZoneId;
    if (!_isFeed) {
      if (data.chicksZones.isNotEmpty) {
        cZoneId = _zone?.id;
      } else {
        cZoneId = int.tryParse(_zoneId.text.trim());
      }
      if (cZoneId == null || cZoneId <= 0) {
        _snack('Please select Zone first!');
        return;
      }
    }

    final lines = <BookingLineInput>[];
    final usedProducts = <int>{};
    for (final line in _lines) {
      final productId = _isFeed
          ? line.feedProduct?.productId
          : line.chicksProduct?.productId;
      if (productId == null || productId <= 0) {
        _snack('Select a product for every row.');
        return;
      }
      if (usedProducts.contains(productId)) {
        _snack('Select different product!');
        return;
      }
      usedProducts.add(productId);
      if (line.qtyValue <= 0) {
        _snack('Please set Booking Quantity (B Qty) for all items!');
        return;
      }
      if (line.priceValue < 0) {
        _snack('Enter a valid price.');
        return;
      }
      if (_isFeed) {
        final trade = line.feedProduct?.tradePrice ?? 0;
        if (line.priceValue < trade) {
          _snack('Booking price cannot be less than trade price!');
          return;
        }
      }
      final mrp = _isFeed
          ? null
          : (double.tryParse(line.mrp.text.trim()) ?? line.priceValue);
      lines.add(
        BookingLineInput(
          productId: productId,
          unitId: 1,
          qty: line.qtyValue,
          price: line.priceValue,
          note: line.note.text.trim().isEmpty ? null : line.note.text.trim(),
          mrp: mrp,
        ),
      );
    }

    final discount = double.tryParse(_discount.text.trim()) ?? 0;
    final advance = _isBookingMoney
        ? (double.tryParse(_advance.text.trim()) ?? 0)
        : 0.0;
    final fmt = DateFormat('yyyy-MM-dd');

    setState(() => _isSubmitting = true);
    final result = await _salesService.createBookingPersonBook(
      CreateBookingPersonBookRequest(
        module: _module,
        dealerId: _dealer!.id,
        categoryId: categoryId,
        subCategoryId: subCategoryId,
        childCategoryId: childCategoryId,
        bookingPointId: _bookingPoint!.id,
        bookingPerson: bookingPerson,
        bookingType: _bookingType,
        isBookingMoney: _isBookingMoney,
        isMultiDelivery: !_isFeed && _isMultiDelivery,
        discount: discount,
        discountType: _discountType,
        advanceAmount: advance,
        totalAmount: _computedTotal,
        bookingDate: fmt.format(_bookingDate),
        invoiceDate: fmt.format(_invoiceDate),
        cZoneId: cZoneId,
        note: _note.text.trim(),
        lines: lines,
        deliveryDetails: (!_isFeed && _isMultiDelivery)
            ? _deliveries.map((d) => d.toInput()).toList()
            : const [],
      ),
    );
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

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message, style: GoogleFonts.poppins())),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = _formData;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: GradientScreenHeader(
              title: 'Post booking',
              subtitle: _salesService.useCreateDemo
                  ? 'Demo mode — enable live sales to post to server'
                  : 'Feed / chicks → booking-person-books',
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
                        if (_canonicalEmployeeId != null)
                          Text(
                            'Booking person ID: ${_isFeed ? _canonicalEmployeeId : (_chicksBookingPersonId ?? _canonicalEmployeeId)}',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        if (_loading) ...[
                          const SizedBox(height: 16),
                          const Center(child: CircularProgressIndicator()),
                        ] else if (data == null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _loadError ?? 'Could not load form data.',
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              color: AppColors.error,
                            ),
                          ),
                          TextButton(
                            onPressed: _loadAll,
                            child: const Text('Retry'),
                          ),
                        ] else ...[
                          if (_loadError != null)
                            Text(
                              _loadError!,
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                color: AppColors.warning,
                              ),
                            ),
                          const SizedBox(height: 12),
                          _dropdown(
                            label: 'Module',
                            value: _module,
                            items: const [
                              DropdownMenuItem(value: 'feed', child: Text('Feed')),
                              DropdownMenuItem(
                                value: 'chicks',
                                child: Text('Chicks'),
                              ),
                            ],
                            onChanged: _switchModule,
                          ),
                          const SizedBox(height: 12),
                          if (_isFeed) _feedHeader(data) else _chicksHeader(data),
                          const SizedBox(height: 12),
                          SearchableSelectField<DealerListItem>(
                            label: 'Dealer',
                            icon: Icons.store_outlined,
                            options: _dealers,
                            selected: _dealer,
                            displayString: (d) => d.tradeName,
                            searchText: (d) => d.searchText,
                            subtitleFor: (d) => d.subtitle,
                            onSelected: (d) => setState(() => _dealer = d),
                            validator: (v) => v == null ? 'Select a dealer' : null,
                          ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              'Is Booking Money',
                              style: GoogleFonts.poppins(fontSize: 14),
                            ),
                            value: _isBookingMoney,
                            onChanged: (v) => setState(() {
                              _isBookingMoney = v;
                              if (!v) _advance.text = '0';
                            }),
                          ),
                          _field(_note, 'Note', Icons.notes_outlined, required: false),
                          const SizedBox(height: 16),
                          Text(
                            'Add Items',
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...List.generate(_lines.length, _lineCard),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: _addLine,
                              icon: const Icon(Icons.add),
                              label: const Text('Add Item'),
                            ),
                          ),
                          const SizedBox(height: 8),
                          _dropdown(
                            label: 'Discount Type',
                            value: _discountType,
                            items: _discountTypes
                                .map(
                                  (t) => DropdownMenuItem(value: t, child: Text(t)),
                                )
                                .toList(),
                            onChanged: (v) => setState(
                              () => _discountType = v ?? _discountType,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _money(_discount, 'Discount', allowZero: true),
                          if (_isBookingMoney) ...[
                            const SizedBox(height: 12),
                            _money(_advance, 'Advance Amount', allowZero: true),
                          ],
                          const SizedBox(height: 12),
                          InputDecorator(
                            decoration: _decoration(
                              'Total Amount (৳)',
                              Icons.payments_outlined,
                            ),
                            child: Text(
                              _fmt(_computedTotal),
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
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
                                      'Create',
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

  Widget _feedHeader(BookingFormData data) {
    final subs = data.feedSubsForCategory(_category?.id);
    final children = data.feedChildrenForSub(_subCategory?.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SearchableSelectField<BookingFormSector>(
          label: 'Booking Point',
          icon: Icons.place_outlined,
          options: data.feedSalesPoints,
          selected: _bookingPoint,
          displayString: (s) => s.name,
          searchText: (s) => s.searchText,
          onSelected: (v) => setState(() => _bookingPoint = v),
          validator: (v) => v == null ? 'Please select sector!' : null,
        ),
        const SizedBox(height: 12),
        SearchableSelectField<BookingFormCategory>(
          label: 'Sale Category',
          icon: Icons.category_outlined,
          options: data.feedCategories,
          selected: _category,
          displayString: (c) => c.name,
          searchText: (c) => c.searchText,
          onSelected: (v) => setState(() {
            _category = v;
            _subCategory = null;
            _childCategory = null;
            for (final line in _lines) {
              line.feedProduct = null;
            }
          }),
          validator: (v) => v == null ? 'Required' : null,
        ),
        const SizedBox(height: 12),
        SearchableSelectField<BookingFormSubCategory>(
          key: ValueKey('sub_${_category?.id}_${subs.length}'),
          label: 'SubCategory',
          icon: Icons.account_tree_outlined,
          options: subs,
          selected: _subCategory,
          displayString: (c) => c.name,
          searchText: (c) => c.searchText,
          onSelected: (v) => setState(() {
            _subCategory = v;
            _childCategory = null;
            for (final line in _lines) {
              line.feedProduct = null;
            }
          }),
          validator: (v) => v == null ? 'Required' : null,
        ),
        const SizedBox(height: 12),
        SearchableSelectField<BookingFormChildCategory>(
          key: ValueKey('child_${_subCategory?.id}_${children.length}'),
          label: 'ChildCategory',
          icon: Icons.device_hub_outlined,
          options: children,
          selected: _childCategory,
          displayString: (c) => c.name,
          searchText: (c) => c.searchText,
          onSelected: (v) => setState(() {
            _childCategory = v;
            for (final line in _lines) {
              line.feedProduct = null;
            }
          }),
          validator: (v) => v == null ? 'Required' : null,
        ),
        const SizedBox(height: 12),
        _bookingTypeAndDates(),
      ],
    );
  }

  Widget _chicksHeader(BookingFormData data) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SearchableSelectField<BookingFormSector>(
          label: 'Booking Point',
          icon: Icons.place_outlined,
          options: data.chicksSectors,
          selected: _bookingPoint,
          displayString: (s) => s.name,
          searchText: (s) => s.searchText,
          onSelected: (v) => setState(() {
            _bookingPoint = v;
            for (final line in _lines) {
              line.chicksProduct = null;
            }
          }),
          validator: (v) => v == null ? 'Please select sector!' : null,
        ),
        const SizedBox(height: 12),
        _bookingTypeAndDates(),
        const SizedBox(height: 12),
        if (data.chicksZones.isNotEmpty)
          SearchableSelectField<BookingFormZone>(
            label: 'Zone',
            icon: Icons.map_outlined,
            options: data.chicksZones,
            selected: _zone,
            displayString: (z) => z.name,
            searchText: (z) => z.searchText,
            onSelected: (v) => setState(() => _zone = v),
            validator: (v) => v == null ? 'Please select Zone first!' : null,
          )
        else
          TextFormField(
            controller: _zoneId,
            keyboardType: TextInputType.number,
            validator: (v) {
              final n = int.tryParse(v?.trim() ?? '');
              if (n == null || n <= 0) return 'Zone ID is required';
              return null;
            },
            style: GoogleFonts.poppins(fontSize: 14),
            decoration: _decoration(
              'Zone ID (cZoneId)',
              Icons.map_outlined,
            ).copyWith(
              helperText:
                  'Chicks zone list is not on the mobile form-data API.',
              helperMaxLines: 2,
            ),
          ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            'Is Multiple Delivery',
            style: GoogleFonts.poppins(fontSize: 14),
          ),
          value: _isMultiDelivery,
          onChanged: (v) => setState(() => _isMultiDelivery = v),
        ),
        if (_isMultiDelivery) ...[
          Text(
            'Delivery details',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          const SizedBox(height: 8),
          ...List.generate(_deliveries.length, (index) {
            final row = _deliveries[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    _field(row.name, 'Name', Icons.person_outline, required: false),
                    const SizedBox(height: 8),
                    _field(row.phone, 'Phone', Icons.phone_outlined, required: false),
                    const SizedBox(height: 8),
                    _field(row.roadNo, 'Road Name', Icons.alt_route, required: false),
                    const SizedBox(height: 8),
                    _field(
                      row.address,
                      'Address',
                      Icons.home_outlined,
                      required: false,
                    ),
                    const SizedBox(height: 8),
                    _field(
                      row.productDetails,
                      'P Details',
                      Icons.inventory_2_outlined,
                      required: false,
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        onPressed: () => _removeDelivery(index),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _addDelivery,
              icon: const Icon(Icons.add),
              label: const Text('Add delivery'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _bookingTypeAndDates() {
    return Column(
      children: [
        _dropdown(
          label: 'Booking Type',
          value: _bookingType,
          items: const [
            DropdownMenuItem(value: 'Sale', child: Text('Sale')),
            DropdownMenuItem(value: 'Sample', child: Text('Sample')),
          ],
          onChanged: (v) => setState(() => _bookingType = v ?? _bookingType),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _dateTile(
                'Booking Date',
                _bookingDate,
                () => _pickDate(booking: true),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _dateTile(
                'Invoice Date',
                _invoiceDate,
                () => _pickDate(booking: false),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _lineCard(int index) {
    final line = _lines[index];

    final usedIds = _lines
        .where((l) => l != line)
        .map((l) => _isFeed ? l.feedProduct?.productId : l.chicksProduct?.productId)
        .whereType<int>()
        .toSet();

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  'Item ${index + 1}',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => _removeLine(index),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            if (_isFeed)
              SearchableSelectField<BookingFormProductPrice>(
                key: ValueKey(
                  'fp_${_category?.id}_${_subCategory?.id}_${_childCategory?.id}_$index',
                ),
                label: 'Product',
                icon: Icons.inventory_2_outlined,
                options: _feedProducts
                    .where((p) => !usedIds.contains(p.productId))
                    .toList(),
                selected: line.feedProduct,
                displayString: (p) => p.displayLabel,
                searchText: (p) => p.searchText,
                subtitleFor: (p) => 'Tr ৳${_fmt(p.tradePrice)}',
                onSelected: (p) {
                  if (_dealer == null) {
                    _snack('Select dealer first!');
                    return;
                  }
                  setState(() {
                    line.feedProduct = p;
                    if (p != null) {
                      line.price.text = _fmt(p.tradePrice);
                    }
                  });
                },
                validator: (v) => v == null ? 'Select a product' : null,
              )
            else
              SearchableSelectField<BookingFormChicksProduct>(
                key: ValueKey('cp_${_bookingPoint?.id}_$index'),
                label: 'Product',
                icon: Icons.inventory_2_outlined,
                options: (_formData?.chicksProductsForSector(_bookingPoint?.id) ??
                        const [])
                    .where((p) => !usedIds.contains(p.productId))
                    .toList(),
                selected: line.chicksProduct,
                displayString: (p) => p.displayLabel,
                searchText: (p) => p.searchText,
                onSelected: (p) {
                  final hasZone = (_formData?.chicksZones.isNotEmpty ?? false)
                      ? _zone != null
                      : int.tryParse(_zoneId.text.trim()) != null;
                  if (!hasZone) {
                    _snack('Please select Zone first!');
                    return;
                  }
                  setState(() => line.chicksProduct = p);
                },
                validator: (v) => v == null ? 'Select a product' : null,
              ),
            const SizedBox(height: 8),
            if (_isFeed && line.feedProduct != null)
              Text(
                'MRP / Tr Price ৳${_fmt(line.feedProduct!.tradePrice)}',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _money(
                    line.price,
                    _isFeed ? 'B Price' : 'Sale Price',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _money(line.qty, 'B Qty'),
                ),
              ],
            ),
            if (!_isFeed) ...[
              const SizedBox(height: 8),
              _money(line.mrp, 'MRP', allowZero: true, required: false),
            ],
            const SizedBox(height: 8),
            _field(line.note, 'Note', Icons.notes_outlined, required: false),
            const SizedBox(height: 6),
            Text(
              'Tl Price ৳${_fmt(line.lineTotal)}',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(double value) {
    if (value == value.roundToDouble()) return value.round().toString();
    return value.toStringAsFixed(2);
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
      validator: required
          ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null
          : null,
      style: GoogleFonts.poppins(fontSize: 14),
      decoration: _decoration(label, icon),
    );
  }

  Widget _money(
    TextEditingController controller,
    String label, {
    bool allowZero = false,
    bool required = true,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      validator: (v) {
        final t = v?.trim() ?? '';
        if (t.isEmpty) return required ? 'Required' : null;
        final n = double.tryParse(t);
        if (n == null) return 'Invalid';
        if (!allowZero && n <= 0) return 'Required';
        if (n < 0) return 'Invalid';
        return null;
      },
      style: GoogleFonts.poppins(fontSize: 14),
      decoration: _decoration(label, Icons.payments_outlined),
    );
  }
}
