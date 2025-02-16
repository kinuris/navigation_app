import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

void main() async {
  await dotenv.load(fileName: '.env');

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tricymeter',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MapSample(),
    );
  }
}

class MapSample extends StatefulWidget {
  const MapSample({super.key});

  @override
  State<MapSample> createState() => MapSampleState();
}

class MapSampleState extends State<MapSample> {
  final Completer<GoogleMapController> _controller =
      Completer<GoogleMapController>();

  CameraPosition? _kGooglePlex;

  LatLng? _selfLocation;
  LatLng? _destinationLocation;
  double _remainingDistance = 0;

  bool _loadingRoute = false;

  /// A collection of circular overlays displayed on the map.
  /// Contains Circle objects representing areas on the map.
  /// Used for highlighting regions or areas of interest.
  final Set<Circle> _circles = {};

  /// A collection of markers displayed on the map.
  /// Contains Marker objects representing specific points of interest.
  /// Used for marking locations, destinations, or waypoints.
  final Set<Marker> _markers = {};

  /// A collection of polylines displayed on the map.
  /// Contains Polyline objects representing paths or routes.
  /// Used for drawing lines connecting different points on the map.
  final Set<Polyline> _polylines = {};

  List<LatLng> _coords = [];
  List<bool> _buttonState = [true, false];

  @override
  void initState() {
    super.initState();

    () async {
      final position = await _determinePosition();
      _selfLocation = LatLng(position.latitude, position.longitude);

      setState(() {
        _circles.add(Circle(
          circleId: const CircleId('user-area'),
          center: LatLng(position.latitude, position.longitude),
          radius: 300,
          strokeColor: Colors.blue,
          strokeWidth: 2,
          fillColor: Colors.blue.shade400.withOpacity(0.15),
        ));

        _circles.add(Circle(
          circleId: const CircleId('user-location'),
          center: LatLng(position.latitude, position.longitude),
          radius: 12,
          strokeColor: Colors.blue.shade200,
          strokeWidth: 1,
          fillColor: Colors.blue.shade700,
        ));

        _kGooglePlex = CameraPosition(
          target: LatLng(position.latitude, position.longitude),
          zoom: 16,
        );
      });

      final positionStream = await _getLocationStream();

      positionStream.listen((event) {
        setState(() {
          _selfLocation = LatLng(event.latitude, event.longitude);
          _remainingDistance = remainingDistance(
            _selfLocation!,
            _coords,
          );

          _circles.add(Circle(
            circleId: const CircleId('user-area'),
            center: LatLng(event.latitude, event.longitude),
            radius: 300,
            strokeColor: Colors.blue,
            strokeWidth: 2,
            fillColor: Colors.blue.shade400.withOpacity(0.15),
          ));

          _circles.add(Circle(
            circleId: const CircleId('user-location'),
            center: LatLng(event.latitude, event.longitude),
            radius: 12,
            strokeColor: Colors.blue.shade200,
            strokeWidth: 1,
            fillColor: Colors.blue.shade700,
          ));
        });
      });
    }();
  }

  double get _distance => calculateAccumulatedDistance(_coords.toList());
  int get _precedingKilometersPrice =>
      _distance <= 2 ? 0 : ((_distance - 2) * 5).round();

  bool get _isStudentOrPwd => !_buttonState[0] && _buttonState[1];

