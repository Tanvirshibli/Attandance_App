import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../config/theme.dart';
import '../../models/marketing_models.dart';
import '../../services/auth_service.dart';
import '../../services/marketing_service.dart';
import '../../widgets/api_empty_state.dart';
import '../../widgets/filter_chip_row.dart';
import '../../widgets/gradient_screen_header.dart';
import '../../widgets/section_card.dart';

/// Create follow-up for a party, or list-mode hub for open follow-ups.
class FollowupFormScreen extends StatefulWidget {
  const FollowupFormScreen({
    super.key,
    this.party,
    this.showListMode = false,
  });

  final Party? party;
  final bool showListMode;

  @override
  State<FollowupFormScreen> createState() => _FollowupFormScreenState();
}

class _FollowupFormScreenState extends State<FollowupFormScreen> {
  final MarketingService _service = MarketingService();
  final AuthService _authService = AuthService();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _action = TextEditingController();

  DateTime? _dueDate;
  String _priority = 'medium';
  bool _submitting = false;

  bool _loadingList = false;
  String? _listError;
  List<Followup> _items = const [];
  String _statusFilter = 'All';

  static const _priorities = ['low', 'medium', 'high', 'urgent'];
  static const _statusOptions = [
    'All',
    'open',
    'in_progress',
    'completed',
    'cancelled',
  ];

  bool get _listMode => widget.showListMode || widget.party == null;

