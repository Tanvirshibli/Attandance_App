import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/theme.dart';
import '../services/endpoint_config_service.dart';
import 'login_screen.dart';

class ServerBootstrapScreen extends StatefulWidget {
  const ServerBootstrapScreen({super.key});

  @override
  State<ServerBootstrapScreen> createState() => _ServerBootstrapScreenState();
}

class _ServerBootstrapScreenState extends State<ServerBootstrapScreen> {
  final _controller = TextEditingController(
    text: 'http://127.0.0.1:8095',
  );
  final _configService = EndpointConfigService.instance;

  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _saveAndContinue() async {
    final base = _controller.text.trim();
    if (base.isEmpty) {
      setState(() => _error = 'Please enter the ZKTeco server URL.');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await _configService.setBootstrapBaseUrl(base);
      final config = await _configService.refreshConfig();
      if (config == null || config.endpoints.isEmpty) {
        setState(() {
          _error =
              'Could not load app configuration. Check the URL and ensure zkteco-production is running.';
          _isLoading = false;
        });
        return;
      }

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    } catch (error) {
      setState(() {
        _error = 'Connection failed: $error';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.primary, AppColors.primaryDark],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 24),
                Text(
                  'Server Setup',
                  style: GoogleFonts.poppins(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Enter your ZKTeco server address. The app will download all API endpoints from the dashboard — nothing is hardcoded.',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: Colors.white70,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 32),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'ZKTeco Base URL',
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _controller,
                        keyboardType: TextInputType.url,
                        decoration: InputDecoration(
                          hintText: 'http://10.0.2.2:8095',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Local Docker: http://127.0.0.1:8095\n'
                        'Emulator: http://10.0.2.2:8095\n'
                        'Physical device: http://YOUR_PC_LAN_IP:8095',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                          height: 1.4,
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            color: Colors.red.shade700,
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: _isLoading ? null : _saveAndContinue,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                'Connect & Continue',
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
