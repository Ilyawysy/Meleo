import '../models/room_icon.dart';

const Map<RoomIcon, String> kIconColorMap = {
  RoomIcon.book: '6366F1',      // indigo
  RoomIcon.code: '2563EB',      // blue
  RoomIcon.penTool: '0EA5E9',   // sky
  RoomIcon.dumbbell: '10B981',  // emerald
  RoomIcon.music: 'EC4899',     // pink
  RoomIcon.briefcase: '8B5CF6', // violet
};

String colorForIcon(RoomIcon icon) =>
    '#${kIconColorMap[icon] ?? '6366F1'}';
