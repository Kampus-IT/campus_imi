// lib/screens/map_data.dart
// Список корпусов для карты. Новый корпус = запись здесь + файлы
// assets/maps/<id>_f<этаж>.svg и <id>_f<этаж>_nav.json.

class MapBuilding {
  final String id; // префикс файлов в assets/maps/
  final String name;
  final String address;
  final List<int> floors;
  final int previewFloor; // план какого этажа показывать на карточке
  const MapBuilding(this.id, this.name, this.address, this.floors, this.previewFloor);
}

const kMapBuildings = [
  MapBuilding('ammosov', 'Учебный корпус КФЕН', 'ул. Кулаковского, 48', [1, 2, 3, 4, 5, 6, 7], 4),
  MapBuilding('kit', 'Технологический институт', 'ул. Строителей, 8', [1], 1),
  MapBuilding('yunost', 'Спортивный комплекс «Юность»', 'ул. П. Морозова, 1', [1, 2], 2),
];
