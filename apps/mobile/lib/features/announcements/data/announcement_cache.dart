import 'dart:async';

import '../models/announcement.dart';

class AnnouncementCache {
  AnnouncementCache._();
  static final AnnouncementCache instance = AnnouncementCache._();

  final StreamController<List<Announcement>> _controller =
      StreamController<List<Announcement>>.broadcast();

  List<Announcement> _items = const [];

  List<Announcement> get items => _items;
  Stream<List<Announcement>> get stream => _controller.stream;

  void replaceAll(List<Announcement> announcements) {
    final next = List<Announcement>.from(announcements)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _items = List<Announcement>.unmodifiable(next);
    if (!_controller.isClosed) {
      _controller.add(_items);
    }
  }

  void removeById(String id) {
    if (_items.isEmpty) return;
    _items = List<Announcement>.unmodifiable(
      _items.where((a) => a.id != id),
    );
    if (!_controller.isClosed) {
      _controller.add(_items);
    }
  }

  void reset() {
    _items = const [];
    if (!_controller.isClosed) {
      _controller.add(_items);
    }
  }
}
