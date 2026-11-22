// lib/utils/building_resolver.dart
class BuildingResolver {
  static const Map<String, String> _textPrefixes = {
    'ГУК': 'guk',
    'КФЕН': 'ammosov',
    'КТФ': 'ktf',
    'УЛК': 'ulk',
    'ПИ': 'pi',
    'КИТ': 'kit',
    'ЮНОСТЬ': 'yunost',
    'МАНЕЖ': 'yunost',
    'СТАДИОН': 'yunost',
    'КЛИНИКА': 'clinic',
    'АСЦ': 'guk',
    'УАК': 'ulk',
    'БИБЛ': 'guk',
    'СПОРТЗАЛ': 'yunost',
  };

  static const Map<String, String> _instituteToBuilding = {
    // КФЕН
    'ИМИ': 'ammosov',
    'ИЕН': 'ammosov',
    'ФТИ': 'ammosov',
    'МИ': 'ammosov',

    // КТФ
    'ГИ': 'ktf',
    'ГРФ': 'ktf',
    'ИТИ': 'ktf',
    'АДФ': 'ktf', // Автодорожный
    'С-П': 'ktf', // Строительный

    // ГУК
    'ЮФ': 'guk',
    'ФЛФ': 'guk',
    'ИП': 'guk',
    'ФЭИ': 'guk',
    'ИЯКН': 'guk', // Языки и культура

    // УЛК
    'ИЗФиР': 'ulk',
    'ИФ': 'ulk',

    // ПИ
    'ПИ': 'pi',

    // КИТ
    'КИТ': 'kit',
  };

  static String parseBuildingFromRoom(String rawRoom) {
    final upper = rawRoom.toUpperCase();
    for (final entry in _textPrefixes.entries) {
      if (upper.startsWith(entry.key) || upper.contains(' ${entry.key} ') || upper.contains('(${entry.key})')) {
        return entry.value;
      }
    }
    if (upper.contains('СТАДИОН') && upper.contains('ЮНОСТЬ')) return 'yunost';
    return '';
  }

  static String cleanRoomNumber(String rawRoom) {
    var result = rawRoom.trim();
    final upper = result.toUpperCase();
    for (final key in _textPrefixes.keys) {
      if (upper.startsWith(key)) {
        result = result.substring(key.length).trim();
        break;
      } else if (upper.contains(' $key ')) {
        result = result.replaceAll(key, '').trim();
        break;
      }
    }
    if (result.toUpperCase().startsWith('АУД.')) result = result.substring(4).trim();
    if (result.toUpperCase().startsWith('АУД')) result = result.substring(3).trim();
    result = result.replaceAll(RegExp(r'[\(\)]'), '').trim();
    return result;
  }

  static String getDefaultBuilding(String groupName, String instituteName) {
    for (final entry in _instituteToBuilding.entries) {
      if (instituteName.toUpperCase().contains(entry.key.toUpperCase())) return entry.value;
    }
    final upperGroup = groupName.toUpperCase();
    for (final entry in _instituteToBuilding.entries) {
      if (upperGroup.startsWith(entry.key.toUpperCase())) return entry.value;
    }
    return '';
  }
}