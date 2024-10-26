// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class CameraScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  final Position? currentPosition;

  const CameraScreen({
    super.key,
    required this.cameras,
    required this.currentPosition,
  });

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  // Camera controller
  CameraController? _cameraController;

  // State variables
  bool _isCameraInitialized = false;
  bool _isCapturing = false;
  File? _imageFile;
  bool _isPreviewMode = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.dispose();
    super.dispose();
  }

  // Initialize camera
  Future<void> _initializeCamera() async {
    if (widget.cameras.isEmpty) return;

    try {
      final controller = CameraController(
        widget.cameras[0],
        ResolutionPreset.high,
        enableAudio: false,
      );

      await controller.initialize();
      await controller.setFlashMode(FlashMode.auto);

      if (!mounted) return;

      setState(() {
        _cameraController = controller;
        _isCameraInitialized = true;
      });
    } catch (e) {
      debugPrint('Error initializing camera: $e');
    }
  }

  // photo capture and watermarking
  Future<void> _takePhoto(String lat, String lon) async {
    if (_isCapturing) return;

    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      debugPrint('Camera controller not initialized');
      return;
    }

    setState(() => _isCapturing = true);

    try {
      final XFile? rawImage = await controller.takePicture();
      if (rawImage == null) throw Exception('Failed to capture image');

      // Processing the image
      final File imageFile = File(rawImage.path);
      final Uint8List bytes = await imageFile.readAsBytes();
      final img.Image? originalImage = img.decodeImage(bytes);
      if (originalImage == null) throw Exception('Failed to decode image');

      // Adding  location watermark
      img.drawString(
        originalImage,
        'Lat: $lat\n\nlong: $lon',
        font: img.arial24,
        x: originalImage.width - (12 * 55),
        y: originalImage.height - 100,
      );

      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final imagePath = '${directory.path}/photo_$timestamp.png';

      final File savedImage = File(imagePath);
      await savedImage.writeAsBytes(img.encodePng(originalImage));

      if (!mounted) return;

      setState(() {
        _imageFile = savedImage;
        _isPreviewMode = true;
        _isCapturing = false;
      });
    } catch (e) {
      debugPrint('Error in photo capture: $e');
      setState(() => _isCapturing = false);
    }
  }

  // Options to retake, save and share
  void _retakePhoto() {
    if (!mounted) return;
    setState(() {
      _imageFile?.delete();
      _imageFile = null;
      _isPreviewMode = false;
    });
  }

  Future<void> _confirmPhoto() async {
    if (!mounted || _imageFile == null) return;
    await Gal.putImage(_imageFile!.path);
    setState(() => _isPreviewMode = false);
  }

  _sharePhoto() async {
    if (!mounted || _imageFile == null) return;
    await Share.shareXFiles([XFile(_imageFile!.path)]);
  }

  @override
  Widget build(BuildContext context) {
    if (!_isCameraInitialized || _cameraController == null) {
      return const _LoadingView();
    }

    return Scaffold(
      body: SafeArea(
        child: _isPreviewMode && _imageFile != null
            ? _PhotoPreviewView(
                imageFile: _imageFile!,
                onRetake: _retakePhoto,
                onConfirm: _confirmPhoto,
                onShare: _sharePhoto,
              )
            : _CameraView(
                controller: _cameraController!,
                position: widget.currentPosition!,
                isCapturing: _isCapturing,
                onCapture: () => _takePhoto(
                  widget.currentPosition!.latitude.toString(),
                  widget.currentPosition!.longitude.toString(),
                ),
              ),
      ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}

class _PhotoPreviewView extends StatelessWidget {
  final File imageFile;
  final VoidCallback onRetake;
  final VoidCallback onConfirm;
  final VoidCallback onShare;

  const _PhotoPreviewView({
    required this.imageFile,
    required this.onRetake,
    required this.onConfirm,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Container(
            color: Colors.black,
            child: Image.file(
              imageFile,
              fit: BoxFit.contain,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: const BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _ActionButton(
                icon: Icons.refresh,
                label: 'Retake',
                onPressed: onRetake,
              ),
              _ActionButton(
                icon: Icons.check,
                label: 'Save',
                onPressed: onConfirm,
              ),
              _ActionButton(
                icon: Icons.share,
                label: 'Share',
                onPressed: onShare,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CameraView extends StatelessWidget {
  final CameraController controller;
  final Position position;
  final bool isCapturing;
  final VoidCallback onCapture;

  const _CameraView({
    required this.controller,
    required this.position,
    required this.isCapturing,
    required this.onCapture,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        CameraPreview(controller),
        _LocationOverlay(position: position),
        _CaptureButton(
          isCapturing: isCapturing,
          onCapture: onCapture,
        ),
      ],
    );
  }
}

class _LocationOverlay extends StatelessWidget {
  final Position position;

  const _LocationOverlay({required this.position});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 20,
      left: 20,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _LocationText(
              label: 'Lat',
              value: position.latitude.toStringAsFixed(4),
            ),
            const SizedBox(height: 4),
            _LocationText(
              label: 'Long',
              value: position.longitude.toStringAsFixed(4),
            ),
          ],
        ),
      ),
    );
  }
}

class _LocationText extends StatelessWidget {
  final String label;
  final String value;

  const _LocationText({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(color: Colors.white, fontSize: 14),
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          TextSpan(text: value),
        ],
      ),
    );
  }
}

class _CaptureButton extends StatelessWidget {
  final bool isCapturing;
  final VoidCallback onCapture;

  const _CaptureButton({
    required this.isCapturing,
    required this.onCapture,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 20,
      right: 20,
      child: FloatingActionButton(
        onPressed: isCapturing ? null : onCapture,
        backgroundColor:
            isCapturing ? Colors.grey : Theme.of(context).primaryColor,
        child: isCapturing
            ? const CircularProgressIndicator(color: Colors.white)
            : const Icon(Icons.camera_alt, size: 28),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(icon, color: Colors.white, size: 32),
          onPressed: onPressed,
        ),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
