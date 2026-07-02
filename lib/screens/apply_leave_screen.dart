import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../config/theme.dart';
import '../models/leave_type.dart';
import '../services/auth_service.dart';
import '../services/leave_service.dart';
import '../widgets/gradient_screen_header.dart';
import '../widgets/section_card.dart';

class ApplyLeaveScreen extends StatefulWidget {
  const ApplyLeaveScreen({super.key});

  @override
  State<ApplyLeaveScreen> createState() => _ApplyLeaveScreenState();
}

class _ApplyLeaveScreenState extends State<ApplyLeaveScreen> {
  final LeaveService _leaveService = LeaveService();
  final AuthService _authService = AuthService();
  final _reasonController = TextEditingController();

  List<LeaveType> _leaveTypes = const [];
  LeaveType? _selectedType;
  DateTime? _startDate;
  DateTime? _endDate;
  String? _documentPath;
  bool _isLoading = true;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadTypes();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _loadTypes() async {
    final result = await _leaveService.getLeaveTypes();
    if (!mounted) return;
    setState(() {
      _leaveTypes = result.data ?? const [];
      _selectedType = _leaveTypes.isNotEmpty ? _leaveTypes.first : null;
      _isLoading = false;
    });
  }

  Future<void> _pickDate({required bool isStart}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
        if (_endDate != null && _endDate!.isBefore(picked)) {
          _endDate = picked;
        }
      } else {
        _endDate = picked;
      }
    });
  }

  Future<void> _pickDocument() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery);
    if (file != null) {
      setState(() => _documentPath = file.path);
    }
  }

  Future<void> _submit() async {
    final profile = await _authService.getCurrentUserProfile();
    final employeeId = profile?.canonicalEmployeeId;
    if (employeeId == null) {
      _showSnack('Employee profile not linked.');
      return;
    }
    if (_selectedType == null || _startDate == null || _endDate == null) {
      _showSnack('Please fill all required fields.');
      return;
    }
    if (_reasonController.text.trim().isEmpty) {
      _showSnack('Please enter a reason.');
      return;
    }

    setState(() => _isSubmitting = true);
    final fmt = DateFormat('yyyy-MM-dd');
    final result = await _leaveService.applyLeave(
      employeeId: employeeId,
      leaveTypeId: _selectedType!.id,
      startDate: fmt.format(_startDate!),
      endDate: fmt.format(_endDate!),
      reason: _reasonController.text.trim(),
      documentPath: _documentPath,
    );
    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (result.success) {
      _showSnack(result.data ?? 'Leave submitted.');
      Navigator.of(context).pop();
    } else {
      _showSnack(result.message ?? 'Submission failed.');
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          const GradientScreenHeader(title: 'Apply for Leave'),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: SectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _label('Leave Type'),
                          DropdownButtonFormField<LeaveType>(
                            value: _selectedType,
                            decoration: _inputDecoration(),
                            items: _leaveTypes
                                .map(
                                  (t) => DropdownMenuItem(
                                    value: t,
                                    child: Text(t.name),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) => setState(() => _selectedType = v),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: _dateField(
                                  label: 'Start Date',
                                  value: _startDate,
                                  onTap: () => _pickDate(isStart: true),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _dateField(
                                  label: 'End Date',
                                  value: _endDate,
                                  onTap: () => _pickDate(isStart: false),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          _label('Reason'),
                          TextField(
                            controller: _reasonController,
                            maxLines: 3,
                            decoration: _inputDecoration(hint: 'Enter reason'),
                          ),
                          const SizedBox(height: 16),
                          OutlinedButton.icon(
                            onPressed: _pickDocument,
                            icon: const Icon(Icons.attach_file_rounded),
                            label: Text(
                              _documentPath == null
                                  ? 'Attach document (optional)'
                                  : 'Document attached',
                            ),
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            height: 50,
                            child: ElevatedButton(
                              onPressed: _isSubmitting ? null : _submit,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
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
                                      'Submit Leave Request',
                                      style: GoogleFonts.poppins(
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: GoogleFonts.poppins(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({String? hint}) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: AppColors.background,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    );
  }

  Widget _dateField({
    required String label,
    required DateTime? value,
    required VoidCallback onTap,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(label),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value == null
                        ? 'Select date'
                        : DateFormat('dd MMM yyyy').format(value),
                    style: GoogleFonts.poppins(fontSize: 13),
                  ),
                ),
                const Icon(Icons.calendar_today_outlined, size: 18),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
