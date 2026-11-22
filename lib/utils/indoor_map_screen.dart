// lib/screens/map_data.dart
// Список корпусов (блоков) для карты. Новый блок = запись здесь + файлы
// assets/maps/<id>_f<этаж>.svg и <id>_f<этаж>_nav.json, затем пересоздать room_index.json.

class MapBuilding {
  final String id; // префикс файлов в assets/maps/
  final String name;
  final String address;
  final List<int> floors;
  final int previewFloor; // план какого этажа показывать на карточке
  final String group; // корпус целиком: у блоков Главного корпуса общий group = 'guk'
  const MapBuilding(this.id, this.name, this.address, this.floors, this.previewFloor, this.group);
}

const kMapBuildings = [
  MapBuilding('ammosov', 'Учебный корпус КФЕН', 'ул. Кулаковского, 48', [1, 2, 3, 4, 5, 6, 7], 4, 'ammosov'),
  MapBuilding('kit', 'Колледж инфраструктурных технологий', 'ул. Строителей, 8', [1], 1, 'kit'),
  MapBuilding('yunost', 'Спортивный комплекс «Юность»', 'ул. П. Морозова, 1', [1, 2], 2, 'yunost'),
  MapBuilding('guk1', 'Главный корпус, блок 1', 'ул. Кулаковского, 42, кабинеты 01–21', [1, 2, 3, 4], 2, 'guk'),
  MapBuilding('guk2', 'Главный корпус, блок 2', 'ул. Кулаковского, 42, кабинеты 18–35', [1, 2, 3, 4], 2, 'guk'),
  MapBuilding('guk3', 'Главный корпус, блок 3', 'ул. Кулаковского, 42, кабинеты 31–49', [1, 2, 3, 4], 3, 'guk'),
];

/// Корпуса для выпадающего списка при создании занятия (значение пишется в lessons.building).
const kMapGroups = {
  'ammosov': 'Учебный корпус КФЕН',
  'kit': 'Колледж инфраструктурных технологий',
  'yunost': 'Спортивный комплекс «Юность»',
  'guk': 'Главный учебный корпус',
};

/// Подсказки в тексте кабинета («КИТ-205», «Юность 103»): подстроки в нижнем регистре.
const kGroupAliases = {
  'ammosov': ['кфен', 'естествен'],
  'kit': ['кит', 'колледж', 'технолог'],
  'yunost': ['юност', 'манеж'],
  'guk': ['гук', 'главн'],
};

MapBuilding? mapBuildingById(String id) {
  for (final b in kMapBuildings) {
    if (b.id == id) return b;
  }
  return null;
}
