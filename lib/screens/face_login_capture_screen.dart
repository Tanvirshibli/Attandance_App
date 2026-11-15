import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../config/theme.dart';
import '../services/camera_prewarm.dart';
import '../services/face_recognition_service.dart';

/// Front-camera capture and local template match for face sign-in.
///
/// This runs **in the app**, on the same `camera` package the check-in screen
/// uses. The earlier implementation opened the platform camera with
/// `ImagePicker(source: ImageSource.camera)`, which launches an external
/// activity; on Android 11+ that intent is invisible to us unless `<queries>`
/// declares it, and the failure surfaced as an instant, unexplained "no photo
/// captured" on every attempt — while check-in, which never leaves the process,
/// kept working.
///
/// Pops with the matched photo, or null when the user cancels. Verification
/// happens here so the caller only has to open a session for a face that has
/// already matched, keeping the engine work off the sign-in critical path.
class FaceLoginCaptureScreen extends StatefulWidget {
  const FaceLoginCaptureScreen({
    super.key,
    required this.faceService,
    this.maxAttempts = 3,
  });

  final FaceRecognitionService faceService;

  /// Matches the attempt budget the server-side flow used, so a user who
  /// repeatedly fails gets the same "sign in with your password" guidance.
  final int maxAttempts;

  @override
  State<FaceLoginCaptureScreen> createState() => _FaceLoginCaptureScreenState();
}

class _FaceLoginCaptureScreenState extends State<FaceLoginCaptureScreen> {
  CameraController? _controller;
  bool _initializing = true;
  bool _capturing = false;
  int _attempts = 0;
  String? _error;
  String _status = 'Position your face in the oval';

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final status = await Permission.camera.request();
    if (!mounted) return;
    if (!status.isGranted) {
      setState(() {
        _initializing = false;
        _error = 'Camera permission is required for face sign-in. Grant it, or '
            'sign in with your password.';
      });
      return;
    }

    try {
      final cameras = await CameraPrewarm.cameras();
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _initializing = false;
      });
    } catch (error) {
      debugPrint('FaceLoginCaptureScreen: camera failed ($error)');
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = 'The camera could not start. Sign in with your password.';
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _captureAndVerify() async {
    final controller = _controller;
    if (_capturing || controller == null || !controller.value.isInitialized) {
      return;
    }
    setState(() {
      _capturing = true;
      _error = null;
      _status = 'Comparing your face…';
    });

    try {
      final shot = await controller.takePicture();
      final verification = await widget.faceService.verifyFace(File(shot.path));
      if (!mounted) return;

      if (verification.isMatch) {
        setState(() => _status = 'Face matched');
        Navigator.of(context).pop(File(shot.path));
        return;
      }

      _attempts++;
      final exhausted = _attempts >= widget.maxAttempts;
      setState(() {
        _capturing = false;
        _status = 'Position your face in the oval';
        _error = exhausted
            ? 'Your face did not match. Sign in with your password, or try again '
                'in better light.'
            : verification.message;
      });
      // The photo never matched, so it has no reason to stay on disk.
      try {
        await File(shot.path).delete();
      } catch (_) {}
    } catch (error) {
      debugPrint('FaceLoginCaptureScreen: capture failed ($error)');
      if (!mounted) return;
      setState(() {
        _capturing = false;
        _status = 'Position your face in the oval';
        _error = 'The photo could not be taken. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Face sign-in'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: _initializing
                    ? const CircularProgressIndicator(color: Colors.white)
                    : _error != null && _controller == null
                        ? _message(_error!)
                        : _preview(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _status,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  if (_error != null && _controller != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 13,
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _capturing || _controller == null
                          ? null
                          : _captureAndVerify,
                      icon: _capturing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.camera_front_rounded),
                      label: Text(_capturing ? 'Checking…' : 'Capture'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Sign in with password instead'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _preview() {
    final controller = _controller!;
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.biggest.shortestSide * 0.82;
        return SizedBox(
          width: side,
          height: side,
          child: ClipOval(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: controller.value.previewSize?.height ?? side,
                height: controller.value.previewSize?.width ?? side,
                child: CameraPreview(controller),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _message(String text) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.no_photography_rounded,
            color: AppColors.primary,
            size: 44,
          ),
          const SizedBox(height: 14),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
