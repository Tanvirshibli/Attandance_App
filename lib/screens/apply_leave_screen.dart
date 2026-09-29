import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../models/leave_type.dart';
import '../services/auth_service.dart';
import '../services/leave_service.dart';
import '../widgets/ui/ui.dart';
import '../widgets/voice_input_field.dart';

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
      backgroundColor: AppColors.canvas,
      body: Column(
        children: [
          const AppHeader(title: 'Apply for Leave'),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(AppSpace.lg),
                    child: AppCard(
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
                          const SizedBox(height: AppSpace.md),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: _dateField(
                                  label: 'Start Date',
                                  value: _startDate,
                                  onTap: () => _pickDate(isStart: true),
                                ),
                              ),
                              const SizedBox(width: AppSpace.sm),
                              Expanded(
                                child: _dateField(
                                  label: 'End Date',
                                  value: _endDate,
                                  onTap: () => _pickDate(isStart: false),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpace.md),
                          _label('Reason'),
                          VoiceTextField(
                            controller: _reasonController,
                            maxLines: 3,
                            decoration: _inputDecoration(hint: 'Enter reason'),
                          ),
                          const SizedBox(height: AppSpace.md),
                          OutlinedButton.icon(
                            onPressed: _pickDocument,
                            icon: const Icon(Icons.attach_file_rounded),
                            label: Text(
                              _documentPath == null
                                  ? 'Attach document (optional)'
                                  : 'Document attached',
                            ),
                          ),
                          const SizedBox(height: AppSpace.lg),
                          SizedBox(
                            height: 50,
                            child: ElevatedButton(
                              onPressed: _isSubmitting ? null : _submit,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.mLeave,
                                shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.md),
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
                                      style: AppType.h3.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
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
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      child: Text(
        text,
        style: AppType.meta.copyWith(
          color: AppColors.inkMuted,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({String? hint}) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: AppColors.surfaceSunk,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
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
      mainAxisSize: MainAxisSize.min,
      children: [
        _label(label),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.sm + 2,
              vertical: AppSpace.sm + 2,
            ),
            decoration: BoxDecoration(
              color: AppColors.surfaceSunk,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value == null
                        ? 'Select date'
                        : DateFormat('dd MMM yyyy').format(value),
                    style: AppType.bodySm.copyWith(
                      color: value == null ? AppColors.inkFaint : AppColors.ink,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                AppIcon(AppIcons.calendar, size: 18),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
