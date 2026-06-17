import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:math';
import 'package:fog_of_war/models/cleared_tile.dart';
import 'package:fog_of_war/services/storage_service.dart';

/// Haversine distance in meters between two lat/lng points
double _haversineDistance(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371000.0;
  final dLat = (lat2 - lat1) * pi / 180;
  final dLng = (lng2 - lng1) * pi / 180;
  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(lat1 * pi / 180) * cos(lat2 * pi / 180) *
      sin(dLng / 2) * sin(dLng / 2);
  final c = 2 * atan2(sqrt(a), sqrt(1 - a));
  return r * c;
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  final StorageService _storage = StorageService();
  
  LatLng? _currentPosition;
  LatLng? _lastTrackedPosition;
  final ClearedTileGrid _clearedGrid = ClearedTileGrid();
  bool _isLoading = true;
  final double _revealRadius = 10.0;
  bool _isTracking = false;
  bool _followMode = false;
  int _tileCount = 0;
  double _totalDistanceMeters = 0.0;

  // Moscow center as default
  static const _defaultCenter = LatLng(55.7558, 37.6173);

  @override
  void initState() {
    super.initState();
    _initMap();
  }

  Future<void> _initMap() async {
    // Load saved data immediately
    final saved = await _storage.loadTiles();
    final grid = ClearedTileGrid();
    grid.fromJson(saved.toJson());
    final savedDistance = await _storage.loadDistance();
    
    if (!mounted) return;
    setState(() {
      _clearedGrid.fromJson(grid.toJson());
      _tileCount = _clearedGrid.count;
      _totalDistanceMeters = savedDistance;
    });

    // Show map immediately, try GPS in background
    setState(() => _isLoading = false);

    // Safety timeout for GPS
    Future.delayed(const Duration(seconds: 10), () {
      if (_isTracking) return;
      if (_currentPosition == null && mounted) {
        _mapController.move(_defaultCenter, 15.0);
      }
    });

    try {
      // Request permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      
      if (permission == LocationPermission.deniedForever || 
          permission == LocationPermission.denied ||
          !await Geolocator.isLocationServiceEnabled()) {
        if (mounted) {
          _mapController.move(_defaultCenter, 15.0);
        }
        return;
      }

      // Try to get position with timeout
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 8),
        ),
      );
      
      if (!mounted) return;
      final latlng = LatLng(pos.latitude, pos.longitude);

      // Сначала обновляем грид, потом камеру — чтобы map move
      // не триггернул ребилд до обновления тумана
      _revealArea(pos.latitude, pos.longitude);
      _mapController.move(latlng, 16.0);
      _startTracking(initialPosition: latlng);

      if (!mounted) return;
      setState(() {
        _currentPosition = latlng;
        _tileCount = _clearedGrid.count;
      });
    } catch (e) {
      // GPS failed, show default location
      if (mounted) {
        _mapController.move(_defaultCenter, 15.0);
      }
    }
  }

  void _startTracking({LatLng? initialPosition}) {
    _isTracking = true;
    _lastTrackedPosition = initialPosition;
    // _currentPosition is set via setState by the caller
    Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen((Position pos) {
      if (!_isTracking || !mounted) return;
      final latlng = LatLng(pos.latitude, pos.longitude);
      
      // Calculate distance from last position
      if (_lastTrackedPosition != null) {
        final dist = _haversineDistance(
          _lastTrackedPosition!.latitude,
          _lastTrackedPosition!.longitude,
          pos.latitude,
          pos.longitude,
        );
        if (dist > 0) {
          _totalDistanceMeters += dist;
          _storage.saveDistance(_totalDistanceMeters);
        }
      }
      _lastTrackedPosition = latlng;

      _revealArea(pos.latitude, pos.longitude);

      setState(() {
        _currentPosition = latlng;
        _tileCount = _clearedGrid.count;
      });
      
      // Only move map if follow mode is on
      if (_followMode) {
        _mapController.move(latlng, _mapController.camera.zoom);
      }
    });
  }

  void _revealArea(double lat, double lng) {
    _clearedGrid.addRadius(lat, lng, _revealRadius);
    _tileCount = _clearedGrid.count;
    _storage.saveTiles(_clearedGrid);
  }

  void _tapToReveal(LatLng point) {
    _revealArea(point.latitude, point.longitude);
    setState(() {});
  }

  @override
  void dispose() {
    _isTracking = false;
    super.dispose();
  }

  String _formatDistance(double meters) {
    if (meters < 1000) {
      return '${meters.toStringAsFixed(0)} м';
    }
    final km = meters / 1000;
    if (km < 10) {
      return '${km.toStringAsFixed(2)} км';
    }
    return '${km.toStringAsFixed(1)} км';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                // Map layer
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _currentPosition ?? _defaultCenter,
                    initialZoom: 16.0,
                    onTap: (tapPosition, point) => _tapToReveal(point),
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.all,
                    ),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.morepara.fog_of_war',
                    ),
                    if (_currentPosition != null)
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: _currentPosition!,
                            width: 80,
                            height: 80,
                            child: const Icon(
                              Icons.my_location,
                              color: Colors.blueAccent,
                              shadows: [Shadow(blurRadius: 10, color: Colors.black)],
                              size: 40,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),

                // Fog overlay — IgnorePointer lets touches pass through to the map
                Positioned.fill(
                  child: IgnorePointer(
                    child: FogOverlay(
                      grid: _clearedGrid,
                      currentPosition: _currentPosition,
                      revealRadius: _revealRadius,
                      mapController: _mapController,
                    ),
                  ),
                ),

                // Top bar — stats
                Positioned(
                  top: MediaQuery.of(context).padding.top + 8,
                  left: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.explore, color: Colors.white70, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Fog of War',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: Colors.white,
                          ),
                        ),
                        const Spacer(),
                        // Distance
                        Icon(Icons.directions_walk,
                          color: Colors.greenAccent.withValues(alpha: 0.7),
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _formatDistance(_totalDistanceMeters),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Tiles
                        Icon(Icons.grid_on,
                          color: Colors.indigoAccent.withValues(alpha: 0.7),
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$_tileCount',
                          style: const TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                        const SizedBox(width: 12),
                        // Follow mode toggle
                        GestureDetector(
                          onTap: () => setState(() => _followMode = !_followMode),
                          child: Icon(
                            _followMode
                                ? Icons.my_location
                                : Icons.location_disabled,
                            size: 20,
                            color: _followMode
                                ? Colors.indigoAccent
                                : Colors.white38,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Help text for new users
                if (_tileCount == 0)
                  Positioned(
                    bottom: MediaQuery.of(context).padding.bottom + 100,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.1),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.touch_app, color: Colors.white54, size: 20),
                            const SizedBox(width: 8),
                            const Text(
                              'Тапни по карте, чтобы открыть',
                              style: TextStyle(color: Colors.white54, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // My Location FAB
                if (_currentPosition != null)
                  Positioned(
                    bottom: MediaQuery.of(context).padding.bottom + 24,
                    right: 16,
                    child: FloatingActionButton.small(
                      heroTag: 'locate',
                      backgroundColor: const Color(0xFF1A1A2E),
                      onPressed: () {
                        _mapController.move(_currentPosition!, 16.0);
                      },
                      child: const Icon(Icons.my_location, size: 20),
                    ),
                  ),
              ],
            ),
    );
  }
}

