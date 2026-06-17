import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fog_of_war/models/cleared_tile.dart';

class StorageService {
  static const _key = 'cleared_tiles';
  static const _keyDistance = 'total_distance';
  static const _keyRadius = 'reveal_radius';

  Future<void> saveTiles(ClearedTileGrid grid) async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(grid.toJson());
    await prefs.setString(_key, json);
  }

  Future<ClearedTileGrid> loadTiles() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_key);
    if (json == null || json.isEmpty) return ClearedTileGrid();

    final grid = ClearedTileGrid();
    try {
      final decoded = jsonDecode(json);
      if (decoded is List) {
        grid.fromJson(decoded);
      }
    } catch (_) {}
    return grid;
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    await prefs.remove(_keyDistance);
  }

  Future<void> saveDistance(double meters) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyDistance, meters);
  }

  Future<double> loadDistance() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_keyDistance) ?? 0.0;
  }

  Future<void> saveRadius(double radius) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyRadius, radius);
  }

  Future<double> loadRadius() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_keyRadius) ?? 50.0;
  }
}
