import 'dart:math';
import 'package:latlong2/latlong.dart';

/// Represents a cleared area on the map
class ClearedTile {
  final double lat;
  final double lng;
  final DateTime timestamp;

  ClearedTile({
    required this.lat,
    required this.lng,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'lat': lat,
    'lng': lng,
    'timestamp': timestamp.toIso8601String(),
  };

  factory ClearedTile.fromJson(Map<String, dynamic> json) => ClearedTile(
    lat: (json['lat'] as num).toDouble(),
    lng: (json['lng'] as num).toDouble(),
    timestamp: DateTime.parse(json['timestamp'] as String),
  );
}

/// Simple tile grid for efficient storage
class ClearedTileGrid {
  final double gridSize = 0.0003; // ~30 meters at equator
  final Set<String> _cleared = {};

  String _key(double lat, double lng) {
    final latTile = (lat / gridSize).round();
    final lngTile = (lng / gridSize).round();
    return '$latTile,$lngTile';
  }

  void add(double lat, double lng) => _cleared.add(_key(lat, lng));

  void addRadius(double centerLat, double centerLng, double radiusMeters) {
    final radiusDeg = radiusMeters / 111000.0;
    final steps = (radiusDeg / gridSize).ceil();
    
    for (int dx = -steps; dx <= steps; dx++) {
      for (int dy = -steps; dy <= steps; dy++) {
        final lat = centerLat + dy * gridSize;
        final lng = centerLng + dx * gridSize / cos(centerLat * pi / 180);
        final dist = _haversine(centerLat, centerLng, lat, lng);
        if (dist <= radiusMeters) {
          _cleared.add(_key(lat, lng));
        }
      }
    }
  }

  bool isCleared(double lat, double lng) => _cleared.contains(_key(lat, lng));

  List<Map<String, dynamic>> toJson() =>
      _cleared.map((k) {
        final parts = k.split(',');
        return {'lat': double.parse(parts[0]) * gridSize, 
                'lng': double.parse(parts[1]) * gridSize};
      }).toList();

  void fromJson(List<dynamic> json) {
    _cleared.clear();
    for (final item in json) {
      if (item is Map) {
        add(
          (item['lat'] as num).toDouble(),
          (item['lng'] as num).toDouble(),
        );
      }
    }
  }

  int get count => _cleared.length;

  double _haversine(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLng = (lng2 - lng1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) * cos(lat2 * pi / 180) *
        sin(dLng / 2) * sin(dLng / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return r * c;
  }
}
