import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const AntiCheatingAbsenceApp());
}

class AntiCheatingAbsenceApp extends StatelessWidget {
  const AntiCheatingAbsenceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Absensi Anti-Curang',
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
      ),
      home: const AttendanceScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  final String scriptUrl = 'https://script.google.com/macros/s/AKfycbzHaqldRMQHCY8iThFxkaAmKup_BQdBkc4T_18AsTFFWBpURkFJCrJ6n2Q1oK0QHKfj/exec';

  final double targetLatitude = -7.4243;  
  final double targetLongitude = 109.2301;
  final double maxRadiusMeters = 50.0;     

  String _statusMessage = 'Siap melakukan absensi';
  bool _isLoading = false;
  File? _capturedImage;
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<Position?> _validateLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showError('GPS/Lokasi perangkat belum aktif.');
      return null;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _showError('Izin lokasi ditolak.');
        return null;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      _showError('Izin lokasi ditolak permanen. Aktifkan di Pengaturan HP.');
      return null;
    }

    Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    if (position.isMocked) {
      _showError('Kecurangan terdeteksi! Anda menggunakan Fake GPS / Mock Location.');
      return null;
    }

    double distanceInMeters = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      targetLatitude,
      targetLongitude,
    );

    if (distanceInMeters > maxRadiusMeters) {
      _showError('Posisi Anda terlalu jauh (${distanceInMeters.toStringAsFixed(1)}m dari lokasi). Maksimal ${maxRadiusMeters}m.');
      return null;
    }

    return position;
  }

  Future<File?> _takeLivePhoto() async {
    final XFile? photo = await _picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.front,
      imageQuality: 40,
    );

    if (photo != null) {
      return File(photo.path);
    }
    return null;
  }

  Future<void> _processAttendance() async {
    String userName = _nameController.text.trim();
    if (userName.isEmpty) {
      _showError('Isi Nama / User ID terlebih dahulu.');
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = 'Memeriksa lokasi & indikator keamanan...';
    });

    Position? position = await _validateLocation();
    if (position == null) {
      setState(() => _isLoading = false);
      return;
    }

    setState(() {
      _statusMessage = 'Lokasi valid! Silakan ambil foto wajah...';
    });

    File? image = await _takeLivePhoto();
    if (image == null) {
      _showError('Absensi dibatalkan: Foto wajah diperlukan.');
      setState(() => _isLoading = false);
      return;
    }

    setState(() {
      _capturedImage = image;
      _statusMessage = 'Mengirim data ke Google Sheet...';
    });

    try {
      List<int> imageBytes = await image.readAsBytes();
      String base64Image = base64Encode(imageBytes);

      final response = await http.post(
        Uri.parse(scriptUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userId': userName,
          'latitude': position.latitude,
          'longitude': position.longitude,
          'gpsStatus': 'VALID (Real GPS)',
          'imageBase64': base64Image,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 302) {
        setState(() {
          _statusMessage = 'BERHASIL ABSEN!\nData & Foto PNG telah dicatat ke Google Sheet.';
        });
      } else {
        _showError('Gagal mengirim data ke server. Kode: ${response.statusCode}');
      }
    } catch (e) {
      _showError('Terjadi kesalahan jaringan: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
    setState(() {
      _statusMessage = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Absensi Anti-Curang'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Nama Lengkap / ID',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
              ),
            ),
            const SizedBox(height: 20),
            if (_capturedImage != null)
              Container(
                height: 220,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.green, width: 2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.file(_capturedImage!, fit: BoxFit.cover),
                ),
              )
            else
              Container(
                height: 180,
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.shield_outlined, size: 60, color: Colors.indigo),
                    SizedBox(height: 10),
                    Text('Anti-Fake GPS + Foto Kamera Wajib'),
                  ],
                ),
              ),
            const SizedBox(height: 20),
            Text(
              _statusMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 25),
            _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ElevatedButton.icon(
                    onPressed: _processAttendance,
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('KIRIM ABSENSI', style: TextStyle(fontSize: 16)),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}
