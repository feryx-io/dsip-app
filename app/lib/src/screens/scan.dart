import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../l10n/app_localizations.dart';

/// Pairing codes as QR codes (app plan A6): shown beside the text wherever a code is shown, and scanned with the
/// camera on a phone wherever a code is asked for. The text stays: a desktop has no camera to scan with, and a code
/// can always be typed or pasted.

/// Whether this device scans codes with its camera: phones. Tests set it.
bool Function() scanAvailable = () => Platform.isAndroid || Platform.isIOS;

/// Scan a code that starts with [prefix] (`DSIPJ1-`; `DSIPW`, a welcome code of either form) with the camera; null when the person goes back.
/// Tests set it.
Future<String?> Function(BuildContext context, String prefix) scanCode = (context, prefix) =>
    Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => ScanPage(prefix: prefix), fullscreenDialog: true));

/// [code] as a QR code, on white whatever the theme (a scanner reads dark on light), at [size] logical pixels.
class CodeQr extends StatelessWidget {
  const CodeQr(this.code, {super.key, this.size = 200});
  final String code;
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    label: Strings.of(context).scanQrLabel,
    image: true,
    child: Container(
      color: Colors.white,
      padding: const EdgeInsets.all(8),
      // painted, not QrImageView: that lays out with a LayoutBuilder, which a dialog cannot measure
      child: CustomPaint(
        size: Size.square(size),
        painter: QrPainter(
          data: code,
          version: QrVersions.auto,
          // the codes are base32 in capitals: QR's alphanumeric mode, a smaller symbol
          errorCorrectionLevel: QrErrorCorrectLevel.M,
          eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.black),
          dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Colors.black),
        ),
      ),
    ),
  );
}

/// A button that fills [into] from a scanned code starting with [prefix], shown only where [scanAvailable].
class ScanButton extends StatelessWidget {
  const ScanButton({super.key, required this.prefix, required this.into, this.onScanned});
  final String prefix;
  final TextEditingController into;
  final VoidCallback? onScanned;

  @override
  Widget build(BuildContext context) {
    if (!scanAvailable()) return const SizedBox.shrink();
    return TextButton.icon(
      key: Key('scan-$prefix'),
      icon: const Icon(Icons.qr_code_scanner),
      label: Text(Strings.of(context).scanButton),
      onPressed: () async {
        final code = await scanCode(context, prefix);
        if (code == null) return;
        into.text = code;
        onScanned?.call();
      },
    );
  }
}

/// The camera, until it sees a QR code that starts with [prefix]: that code, returned.
class ScanPage extends StatefulWidget {
  const ScanPage({super.key, required this.prefix});
  final String prefix;

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  final _camera = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool _done = false;

  @override
  void dispose() {
    _camera.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.scanTitle)),
      body: Stack(
        children: [
          MobileScanner(
            controller: _camera,
            onDetect: (capture) {
              if (_done) return;
              // another QR code (or another kind of DSIP code) in view is passed over, not taken
              final code = capture.barcodes
                  .map((b) => b.rawValue?.trim())
                  .whereType<String>()
                  .where((v) => v.toUpperCase().startsWith(widget.prefix))
                  .firstOrNull;
              if (code == null) return;
              _done = true;
              Navigator.of(context).pop(code);
            },
            errorBuilder: (context, error) =>
                Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(s.scanNoCamera(error.errorCode.name)))),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              color: Colors.black54,
              padding: const EdgeInsets.all(16),
              child: Text(s.scanHint, style: const TextStyle(color: Colors.white), textAlign: TextAlign.center),
            ),
          ),
        ],
      ),
    );
  }
}
