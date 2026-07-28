const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

const shortMonths = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String formatHoursMinutes(int seconds) {
  final totalMinutes = seconds ~/ 60;
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  if (minutes == 0 || hours >= 100) {
    return '${hours}h';
  }
  return '${hours}h ${minutes}m';
}

String formatShortDate(DateTime d) {
  return '${d.day} ${shortMonths[d.month - 1]} ${d.year}';
}

String formatMonthYear(String ym) {
  // ym = 'YYYY-MM'
  final parts = ym.split('-');
  if (parts.length < 2) return ym;
  final year = parts[0];
  final month = int.tryParse(parts[1]);
  if (month == null || month < 1 || month > 12) return ym;
  return '${_months[month - 1]} $year';
}

String formatWeekRange(DateTime weekStart) {
  final weekEnd = weekStart.add(const Duration(days: 6));
  final startStr =
      '${shortMonths[weekStart.month - 1]} ${weekStart.day}';
  final endStr = '${shortMonths[weekEnd.month - 1]} ${weekEnd.day}';
  return '$startStr — $endStr';
}
