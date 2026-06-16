import 'package:flutter/material.dart';
import 'package:fog_of_war/screens/map_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FogOfWarApp());
}

class FogOfWarApp extends StatelessWidget {
  const FogOfWarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fog of War',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const MapScreen(),
    );
  }
}
