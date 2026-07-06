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
    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      if (barcode.rawValue != null && barcode.rawValue!.startsWith('cipher-qr-')) {
        // Send add friend request
        // Pause scanner conceptually or handle single trigger
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
