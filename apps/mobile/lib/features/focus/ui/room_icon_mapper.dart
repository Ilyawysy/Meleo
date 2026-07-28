import 'package:flutter/material.dart';

import '../models/room_icon.dart';

IconData iconDataOf(RoomIcon? icon) {
  switch (icon) {
    case RoomIcon.book:
      return Icons.menu_book_outlined;
    case RoomIcon.code:
      return Icons.code;
    case RoomIcon.penTool:
      return Icons.edit_outlined;
    case RoomIcon.dumbbell:
      return Icons.fitness_center_outlined;
    case RoomIcon.music:
      return Icons.music_note_outlined;
    case RoomIcon.briefcase:
      return Icons.work_outline;
    case null:
      return Icons.folder_outlined;
  }
}
