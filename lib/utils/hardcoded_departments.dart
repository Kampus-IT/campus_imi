// lib/utils/hardcoded_departments.dart

const Map<String, String> kDepartmentToBuilding = {
  // КФЕН
  'ИМИ': 'ammosov',
  'ИЕН': 'ammosov',
  'ФТИ': 'ammosov',
  'МИ': 'ammosov',
  'Институт математики': 'ammosov',
  'Институт естественных': 'ammosov',

  // КТФ
  'ГИ': 'ktf',
  'ГРФ': 'ktf',
  'ИТИ': 'ktf',
  'АДФ': 'ktf',
  'С-П': 'ktf',
  'Строительный': 'ktf',

  // ГУК
  'ЮФ': 'guk',
  'ФЛФ': 'guk',
  'ИП': 'guk',
  'ФЭИ': 'guk',
  'ИЯКН': 'guk',
  'Юридический': 'guk',
  'Филологический': 'guk',

  // УЛК
  'ИЗФиР': 'ulk',
  'ИФ': 'ulk',
  'Исторический': 'ulk',

  // ПИ
  'ПИ': 'pi',
  'Педагогический': 'pi',

  // КИТ
  'КИТ': 'kit',
  'Колледж': 'kit',
};

String getBuildingForInstitute(String instituteName) {
  final upperName = instituteName.toUpperCase();
  for (final entry in kDepartmentToBuilding.entries) {
    if (upperName.contains(entry.key.toUpperCase())) {
      return entry.value;
    }
  }
  return ''; // Если не нашли
}