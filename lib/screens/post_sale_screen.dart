import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../config/theme.dart';
import '../models/sales_models.dart';
import '../services/auth_service.dart';
import '../services/sales_service.dart';
import '../widgets/gradient_screen_header.dart';
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

  final _customerController = TextEditingController();
  final _amountController = TextEditingController();
  final _productController = TextEditingController();
  final _quantityController = TextEditingController();
  final _notesController = TextEditingController();

  DateTime _saleDate = DateTime.now();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _customerController.dispose();
    _amountController.dispose();
    _productController.dispose();
    _quantityController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _saleDate,
      firstDate: DateTime.now().subtract(const Duration(days: 90)),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _saleDate = picked);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final profile = await _authService.getCurrentUserProfile();
    final employeeId = profile?.canonicalEmployeeId;
    if (employeeId == null) {
      _snack('Please login again.');
      return;
    }

    setState(() => _isSubmitting = true);

    final request = CreateSaleRequest(
      employeeId: employeeId,
      saleDate: DateFormat('yyyy-MM-dd').format(_saleDate),
      amount: double.parse(_amountController.text.trim()),
      customerName: _customerController.text.trim(),
      productName: _productController.text.trim().isEmpty
          ? null
          : _productController.text.trim(),
      quantity: _quantityController.text.trim().isEmpty
          ? null
          : double.tryParse(_quantityController.text.trim()),
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
    );

    final result = await _salesService.createSale(request);
    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (!result.success) {
      _snack(result.message ?? 'Could not submit sale.');
      return;
    }

    _snack(_salesService.useDemoData
        ? 'Demo sale posted successfully.'
        : 'Sale submitted successfully.');
    Navigator.of(context).pop(true);
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message, style: GoogleFonts.poppins())),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          const SliverToBoxAdapter(
            child: GradientScreenHeader(
              title: 'Post sale',
              subtitle: 'Record a new customer sale',
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
                        if (_salesService.useDemoData) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.warning.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'Demo mode — this sale is stored only on this device session.',
                              style: GoogleFonts.poppins(fontSize: 12),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        _field(
                          controller: _customerController,
                          label: 'Customer / outlet',
                          icon: Icons.store_outlined,
                          validator: (v) =>
                              (v == null || v.trim().isEmpty)
                                  ? 'Required'
                                  : null,
                        ),
                        const SizedBox(height: 14),
                        _field(
                          controller: _amountController,
                          label: 'Amount (৳)',
                          icon: Icons.payments_outlined,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          validator: (v) {
                            final n = double.tryParse(v?.trim() ?? '');
                            if (n == null || n <= 0) {
                              return 'Enter a valid amount';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        InkWell(
                          onTap: _pickDate,
                          borderRadius: BorderRadius.circular(12),
                          child: InputDecorator(
                            decoration: _decoration(
                              'Sale date',
                              Icons.calendar_today_outlined,
                            ),
                            child: Text(
                              DateFormat('dd MMM yyyy').format(_saleDate),
                              style: GoogleFonts.poppins(fontSize: 14),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        _field(
                          controller: _productController,
                          label: 'Product (optional)',
                          icon: Icons.inventory_2_outlined,
                        ),
                        const SizedBox(height: 14),
                        _field(
                          controller: _quantityController,
                          label: 'Quantity (optional)',
                          icon: Icons.numbers_rounded,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                        ),
                        const SizedBox(height: 14),
                        _field(
                          controller: _notesController,
                          label: 'Notes (optional)',
                          icon: Icons.notes_outlined,
                          maxLines: 3,
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
                                    'Submit sale',
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

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      validator: validator,
      style: GoogleFonts.poppins(fontSize: 14),
      decoration: _decoration(label, icon),
    );
  }
}
