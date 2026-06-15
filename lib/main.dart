import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'emergency_contacts.dart';
import 'package:flutter/services.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: SplashScreen(),
    );
  }
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen>
    with SingleTickerProviderStateMixin {

  final MapController _mapController = MapController();

  StreamSubscription<Position>? _posStream;
  StreamSubscription<CompassEvent>? _compassStream;

  LatLng? currentLocation;
  LatLng? searchedLocation;

  double heading = 0;
  DateTime? lastMove;

  bool outside = false;
  bool autoSosTriggered = false;

  final LatLng safeZone = const LatLng(17.3850, 78.4867);
  final double safeRadius = 500;

  late AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    await requestPermission();
    startTracking();
    startCompass();

    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
  }

  Future<void> requestPermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return;

    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
  }

  void safeMove(LatLng pos) {
    final now = DateTime.now();

    if (lastMove != null &&
        now.difference(lastMove!) < const Duration(seconds: 2)) return;

    lastMove = now;
    _mapController.move(pos, _mapController.camera.zoom);
  }

  void startTracking() {
    const settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
    );

    _posStream =
        Geolocator.getPositionStream(locationSettings: settings)
            .listen((Position pos) {
          final newPos = LatLng(pos.latitude, pos.longitude);

          setState(() {
            currentLocation = newPos;
          });

          safeMove(newPos);
          checkSafeZone(newPos);
        });
  }

  void startCompass() {
    _compassStream = FlutterCompass.events?.listen((event) {
      if (event.heading == null) return;

      setState(() {
        heading = (event.heading ?? 0) * (pi / 180);
      });
    });
  }

  void checkSafeZone(LatLng user) {
    final distance = Geolocator.distanceBetween(
      user.latitude,
      user.longitude,
      safeZone.latitude,
      safeZone.longitude,
    );

    if (distance > safeRadius && !outside) {
      outside = true;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("⚠️ Outside Safe Zone")),
      );

      if (!autoSosTriggered) {
        autoSosTriggered = true;
        sendAutoSOS();
      }
    } else if (distance <= safeRadius) {
      outside = false;
      autoSosTriggered = false;
    }
  }

  Future<void> sendAutoSOS() async {
    final msg =
        "🚨 AUTO ALERT\n"
        "https://maps.google.com/?q=${currentLocation?.latitude ?? 0},${currentLocation?.longitude ?? 0}";

    final url = Uri.parse(
      "https://wa.me/?text=${Uri.encodeComponent(msg)}",
    );

    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  Future<void> call112() async {
    HapticFeedback.heavyImpact();

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Emergency SOS"),
        content: const Text("Who do you want to contact?"),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await launchUrl(Uri(scheme: 'tel', path: '9154231004'));
            },
            child: const Text("Mom"),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await launchUrl(Uri(scheme: 'tel', path: '9951897405'));
            },=
            child: const Text("Dad"),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await launchUrl(Uri(scheme: 'tel', path: '112'));
            },
            child: const Text("Police 112"),
          ),
        ],
      ),
    );
  }

  Future<void> shareLocation() async {
    Share.share(
      "https://maps.google.com/?q=${currentLocation?.latitude ?? 0},${currentLocation?.longitude ?? 0}",
    );
  }
  Future<void> whatsappSOS() async {
    final msg =
        "🚨 Emergency! I need help.\n"
        "My location:\n"
        "https://maps.google.com/?q=${currentLocation?.latitude ?? 0},${currentLocation?.longitude ?? 0}";

    await launchUrl(
      Uri.parse(
        "https://wa.me/?text=${Uri.encodeComponent(msg)}",
      ),
      mode: LaunchMode.externalApplication,
    );
  }
  Future<void> searchPlace(String query) async {
    if (query.trim().isEmpty) return;

    try {
      final url = Uri.parse(
        "https://photon.komoot.io/api/?q=${Uri.encodeComponent(query)}&limit=1",
      );

      final response = await http
          .get(
        url,
        headers: {
          "User-Agent": "Mozilla/5.0",
          "Accept": "application/json",
        },
      )
          .timeout(const Duration(seconds: 10));

      print("STATUS CODE: ${response.statusCode}");
      print("BODY: ${response.body}");

      if (response.statusCode != 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Search failed (server issue)")),
        );
        return;
      }

      final data = jsonDecode(response.body);

      if (data["features"] == null || data["features"].isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Place not found")),
        );
        return;
      }

      final coords = data["features"][0]["geometry"]["coordinates"];

      final location = LatLng(
        (coords[1] as num).toDouble(),
        (coords[0] as num).toDouble(),
      );

      setState(() {
        searchedLocation = location;
      });

      _mapController.move(location, 15);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Location Found")),
      );

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Network Error: Check internet")),
      );
    }
  }
  void openSearch() {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Search Place"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: "Enter place name",
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              final text = controller.text;
              if (text.isNotEmpty) {
                searchPlace(text);
              }
            },
            child: const Text("Search"),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _posStream?.cancel();
    _compassStream?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fallback = const LatLng(17.3850, 78.4867);

    return Scaffold(
      appBar: AppBar(
        title: const Text("SafePath AI"),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: openSearch,
          ),
          IconButton(
            icon: const Icon(Icons.contacts),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const EmergencyContacts(),
                ),
              );
            },
          ),
        ],
      ),
      body: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: currentLocation ?? fallback,
          initialZoom: 16,
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.example.safepath_ai_fixed',
          ),
      MarkerLayer(
        markers: [
          if (currentLocation != null)
            Marker(
              point: currentLocation!,
              width: 40,
              height: 40,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.blue,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white,
                    width: 3,
                  ),
                ),
              ),
            ),

          if (searchedLocation != null)
            Marker(
              point: searchedLocation!,
              width: 50,
              height: 50,
              child: const Icon(
                Icons.location_on,
                color: Colors.red,
                size: 50,
              ),
            ),
        ],
      ),
      ],
      ),


      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: "myLoc",
            onPressed: () async {
              Position pos = await Geolocator.getCurrentPosition(
                desiredAccuracy: LocationAccuracy.high,
              );

              LatLng newPos = LatLng(pos.latitude, pos.longitude);

              _mapController.move(newPos, 18);

              setState(() {
                currentLocation = newPos;
              });
            },
            child: const Icon(Icons.my_location),
          ),
          const SizedBox(height: 10),

          FloatingActionButton(
            heroTag: "compass",
            onPressed: () => _mapController.rotate(0),
            child: Transform.rotate(
              angle: -heading,
              child: const Icon(Icons.navigation),
            ),
          ),
          const SizedBox(height: 10),

          FloatingActionButton(
            heroTag: "share",
            onPressed: shareLocation,
            child: const Icon(Icons.share),
          ),
          const SizedBox(height: 10),
          FloatingActionButton(
            heroTag: "whatsapp",
            backgroundColor: Colors.green,
            onPressed: whatsappSOS,
            child: const Icon(Icons.message),
          ),

          FloatingActionButton(
            heroTag: "sos",
            backgroundColor: Colors.red,
            onPressed: call112,
            child: const Icon(Icons.emergency),
          ),
        ],
      ),
    );
  }
}