  int get _basePrice => _isStudentOrPwd ? 10 : 15;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // When pressed, the floating action button:
      // 1. Fetches a driving route between current location (_selfLocation) and destination (_destinationLocation)
      // 2. Converts the received route points into a polyline
      // 3. Displays the route on the map as a blue line
      floatingActionButton:
          _destinationLocation == null || _kGooglePlex == null || _loadingRoute
              ? null
              : FloatingActionButton(
                  backgroundColor: Colors.blue.shade600,
                  onPressed: () async {
                    setState(() {
                      _loadingRoute = true;
                    });

                    final polyline = PolylinePoints();

                    // Here we use the flutter_polyline_points package to generate Polylines that can be rendered directly on the map
                    final result = await polyline.getRouteBetweenCoordinates(
                      request: PolylineRequest(
                        origin: PointLatLng(
                          _selfLocation!.latitude,
                          _selfLocation!.longitude,
                        ),
                        destination: PointLatLng(
                          _destinationLocation!.latitude,
                          _destinationLocation!.longitude,
                        ),
                        mode: TravelMode.driving,
                      ),
                      googleApiKey: dotenv.get('API_KEY'),
                    );

                    final points = result.points
                        .map((point) => LatLng(point.latitude, point.longitude))
                        .toList();

                    setState(() {
                      _loadingRoute = false;
                      _remainingDistance = remainingDistance(
                        _selfLocation!,
                        points,
                      );

                      _coords = points;
                      _polylines.add(
                        Polyline(
                          polylineId: const PolylineId('route'),
                          points: points,
                          color: Colors.blue,
                          width: 4,
                        ),
                      );
                    });
                  },
                  child: const Icon(Icons.navigation, color: Colors.white),
                ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      body: _kGooglePlex == null
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : Stack(
              children: [
                GoogleMap(
                  mapType: MapType.hybrid,
                  initialCameraPosition: _kGooglePlex!,
                  onMapCreated: (GoogleMapController controller) {
                    _controller.complete(controller);
                  },
                  circles: _circles,
                  markers: _markers,
                  polylines: _polylines,
                  onTap: (LatLng location) {
                    setState(() {
                      _destinationLocation = location;

                      _markers.add(Marker(
                        markerId: const MarkerId("destination-marker"),
                        position: location,
                        infoWindow: InfoWindow(
                          title: 'Destination',
                          snippet:
                              '${location.latitude}, ${location.longitude}',
                        ),
                        icon: BitmapDescriptor.defaultMarkerWithHue(
                          BitmapDescriptor.hueRed,
                        ),
                      ));
                    });
                  },
                ),
                _polylines.isEmpty
                    ? const SizedBox()
                    : Positioned(
                        top: 64,
                        left: 16,
                        right: 16,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                spreadRadius: 2,
                                blurRadius: 6,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 12),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.end,
                                            children: [
                                              Text(
                                                _distance < 1.5
                                                    ? (_distance * 1000)
                                                        .toStringAsFixed(0)
                                                    : _distance
                                                        .toStringAsFixed(2),
                                                style: const TextStyle(
                                                  fontSize: 32,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.black87,
                                                  height: 1,
                                                ),
                                              ),
                                              const SizedBox(width: 4),
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                    bottom: 4),
                                                child: Text(
                                                  _distance < 1.5 ? "m" : "km",
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    color: Colors.grey.shade700,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            _remainingDistance < 1.5
                                                ? "${(_remainingDistance * 1000).toStringAsFixed(0)} m remaining"
                                                : "${_remainingDistance.toStringAsFixed(2)} km remaining",
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: Colors.grey.shade600,
                                              letterSpacing: 0.3,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    TextButton.icon(
                                      onPressed: () {
                                        setState(() {
                                          _polylines.clear();
                                          _coords.clear();
                                        });
                                      },
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 16, vertical: 12),
                                        backgroundColor: Colors.red.shade50,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                      ),
                                      icon: Icon(Icons.close,
                                          color: Colors.red.shade700, size: 20),
                                      label: Text(
                                        'Clear Route',
                                        style: TextStyle(
                                          color: Colors.red.shade700,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Divider(),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8.0),
                                child: ToggleButtons(
                                  borderRadius: BorderRadius.circular(24),
                                  constraints: const BoxConstraints.expand(
                                      width: 130, height: 40),
                                  isSelected: _buttonState,
                                  selectedColor: Colors.white,
                                  fillColor: Colors.blue.shade600,
                                  color: Colors.grey.shade700,
                                  borderColor: Colors.grey.shade300,
                                  children: const [
                                    Text(
                                      'Regular',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w500),
                                    ),
                                    Text(
                                      'Student/PWD',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w500),
                                    ),
                                  ],
                                  onPressed: (index) => setState(() {
                                    _buttonState = index == 0
                                        ? [true, false]
                                        : [false, true];
                                  }),
                                ),
                              ),
                              Card(
                                elevation: 0,
                                color: Colors.grey.shade100,
                                child: Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Column(
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          const Text('Base Fare:'),
                                          Text('₱$_basePrice',
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w500)),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          const Text('Distance Charge:'),
                                          const Expanded(child: SizedBox()),
                                          IconButton(
                                            icon: const Icon(
                                              Icons.info_outline,
                                              size: 20,
                                            ),
                                            style: const ButtonStyle(
                                              visualDensity:
                                                  VisualDensity.compact,
                                            ),
                                            onPressed: () {
                                              showDialog(
                                                context: context,
                                                builder: (context) =>
                                                    AlertDialog(
                                                  title: const Text(
                                                    'Distance Charge Information',
                                                  ),
                                                  content: const Text(
                                                    'The Distance Charge is every preceding kilometer after 2km multiplied by 5 PHP',
                                                  ),
                                                  actions: [
                                                    TextButton(
                                                      onPressed: () =>
                                                          Navigator.pop(
                                                        context,
                                                      ),
                                                      child: const Text('OK'),
                                                    ),
                                                  ],
                                                ),
                                              );
                                            },
                                          ),
                                          Text(
                                            '₱$_precedingKilometersPrice',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const Divider(height: 24),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          const Text(
                                            'Total Fare:',
                                            style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          Text(
                                            '₱${_basePrice + _precedingKilometersPrice}',
                                            style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                            ],
                          ),
                        ),
                      ),
                if (_loadingRoute)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withOpacity(0.8),
                      child: const Center(
                        child: CircularProgressIndicator(
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

/// Requests and sets up a stream of location updates.
///
/// This function performs the following checks:
/// 1. Verifies if location services are enabled
/// 2. Checks and requests location permissions if needed
/// 3. Handles cases where permissions are permanently denied
///
/// Returns a [Stream] of [Position] objects containing location updates.
///
/// Throws a [Future.error] if:
/// * Location services are disabled
/// * Location permissions are denied
/// * Location permissions are permanently denied
Future<Stream<Position>> _getLocationStream() async {
  bool serviceEnabled;
  LocationPermission permission;

  serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    return Future.error('Location services are disabled.');
  }

  permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) {
      return Future.error('Location permissions are denied');
    }
  }

  if (permission == LocationPermission.deniedForever) {
    // Permissions are denied forever, handle appropriately.
    return Future.error(
      'Location permissions are permanently denied, we cannot request permissions.',
    );
  }

  final geolocator = GeolocatorPlatform.instance;

  return geolocator.getPositionStream();
}

/// Determines the current position of the device.
///
/// This function checks if location services are enabled and requests necessary permissions
/// to access the device's location. It handles various permission scenarios:
///
/// - Checks if location services are enabled on the device
/// - Requests location permission if not already granted
/// - Handles cases where permissions are denied or permanently denied
///
/// Returns a [Future<Position>] containing the device's current location coordinates.
///
/// Throws a [Future.error] if:
/// - Location services are disabled
/// - Location permissions are denied
/// - Location permissions are permanently denied
Future<Position> _determinePosition() async {
  bool serviceEnabled;
  LocationPermission permission;

  serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    return Future.error('Location services are disabled.');
  }

  permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) {
      return Future.error('Location permissions are denied');
    }
  }

  if (permission == LocationPermission.deniedForever) {
    // Permissions are denied forever, handle appropriately.
    return Future.error(
      'Location permissions are permanently denied, we cannot request permissions.',
    );
  }

  return await Geolocator.getCurrentPosition();
}

double calculateDistance(
  double startLat,
  double startLng,
  double endLat,
  double endLng,
) {
  const earthRadius = 6371;

  /// Calculates part of the Haversine formula to find distance between two points on a sphere
  ///
  /// [dLat]: Difference in latitude in radians
  /// [dLng]: Difference in longitude in radians
  /// [startLat]: Starting latitude in degrees
  /// [endLat]: Ending latitude in degrees
  ///
  /// First calculates 'a' using the Haversine formula:
  /// a = sin²(Δφ/2) + cos(φ₁)cos(φ₂)sin²(Δλ/2)
  ///
  /// Then calculates 'c' which is the great circle distance in radians:
  /// c = 2 * atan2(√a, √(1-a))
  ///
  /// This is part of the Haversine formula implementation to calculate
  /// the great-circle distance between two points on a sphere.

  final dLat = _toRadians(endLat - startLat);
  final dLng = _toRadians(endLng - startLng);

  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_toRadians(startLat)) *
          math.cos(_toRadians(endLat)) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);

  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

  return earthRadius * c;
}

double _toRadians(double degree) {
  return degree * math.pi / 180;
}

double calculateAccumulatedDistance(List<LatLng> polyline) {
  double totalDistance = 0.0;

  for (int i = 0; i < polyline.length - 1; i++) {
    final startLat = polyline[i].latitude;
    final startLng = polyline[i].longitude;
    final endLat = polyline[i + 1].latitude;
    final endLng = polyline[i + 1].longitude;

    totalDistance += calculateDistance(startLat, startLng, endLat, endLng);
  }

  return totalDistance;
}

/// Calculates the remaining distance along a polyline from the user's current position
/// to the end of the route.
///
/// Parameters:
/// - [userPos]: The current LatLng position of the user
/// - [polyline]: List of LatLng points representing the route
///
/// Returns:
/// - The remaining distance in kilometers, or 0 if polyline is empty
double remainingDistance(LatLng userPos, List<LatLng> polyline) {
  // Return 0 if polyline is empty
  if (polyline.isEmpty) return 0;

  double minDistance = double.infinity;
  int nearestPointIndex = 0;

  // Find the nearest point on the polyline to the user's position
  // by calculating distance to each polyline point and keeping track
  // of the minimum distance and its index
  for (int i = 0; i < polyline.length; i++) {
    final distance = calculateDistance(
      userPos.latitude,
      userPos.longitude,
      polyline[i].latitude,
      polyline[i].longitude,
    );

    if (distance < minDistance) {
      minDistance = distance;
      nearestPointIndex = i;
    }
  }

  // Calculate the total remaining distance by summing up distances
  // between consecutive points from the nearest point to the end
  double remainingDist = 0;
  for (int i = nearestPointIndex; i < polyline.length - 1; i++) {
    remainingDist += calculateDistance(
      polyline[i].latitude,
      polyline[i].longitude,
      polyline[i + 1].latitude,
      polyline[i + 1].longitude,
    );
  }

  return remainingDist;
}
