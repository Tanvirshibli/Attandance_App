import 'dart:async';

import 'package:flutter/material.dart';
import 'package:animate_do/animate_do.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../config/theme.dart';
import '../screens/main_shell.dart';
import '../services/app_settings_service.dart';
import '../services/auth_service.dart';
import '../services/biometric_login_service.dart';
import '../services/endpoint_config_service.dart';
import '../services/transaction_ui_service.dart';
import '../services/face_recognition_service.dart';
import '../widgets/voice_input_field.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final AuthService _authService = AuthService();
  final FaceRecognitionService _faceRecognitionService = FaceRecognitionService();
  bool _obscurePassword = true;
  bool _rememberMe = true;
  bool _isLoading = false;

  /// Which biometric sign-in is currently running, if any.
  BiometricLoginMethod? _biometricBusy;

  @override
  void initState() {
    super.initState();
    _loadSavedLoginState();
  }

  Future<void> _loadSavedLoginState() async {
    final savedEmail = await _authService.getSavedEmail();
    final savedPassword = await _authService.getSavedPassword();
    final rememberMe = await _authService.getRememberMe();
    if (!mounted) return;
    setState(() {
      _rememberMe = rememberMe;
      _emailController.text = savedEmail ?? '';
      _passwordController.text = savedPassword ?? '';
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter email and password.')),
      );
      return;
    }

    setState(() => _isLoading = true);
    final result = await TransactionUiService.instance.run(
      () => _authService.login(
        email: email,
        password: password,
        rememberMe: _rememberMe,
      ),
      label: 'Signing in',
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (!result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message ?? 'Authentication failed.')),
      );
      return;
    }

    // Everything after a successful login runs in the background. The token is
    // already stored, so the dashboard can render immediately; waiting on
    // get-my-info here (a 45s timeout) to fill in the header is what made the
    // app feel slow between tapping Sign In and seeing anything.
    unawaited(EndpointConfigService.instance.refreshConfig());
    unawaited(_hydrateProfileInBackground());
    // Face sign-in needs a token to refresh from, and a password login is the
    // only moment the app is allowed to write one.
    if (AppSettingsService.instance.biometricFaceLoginEnabled.value) {
      unawaited(_authService.storeFaceLoginSecrets());
    }

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const MainShell()),
    );
  }

  Future<void> _handleBiometricLogin(BiometricLoginMethod method) async {
    if (_biometricBusy != null) return;

    setState(() => _biometricBusy = method);

    final outcome = await TransactionUiService.instance.run(
      () => switch (method) {
        BiometricLoginMethod.fingerprint =>
          BiometricLoginService.instance.loginWithFingerprint(),
        BiometricLoginMethod.face =>
          BiometricLoginService.instance.loginWithFace(
            _faceRecognitionService,
          ),
      },
      label: switch (method) {
        BiometricLoginMethod.fingerprint => 'Verifying fingerprint',
        BiometricLoginMethod.face => 'Verifying face',
      },
    );

    if (!mounted) return;
    setState(() => _biometricBusy = null);

    if (!outcome.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(outcome.message)),
      );
      return;
    }

    unawaited(EndpointConfigService.instance.refreshConfig());
    unawaited(_hydrateProfileInBackground());

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const MainShell()),
    );
  }

  void _cancelBiometricLogin() {
    BiometricLoginService.instance.cancel();
  }

  /// Passwordless sign-in, offered only when this device actually holds what the
  /// flow needs. Nothing here is required to sign in — the password form stays
  /// the primary path and is never hidden or reordered.
  Widget _buildBiometricSection() {
    final settings = AppSettingsService.instance;
    final fingerprintReady = settings.biometricLoginFingerprint.value &&
        settings.hasBiometricCredential;
    final faceReady = settings.biometricFaceLoginEnabled.value;
    if (!fingerprintReady && !faceReady) return const SizedBox.shrink();

    final busy = _biometricBusy;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(child: Divider(color: AppColors.divider, height: 1)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'or sign in with',
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  color: AppColors.textHint,
                ),
              ),
            ),
            Expanded(child: Divider(color: AppColors.divider, height: 1)),
          ],
        ),
        const SizedBox(height: 14),
        if (fingerprintReady)
          _biometricButton(
            method: BiometricLoginMethod.fingerprint,
            icon: Icons.fingerprint_rounded,
            label: 'fingerprint',
            busy: busy,
          ),
        if (fingerprintReady && faceReady) const SizedBox(height: 10),
        if (faceReady)
          _biometricButton(
            method: BiometricLoginMethod.face,
            icon: Icons.face_retouching_natural_rounded,
            label: 'face',
            busy: busy,
          ),
        if (busy != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: TextButton(
              onPressed: _cancelBiometricLogin,
              child: Text(
                'Cancel',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _biometricButton({
    required BiometricLoginMethod method,
    required IconData icon,
    required String label,
    required BiometricLoginMethod? busy,
  }) {
    final isBusy = busy == method;
    return SizedBox(
      height: 46,
      child: OutlinedButton.icon(
        onPressed: busy != null ? null : () => _handleBiometricLogin(method),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: AppColors.primary.withValues(alpha: 0.4)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        icon: isBusy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(icon, size: 20, color: AppColors.primary),
        label: Text(
          isBusy ? 'Verifying…' : 'Sign in with $label',
          style: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.primary,
          ),
        ),
      ),
    );
  }

  /// Warms the profile cache and the face-registration flag for the screens
  /// that need them.
  ///
  /// Failures are swallowed on purpose: the dashboard loads the profile itself
  /// and falls back gracefully, so a failure here must not stop the user from
  /// reaching it.
  Future<void> _hydrateProfileInBackground() async {
    try {
      final profile = await _authService.getCurrentUserProfile();
      _faceRecognitionService.hydrateRegistration(profile?.faceRegistration);
    } catch (_) {
      // Nothing to do — the dashboard retries on its own.
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: AppColors.darkGradient,
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              children: [
                SizedBox(height: size.height * 0.06),

                // Animated Logo
                FadeInDown(
                  duration: const Duration(milliseconds: 600),
                  child: Container(
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.3),
                          blurRadius: 30,
                          spreadRadius: 0,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: CachedNetworkImage(
                        imageUrl: 'https://peoplespoultry.com/assets/front/img/1730297252134723053.gif',
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          decoration: BoxDecoration(
                            gradient: AppColors.primaryGradient,
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: const Center(
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          decoration: BoxDecoration(
                            gradient: AppColors.primaryGradient,
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: const Icon(
                            Icons.fingerprint_rounded,
                            size: 48,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // App Title
                FadeInDown(
                  delay: const Duration(milliseconds: 200),
                  duration: const Duration(milliseconds: 600),
                  child: Text(
                    'PPHL',
                    style: GoogleFonts.poppins(
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                FadeInDown(
                  delay: const Duration(milliseconds: 300),
                  duration: const Duration(milliseconds: 600),
                  child: Text(
                    'Attendance System',
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      color: Colors.white54,
                      fontWeight: FontWeight.w400,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),

                SizedBox(height: size.height * 0.05),

                // Login Card
                FadeInUp(
                  delay: const Duration(milliseconds: 400),
                  duration: const Duration(milliseconds: 700),
                  child: Container(
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 40,
                          spreadRadius: 0,
                          offset: const Offset(0, 20),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Welcome Back',
                          style: GoogleFonts.poppins(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Sign in to continue',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 28),

                        // Email field
                        Text(
                          'Email Address',
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        VoiceTextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: InputDecoration(
                            prefixIcon: Icon(Icons.email_outlined,
                                color: AppColors.textHint, size: 20),
                            hintText: 'Enter your email',
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Password field
                        Text(
                          'Password',
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          onSubmitted: (_) => _handleLogin(),
                          decoration: InputDecoration(
                            prefixIcon: Icon(Icons.lock_outline_rounded,
                                color: AppColors.textHint, size: 20),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                color: AppColors.textHint,
                                size: 20,
                              ),
                              onPressed: () {
                                setState(() => _obscurePassword = !_obscurePassword);
                              },
                            ),
                            hintText: 'Enter your password',
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Remember me + Forgot
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: Checkbox(
                                    value: _rememberMe,
                                    onChanged: (v) =>
                                        setState(() => _rememberMe = v!),
                                    activeColor: AppColors.primary,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Remember me',
                                  style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                            TextButton(
                              onPressed: () {},
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: Text(
                                'Forgot Password?',
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 28),

                        // Login button
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _handleLogin,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                          Colors.white),
                                    ),
                                  )
                                : Text(
                                    'Sign In',
                                    style: GoogleFonts.poppins(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                          ),
                        ),
                        _buildBiometricSection(),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 30),

                // Footer
                FadeInUp(
                  delay: const Duration(milliseconds: 600),
                  duration: const Duration(milliseconds: 600),
                  child: Text(
                    '© 2026 PPHL. All rights reserved.',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: Colors.white30,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
