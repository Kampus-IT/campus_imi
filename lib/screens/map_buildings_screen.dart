// lib/screens/map_buildings_screen.dart
// Выбор корпуса. Лицо корпуса — его настоящий план этажа.

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'indoor_map_screen.dart';
import 'map_data.dart';
import 'map_style.dart';

String _floorsText(int n) {
  final m10 = n % 10, m100 = n % 100;
  final word = (m10 == 1 && m100 != 11)
      ? 'этаж'
      : (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14))
      ? 'этажа'
      : 'этажей';
  return '$n $word';
}

class MapBuildingsScreen extends StatelessWidget {
  const MapBuildingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: MapStyle.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        children: [
          const Text(
            'Корпуса',
            style: TextStyle(
              fontSize: 34,
              height: 1.1,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: MapStyle.ink,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Выбери корпус, чтобы открыть план этажа',
            style: TextStyle(fontSize: 15, color: MapStyle.mute),
          ),
          const SizedBox(height: 24),
          for (final b in kMapBuildings) ...[
            _BuildingTile(b),
            const SizedBox(height: 28),
          ],
        ],
      ),
    );
  }
}

class _BuildingTile extends StatelessWidget {
  final MapBuilding b;
  const _BuildingTile(this.b);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => IndoorMapScreen(
            buildingId: b.id,
            buildingName: b.name,
            floors: b.floors,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Container(
              height: 170,
              width: double.infinity,
              color: MapStyle.canvas,
              padding: const EdgeInsets.all(12),
              child: SvgPicture.asset(
                'assets/maps/${b.id}_f${b.previewFloor}.svg',
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) =>
                const Center(child: Icon(Icons.apartment, color: MapStyle.mute, size: 40)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(b.name,
              style: const TextStyle(
                  fontSize: 19, fontWeight: FontWeight.w700, color: MapStyle.ink)),
          const SizedBox(height: 2),
          Text('${b.address}, ${_floorsText(b.floors.length)}',
              style: const TextStyle(fontSize: 14, color: MapStyle.mute)),
        ],
      ),
    );
  }
}
