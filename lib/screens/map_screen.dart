import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:math';
import 'package:fog_of_war/models/cleared_tile.dart';
import 'package:fog_of_war/services/storage_service.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  final StorageService _storage = StorageService();
  
  LatLng? _currentPosition;
  final ClearedTileGrid _clearedGrid = ClearedTileGrid();
  bool _isLoading = true;
  double _revealRadius = 50.0;
  bool _isTracking = false;
  int _tileCount = 0;

  // Moscow center as default
  static const _defaultCenter = LatLng(55.7558, 37.6173);

  @override
  void initState() {
    super.initState();
    _initMap();
  }

  Future<void> _initMap() async {
    // Load saved data
    final saved = await _storage.loadTiles();
    final grid = ClearedTileGrid();
    grid.fromJson(saved.toJson());
    
    setState(() {
      _clearedGrid.fromJson(grid.toJson());
      _tileCount = _clearedGrid.count;
    });

    // Get current position
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.deniedForever || permission == LocationPermission.denied) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        return;
      }
    }

    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (!mounted) return;
      
      setState(() {
        _currentPosition = LatLng(pos.latitude, pos.longitude);
        _isLoading = false;
      });

      _mapController.move(_currentPosition!, 16.0);
      _revealArea(pos.latitude, pos.longitude);
      _startTracking();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  void _startTracking() {
    _isTracking = true;
    Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen((Position pos) {
      if (!_isTracking || !mounted) return;
      final latlng = LatLng(pos.latitude, pos.longitude);
      setState(() {
        _currentPosition = latlng;
      });
      _revealArea(pos.latitude, pos.longitude);
      if (_mapController.camera.zoom > 14) {
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

                // Fog overlay
                Positioned.fill(
                  child: FogOverlay(
                    grid: _clearedGrid,
                    currentPosition: _currentPosition,
                    revealRadius: 50,
                    mapController: _mapController,
                  ),
                ),

                // Top bar
                Positioned(
                  top: MediaQuery.of(context).padding.top + 8,
                  left: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(12),
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
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.indigo.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '$_tileCount tiles',
                            style: const TextStyle(color: Colors.white70, fontSize: 11),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (_currentPosition != null)
                          Text(
                            '${_currentPosition!.latitude.toStringAsFixed(4)}, '
                            '${_currentPosition!.longitude.toStringAsFixed(4)}',
                            style: const TextStyle(color: Colors.white38, fontSize: 10),
                          ),
                      ],
                    ),
                  ),
                ),

                // Bottom controls
                Positioned(
                  bottom: MediaQuery.of(context).padding.bottom + 16,
                  right: 16,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FloatingActionButton.small(
                        heroTag: 'reset',
                        onPressed: () async {
                          await _storage.clear();
                          setState(() {
                            _clearedGrid.fromJson([]);
                            _tileCount = 0;
                          });
                        },
                        child: const Icon(Icons.delete_outline),
                      ),
                      const SizedBox(height: 8),
                      FloatingActionButton.small(
                        heroTag: 'radius',
                        onPressed: () => setState(() {
                          _revealRadius = _revealRadius == 50 ? 100 : 
                                        _revealRadius == 100 ? 25 : 50;
                        }),
                        child: Text(
                          '${_revealRadius.toInt()}m',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
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

    final fogPaint = Paint()
      ..color = const Color(0xCC111122)
      ..style = PaintingStyle.fill;

    // Draw full fog
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), fogPaint);

    // Clear circles using blend mode
    final clearPaint = Paint()
      ..blendMode = BlendMode.dstOut
      ..color = Colors.transparent
      ..style = PaintingStyle.fill;

    // Clear around saved tiles (sampled for performance)
    final projection = mapController.camera;
    final bounds = projection.visibleBounds;
    
    final latStep = (bounds.north - bounds.south) / 60;
      final lngStep = (bounds.east - bounds.west) / 60;

      for (double lat = bounds.south; lat <= bounds.north; lat += latStep) {
        for (double lng = bounds.west; lng <= bounds.east; lng += lngStep) {
          if (grid.isCleared(lat, lng)) {
            final point = projection.latLngToScreenOffset(LatLng(lat, lng));
            canvas.drawCircle(
              point,
              8.0,
              clearPaint,
            );
          }
        }
      }

    // Clear around current position
    if (currentPosition != null) {
      final pos = projection.latLngToScreenOffset(currentPosition!);
      final radiusPx = _metersToPixels(revealRadius, projection, currentPosition!);
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

  double _metersToPixels(double meters, MapCamera cam, LatLng at) {
    // Approximate: 1 degree latitude ≈ 111320 meters at equator
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