  @override
  void initState() {
    super.initState();
    if (_listMode) {
      _loadList();
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _action.dispose();
    super.dispose();
  }

  Future<void> _loadList() async {
    setState(() {
      _loadingList = true;
      _listError = null;
    });
    final profile = await _authService.getCurrentUserProfile();
    final result = await _service.listFollowups(
      employeeId: profile?.canonicalEmployeeId,
      partyId: widget.party?.id,
      status: _statusFilter,
    );
    if (!mounted) return;
    if (!result.success) {
      setState(() {
        _items = const [];
        _listError = result.message ?? 'Could not load follow-ups.';
        _loadingList = false;
      });
      return;
    }
    setState(() {
      _items = result.data ?? const [];
      _loadingList = false;
    });
  }

  Future<void> _pickDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? DateTime.now().add(const Duration(days: 3)),
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _dueDate = picked);
  }

  Future<void> _markCompleted(Followup item) async {
    final noteCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Mark completed',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        content: TextField(
          controller: noteCtrl,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Completion note (optional)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Complete'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final result = await _service.updateFollowup(item.id, {
      'status': 'completed',
      if (noteCtrl.text.trim().isNotEmpty)
        'completion_note': noteCtrl.text.trim(),
    });
    if (!mounted) return;
    if (!result.success) {
      _snack(result.message ?? 'Could not update follow-up.');
      return;
    }
    _snack('Marked completed.');
    _loadList();
  }

  Future<void> _submit() async {
    final party = widget.party;
    if (party == null) {
      _snack('Select a party first.');
      return;
    }
    if (_title.text.trim().isEmpty) {
      _snack('Title is required.');
      return;
    }
    final profile = await _authService.getCurrentUserProfile();
    final employeeId = profile?.canonicalEmployeeId;
    if (employeeId == null || employeeId <= 0) {
      _snack('Employee profile not linked.');
      return;
    }

    setState(() => _submitting = true);
    final payload = <String, dynamic>{
      'party_id': party.id,
      'employee_id': employeeId,
      'title': _title.text.trim(),
      if (_description.text.trim().isNotEmpty)
        'description': _description.text.trim(),
      if (_action.text.trim().isNotEmpty) 'action_type': _action.text.trim(),
      'priority': _priority,
      'status': 'open',
      if (_dueDate != null)
        'due_date': DateFormat('yyyy-MM-dd').format(_dueDate!),
    };

    final result = await _service.createFollowup(payload);
    if (!mounted) return;
    setState(() => _submitting = false);
    if (!result.success) {
      _snack(result.message ?? 'Could not save follow-up.');
      return;
    }
    _snack('Follow-up saved.');
    Navigator.of(context).pop(result.data);
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  InputDecoration _decoration({String? hint}) {
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

  Color _priorityColor(String? p) {
    switch ((p ?? '').toLowerCase()) {
      case 'urgent':
      case 'high':
        return AppColors.error;
      case 'low':
        return AppColors.info;
      default:
        return AppColors.warning;
    }
  }

  Color _statusColor(String? s) {
    switch ((s ?? '').toLowerCase()) {
      case 'completed':
      case 'done':
        return AppColors.success;
      case 'cancelled':
        return AppColors.error;
      case 'in_progress':
        return AppColors.info;
      default:
        return AppColors.warning;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_listMode && widget.party == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: RefreshIndicator(
          onRefresh: _loadList,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              const SliverToBoxAdapter(
                child: GradientScreenHeader(
                  title: 'Follow-ups',
                  subtitle: 'Open actions & reminders',
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: FilterChipRow(
                    options: _statusOptions,
                    selected: _statusFilter,
                    onSelected: (v) {
                      setState(() => _statusFilter = v);
                      _loadList();
                    },
                  ),
                ),
              ),
              if (_loadingList)
                const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_listError != null)
                SliverFillRemaining(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: ApiEmptyState(
                        icon: Icons.error_outline,
                        title: 'Could not load',
                        subtitle: _listError,
                        onRetry: _loadList,
                      ),
                    ),
                  ),
                )
              else if (_items.isEmpty)
                const SliverFillRemaining(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: ApiEmptyState(
                        icon: Icons.event_note_outlined,
                        title: 'No follow-ups',
                        subtitle:
                            'Create follow-ups from a dealer or farm detail page.',
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final item = _items[index];
                        final status = (item.status ?? 'open').toLowerCase();
                        final canComplete = status != 'completed' &&
                            status != 'done' &&
                            status != 'cancelled';
                        return FadeInUp(
                          delay: Duration(milliseconds: 30 * index),
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: SectionCard(
                              child: InkWell(
                                onTap: canComplete
                                    ? () => _markCompleted(item)
                                    : null,
                                borderRadius: BorderRadius.circular(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            item.displayTitle,
                                            style: GoogleFonts.poppins(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: _statusColor(item.status)
                                                .withValues(alpha: 0.12),
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                          child: Text(
                                            item.status ?? 'open',
                                            style: GoogleFonts.poppins(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                              color:
                                                  _statusColor(item.status),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: _priorityColor(item.priority)
                                                .withValues(alpha: 0.12),
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                          child: Text(
                                            item.priority ?? 'medium',
                                            style: GoogleFonts.poppins(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                              color: _priorityColor(
                                                item.priority,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      [
                                        if (item.partyName != null)
                                          item.partyName!,
                                        if (item.dueDate != null)
                                          'Due ${item.dueDate}',
                                        if (item.actionType != null)
                                          item.actionType!,
                                      ].where((e) => e.isNotEmpty).join(' · '),
                                      style: GoogleFonts.poppins(
                                        fontSize: 12,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                    if (item.description != null ||
                                        item.notes != null) ...[
                                      const SizedBox(height: 6),
                                      Text(
                                        item.description ?? item.notes!,
                                        style:
                                            GoogleFonts.poppins(fontSize: 12),
                                      ),
                                    ],
                                    if (canComplete) ...[
                                      const SizedBox(height: 8),
                                      Text(
                                        'Tap to mark completed',
                                        style: GoogleFonts.poppins(
                                          fontSize: 11,
                                          color: AppColors.primary,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                      childCount: _items.length,
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          GradientScreenHeader(
            title: 'New Follow-up',
            subtitle: widget.party?.displayName ?? 'Follow-up',
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              child: SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _label('Title *'),
                    TextField(
                      controller: _title,
                      decoration: _decoration(
                        hint: 'e.g. Call back next week',
                      ),
                    ),
                    const SizedBox(height: 14),
                    _label('Description'),
                    TextField(
                      controller: _description,
                      maxLines: 3,
                      decoration: _decoration(),
                    ),
                    const SizedBox(height: 14),
                    _label('Action type'),
                    TextField(
                      controller: _action,
                      decoration: _decoration(
                        hint: 'e.g. Call, Visit, Sample',
                      ),
                    ),
                    const SizedBox(height: 14),
                    _label('Due date'),
                    InkWell(
                      onTap: _pickDueDate,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _dueDate == null
                                    ? 'Select date'
                                    : DateFormat('dd MMM yyyy')
                                        .format(_dueDate!),
                                style: GoogleFonts.poppins(fontSize: 13),
                              ),
                            ),
                            const Icon(Icons.calendar_today_outlined, size: 18),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _label('Priority'),
                    DropdownButtonFormField<String>(
                      initialValue: _priority,
                      decoration: _decoration(),
                      items: _priorities
                          .map(
                            (p) => DropdownMenuItem(
                              value: p,
                              child: Text(p),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setState(() => _priority = v);
                      },
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _submitting ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.warning,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: _submitting
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                'Save follow-up',
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
}
