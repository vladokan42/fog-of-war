import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fog_of_war/models/cleared_tile.dart';

class StorageService {
  static const _key = 'cleared_tiles';

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
  }
}
