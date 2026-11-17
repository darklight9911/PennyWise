/// Human labels for YYYY-MM-DD dates, without a locale package:
/// "Today", "Yesterday", "Mon 10 Nov", or "Mon 10 Nov 2025" for other years.
library;

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String dayLabel(String localDate, DateTime now) {
  final d = DateTime.parse(localDate);
  final today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(DateTime(d.year, d.month, d.day)).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  final base = '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';
  return d.year == now.year ? base : '$base ${d.year}';
}

/// "November 2026" for a YYYY-MM month.
String monthLabel(String yearMonth) {
  const full = [
    'January', 'February', 'March', 'April', 'May', 'June', //
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  final parts = yearMonth.split('-');
  return '${full[int.parse(parts[1]) - 1]} ${parts[0]}';
}
