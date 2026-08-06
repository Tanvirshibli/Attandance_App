import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/theme.dart';
import '../services/app_permissions_service.dart';
import '../widgets/gradient_screen_header.dart';
import '../widgets/section_card.dart';

class PermissionsGateScreen extends StatefulWidget {
  const PermissionsGateScreen({
    super.key,
    required this.onAllGranted,
    this.autoPromptOnFirstOpen = true,
  });

  final VoidCallback onAllGranted;
  final bool autoPromptOnFirstOpen;

  @override
  State<PermissionsGateScreen> createState() => _PermissionsGateScreenState();
}

class _PermissionsGateScreenState extends State<PermissionsGateScreen> {
  final AppPermissionsService _permissions = AppPermissionsService.instance;

  Map<String, bool> _status = {};
  bool _loading = true;
  bool _busy = false;
  bool _permanentlyDenied = false;
  bool _autoPromptDone = false;

  @override
  void initState() {
    super.initState();
    _refreshStatus().then((_) {
      if (widget.autoPromptOnFirstOpen && mounted && !_autoPromptDone) {
        _runAutoPrompts();
      }
    });
  }

  Future<void> _refreshStatus() async {
    setState(() => _loading = true);
    final snapshot = await _permissions.statusSnapshot();
    final blocked = await _permissions.hasPermanentlyDenied();
    if (!mounted) return;
    setState(() {
      _status = snapshot;
      _permanentlyDenied = blocked;
      _loading = false;
    });
    if (snapshot.values.every((g) => g)) {
      widget.onAllGranted();
    }
  }

  Future<void> _runAutoPrompts() async {
    if (_autoPromptDone || !mounted) return;
    _autoPromptDone = true;

    final notificationsOk = _status['notification'] ?? false;
    if (!notificationsOk) {
      final proceed = await _showRationaleDialog(
        title: 'Enable notifications',
        message:
            'PPHL Attendance needs notification permission for geo wake alerts and tracking status updates.',
        confirmLabel: 'Allow notifications',
      );
      if (proceed == true && mounted) {
        await _requestNotifications();
      }
    }

    if (!mounted) return;
    await _refreshStatus();
    if (_status.values.every((g) => g)) return;

    final proceed = await _showRationaleDialog(
      title: 'Enable app permissions',
      message:
          'Camera and location (including background) are required for face check-in, attendance punches, and geo tracking. You cannot use the app without them.',
      confirmLabel: 'Allow permissions',
    );
    if (proceed == true && mounted) {
      await _requestRemaining();
    }
    if (mounted) {
      await _refreshStatus();
    }
  }

  Future<bool?> _showRationaleDialog({
    required String title,
    required String message,
    required String confirmLabel,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(title, style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        content: Text(message, style: GoogleFonts.poppins(fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  Future<void> _requestNotifications() async {
    if (_busy) return;
    setState(() => _busy = true);
    await _permissions.requestNotifications();
    if (mounted) {
      setState(() => _busy = false);
      await _refreshStatus();
    }
  }

  Future<void> _requestRemaining() async {
    if (_busy) return;
    setState(() => _busy = true);
    await _permissions.requestRemainingPermissions();
    if (mounted) {
      setState(() => _busy = false);
      await _refreshStatus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: RefreshIndicator(
          onRefresh: _refreshStatus,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              SliverToBoxAdapter(
                child: GradientScreenHeader(
                  title: 'Permissions required',
                  subtitle:
                      'Grant all permissions below to use PPHL Attendance. The app cannot open until every item is allowed.',
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                sliver: SliverToBoxAdapter(
                  child: SectionCard(
                    child: _loading
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 32),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Permission status',
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 12),
                              ...AppPermissionsService.requiredItems.map(
                                _permissionRow,
                              ),
                              const SizedBox(height: 20),
                              if (_permanentlyDenied) ...[
                                Text(
                                  'One or more permissions were permanently denied. Open app settings and enable them manually, then tap Check again.',
                                  style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    color: AppColors.error,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                OutlinedButton.icon(
                                  onPressed: _busy
                                      ? null
                                      : () => _permissions.openSystemSettings(),
                                  icon: const Icon(Icons.settings_outlined),
                                  label: const Text('Open app settings'),
                                ),
                                const SizedBox(height: 12),
                              ],
                              FilledButton(
                                onPressed: _busy || _permanentlyDenied
                                    ? null
                                    : _requestNotifications,
                                child: _busy
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Text('Enable notifications'),
                              ),
                              const SizedBox(height: 10),
                              FilledButton(
                                onPressed: _busy || _permanentlyDenied
                                    ? null
                                    : _requestRemaining,
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                ),
                                child: const Text('Enable all other permissions'),
                              ),
                              const SizedBox(height: 10),
                              OutlinedButton(
                                onPressed: _busy ? null : _refreshStatus,
                                child: const Text('Check again'),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _permissionRow(AppPermissionItem item) {
    final granted = _status[item.id] ?? false;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            granted ? Icons.check_circle : Icons.cancel,
            color: granted ? AppColors.success : AppColors.error,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.label,
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                Text(
                  item.description,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
