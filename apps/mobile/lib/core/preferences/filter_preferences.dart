import 'package:shared_preferences/shared_preferences.dart';

class FilterPreferences {
  static const String _keyTaskFilterProject = 'task_filter_project';
  static const String _keyTaskFilterGroup = 'task_filter_group';

  /// Сохранить фильтр проекта для задач
  static Future<void> saveTaskProjectFilter(String? projectId) async {
    final prefs = await SharedPreferences.getInstance();
    if (projectId == null) {
      await prefs.remove(_keyTaskFilterProject);
    } else {
      await prefs.setString(_keyTaskFilterProject, projectId);
    }
  }

  /// Загрузить фильтр проекта для задач
  static Future<String?> loadTaskProjectFilter() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyTaskFilterProject);
  }

  /// Сохранить фильтр группы для задач
  static Future<void> saveTaskGroupFilter(String? groupId) async {
    final prefs = await SharedPreferences.getInstance();
    if (groupId == null) {
      await prefs.remove(_keyTaskFilterGroup);
    } else {
      await prefs.setString(_keyTaskFilterGroup, groupId);
    }
  }

  /// Загрузить фильтр группы для задач
  static Future<String?> loadTaskGroupFilter() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyTaskFilterGroup);
  }

  /// Очистить все фильтры (при выходе)
  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyTaskFilterProject);
    await prefs.remove(_keyTaskFilterGroup);
  }
}