/// Draws the fog overlay using CustomPainter
class FogOverlay extends StatelessWidget {
  final ClearedTileGrid grid;
  final LatLng? currentPosition;
  final double revealRadius;
  final MapController mapController;

  const FogOverlay({
    super.key,
    required this.grid,
    this.currentPosition,
    required this.revealRadius,
    required this.mapController,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final pos = currentPosition;
        return RepaintBoundary(
          child: CustomPaint(
            painter: _FogPainter(
              grid: grid,
              mapController: mapController,
              size: Size(constraints.maxWidth, constraints.maxHeight),
              currentPosition: pos,
              revealRadius: revealRadius,
            ),
            size: Size(constraints.maxWidth, constraints.maxHeight),
          ),
        );
      },
    );
  }
}

class _FogPainter extends CustomPainter {
  final ClearedTileGrid grid;
  final MapController mapController;
  final Size size;
  final LatLng? currentPosition;
  final double revealRadius;

  _FogPainter({
    required this.grid,
    required this.mapController,
    required this.size,
    this.currentPosition,
    required this.revealRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    // Dark, almost opaque fog — only ~5% of map visible through uncleared areas
    final fogPaint = Paint()
      ..color = const Color(0xF0040612)
      ..style = PaintingStyle.fill;

    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), fogPaint);

    // Clear holes using dstOut blend mode
    final clearPaint = Paint()
      ..blendMode = BlendMode.dstOut
      ..color = Colors.transparent
      ..style = PaintingStyle.fill;

    // Sample cleared tiles visible on screen (performance sampling)
    final projection = mapController.camera;
    final bounds = projection.visibleBounds;
    
    final latStep = (bounds.north - bounds.south) / 60;
    final lngStep = (bounds.east - bounds.west) / 60;

    for (double lat = bounds.south; lat <= bounds.north; lat += latStep) {
      for (double lng = bounds.west; lng <= bounds.east; lng += lngStep) {
        if (grid.isCleared(lat, lng)) {
          final point = projection.latLngToScreenOffset(LatLng(lat, lng));
          canvas.drawCircle(point, 8.0, clearPaint);
        }
      }
    }

    // Clear around current position
    if (currentPosition != null) {
      final pos = projection.latLngToScreenOffset(currentPosition!);
      final radiusPx = _metersToPixels(revealRadius, projection, currentPosition!);
      if (radiusPx > 0) {
        canvas.drawCircle(
          pos,
          radiusPx,
          Paint()
            ..blendMode = BlendMode.dstOut
            ..color = Colors.transparent
            ..style = PaintingStyle.fill,
        );
      }
    }
  }

  double _metersToPixels(double meters, MapCamera cam, LatLng at) {
    final latRad = at.latitude * pi / 180;
    final metersPerDegree = 111320 * cos(latRad).abs();
    if (metersPerDegree < 1) return 100;
    
    final p1 = cam.latLngToScreenOffset(LatLng(at.latitude, at.longitude));
    final p2 = cam.latLngToScreenOffset(
      LatLng(at.latitude + meters / metersPerDegree, at.longitude),
    );
    return (p1.dx - p2.dx).abs();
  }

  @override
  bool shouldRepaint(covariant _FogPainter oldDelegate) => true;
}
