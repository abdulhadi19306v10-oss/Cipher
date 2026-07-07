import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';

class QRScannerScreen extends StatefulWidget {
  const QRScannerScreen({super.key});

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  String? myQrCode;
  int? myUserId;
  bool _isProcessing = false; // ponytail: fix BUG-3, prevent double-trigger

  @override
  void initState() {
    super.initState();
    _loadMyQr();
  }

  void _loadMyQr() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      myQrCode = prefs.getString('qr_code') ?? 'Unknown';
      myUserId = prefs.getInt('user_id');
    });
  }

  void _onDetect(BarcodeCapture capture) async {
    if (_isProcessing) return;
    for (final barcode in capture.barcodes) {
      final val = barcode.rawValue;
      if (val != null && val.startsWith('cipher-qr-') && myUserId != null) {
        setState(() => _isProcessing = true);
        try {
          final result = await ApiService.addFriendByQr(myUserId!, val);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(result['success'] ? 'Friend request sent!' : (result['message'] ?? 'Error'))),
            );
            Navigator.pop(context);
          }
        } catch (e) {
          // ponytail: fix — reset on error so scanner isn't permanently frozen
          if (mounted) setState(() => _isProcessing = false);
        }
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Add Friends'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'My QR Code'),
              Tab(text: 'Scan Code'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // My QR Code Tab
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Show this to a friend to add them!', style: TextStyle(fontSize: 16)),
                  const SizedBox(height: 30),
                  if (myQrCode != null)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: QrImageView(
                        data: myQrCode!,
                        version: QrVersions.auto,
                        size: 200.0,
                      ),
                    ),
                  const SizedBox(height: 30),
                  Text('Code: $myQrCode', style: const TextStyle(color: Colors.grey)),
                ],
              ),
            ),
            // Scanner Tab
            MobileScanner(
              onDetect: _onDetect,
            ),
          ],
        ),
      ),
    );
  }
}
