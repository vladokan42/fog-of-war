import 'package:flutter_test/flutter_test.dart';
import 'package:fog_of_war/models/cleared_tile.dart';

void main() {
  test('ClearedTileGrid add and check', () {
    final grid = ClearedTileGrid();
    grid.add(55.7558, 37.6173);
    expect(grid.isCleared(55.7558, 37.6173), true);
    expect(grid.count, 1);
  });
}
