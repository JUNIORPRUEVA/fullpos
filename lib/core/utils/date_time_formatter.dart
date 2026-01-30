import 'package:intl/intl.dart';

/// Utilidades para formatear fecha y hora
class DateTimeFormatter {
  DateTimeFormatter._();

  /// Formato simple sin locale específico
  static String formatFullDateTime(DateTime dateTime) {
    // Días de la semana en español
    const weekDays = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
    // Meses en español
    const months = [
      'Ene',
      'Feb',
      'Mar',
      'Abr',
      'May',
      'Jun',
      'Jul',
      'Ago',
      'Sep',
      'Oct',
      'Nov',
      'Dic'
    ];

    final weekDay = weekDays[dateTime.weekday - 1];
    final day = dateTime.day;
    final month = months[dateTime.month - 1];
    final year = dateTime.year;
    
    // Formato 12 horas con AM/PM
    final hour = dateTime.hour > 12 ? dateTime.hour - 12 : (dateTime.hour == 0 ? 12 : dateTime.hour);
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final period = dateTime.hour >= 12 ? 'PM' : 'AM';

    return '$weekDay $day $month $year · $hour:$minute $period';
  }

  /// Solo fecha: "Lun 22 Dic 2025"
  static String formatDate(DateTime dateTime) {
    const weekDays = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
    const months = [
      'Ene',
      'Feb',
      'Mar',
      'Abr',
      'May',
      'Jun',
      'Jul',
      'Ago',
      'Sep',
      'Oct',
      'Nov',
      'Dic'
    ];

    final weekDay = weekDays[dateTime.weekday - 1];
    final day = dateTime.day;
    final month = months[dateTime.month - 1];
    final year = dateTime.year;

    return '$weekDay $day $month $year';
  }

  /// Solo hora: "5:18 PM"
  static String formatTime(DateTime dateTime) {
    final hour = dateTime.hour > 12 ? dateTime.hour - 12 : (dateTime.hour == 0 ? 12 : dateTime.hour);
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final period = dateTime.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  /// Formato corto: "22/12/2025 17:18"
  static String formatShort(DateTime dateTime) {
    return DateFormat('dd/MM/yyyy HH:mm').format(dateTime);
  }
}
