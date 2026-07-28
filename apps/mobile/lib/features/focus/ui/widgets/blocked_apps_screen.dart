import 'package:flutter/material.dart';
import '../../../../core/design/app_colors.dart';
import '../../../../core/design/app_typography.dart';
import '../../data/app_blocker_channel.dart';
import '../../data/blocked_apps_db.dart';

class BlockedAppsScreen extends StatefulWidget {
  const BlockedAppsScreen({super.key});

  @override
  State<BlockedAppsScreen> createState() => _BlockedAppsScreenState();
}

class _BlockedAppsScreenState extends State<BlockedAppsScreen> with WidgetsBindingObserver {
  final _channel = AppBlockerChannel();
  final _db = BlockedAppsDb();
  final _searchController = TextEditingController();

  List<InstalledApp> _allApps = [];
  Set<String> _selected = {};
  bool _loading = true;
  String _search = '';

  bool _hasOverlay = false;
  bool _hasUsageStats = false;
  bool _waitingForPermission = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _waitingForPermission) {
      _waitingForPermission = false;
      _recheckPermissions();
    }
  }

  Future<void> _recheckPermissions() async {
    final results = await Future.wait([
      _channel.hasOverlayPermission(),
      _channel.hasUsageStatsPermission(),
    ]);
    if (!mounted) return;
    setState(() {
      _hasOverlay = results[0];
      _hasUsageStats = results[1];
    });
  }

  Future<void> _load() async {
    final results = await Future.wait([
      _channel.getInstalledApps(),
      _db.getBlockedApps(),
      _channel.hasOverlayPermission(),
      _channel.hasUsageStatsPermission(),
    ]);
    if (!mounted) return;
    setState(() {
      _allApps = results[0] as List<InstalledApp>;
      _selected = (results[1] as List<String>).toSet();
      _hasOverlay = results[2] as bool;
      _hasUsageStats = results[3] as bool;
      _loading = false;
    });
  }

  Future<void> _save() async {
    await _db.saveBlockedApps(_selected.toList());
    if (mounted) Navigator.of(context).pop(_selected.toList());
  }

  List<InstalledApp> get _filtered {
    if (_search.isEmpty) return _allApps;
    final q = _search.toLowerCase();
    return _allApps
        .where((a) =>
            a.appName.toLowerCase().contains(q) ||
            a.packageName.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textDark),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('Block Apps', style: AppTypography.heading18()),
        actions: [
          TextButton(
            onPressed: _save,
            child: Text(
              'Save',
              style: AppTypography.body15(
                color: AppColors.primaryBlue,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (!_hasOverlay || !_hasUsageStats)
                  _buildPermissionsBanner(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (v) => setState(() => _search = v),
                    style: AppTypography.body15(),
                    decoration: InputDecoration(
                      hintText: 'Search apps...',
                      hintStyle: AppTypography.body15(color: AppColors.textLight),
                      prefixIcon: const Icon(Icons.search, color: AppColors.textMedium, size: 20),
                      filled: true,
                      fillColor: AppColors.greyBgDarker,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Text(
                        '${_selected.length} app(s) selected',
                        style: AppTypography.body13(),
                      ),
                      const Spacer(),
                      if (_selected.isNotEmpty)
                        GestureDetector(
                          onTap: () => setState(() => _selected.clear()),
                          child: Text(
                            'Clear all',
                            style: AppTypography.body13(color: AppColors.primaryBlue),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: ListView.builder(
                    itemCount: _filtered.length,
                    itemBuilder: (context, index) {
                      final app = _filtered[index];
                      final checked = _selected.contains(app.packageName);
                      return _AppTile(
                        app: app,
                        checked: checked,
                        onChanged: (v) {
                          setState(() {
                            if (v) {
                              _selected.add(app.packageName);
                            } else {
                              _selected.remove(app.packageName);
                            }
                          });
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildPermissionsBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.dayStatusBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Permissions required',
            style: AppTypography.body14(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'App blocking needs these permissions to detect and block apps during focus sessions.',
            style: AppTypography.caption12(color: AppColors.textMedium),
          ),
          const SizedBox(height: 12),
          if (!_hasOverlay)
            _PermissionRow(
              label: 'Display over other apps',
              onRequest: () async {
                _waitingForPermission = true;
                await _channel.requestOverlayPermission();
              },
            ),
          if (!_hasUsageStats)
            _PermissionRow(
              label: 'Usage access',
              onRequest: () async {
                _waitingForPermission = true;
                await _channel.requestUsageStatsPermission();
              },
            ),
        ],
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  final String label;
  final VoidCallback onRequest;

  const _PermissionRow({required this.label, required this.onRequest});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, size: 18, color: AppColors.priorityMedText),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: AppTypography.body14())),
          GestureDetector(
            onTap: onRequest,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primaryBlue,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('Grant', style: AppTypography.body13(color: AppColors.white)),
            ),
          ),
        ],
      ),
    );
  }
}

class _AppTile extends StatelessWidget {
  final InstalledApp app;
  final bool checked;
  final ValueChanged<bool> onChanged;

  const _AppTile({
    required this.app,
    required this.checked,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!checked),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            if (app.icon != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.memory(app.icon!, width: 40, height: 40),
              )
            else
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.greyBgDarker,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.android, color: AppColors.textLight),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    app.appName,
                    style: AppTypography.body15(fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    app.packageName,
                    style: AppTypography.caption12(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Checkbox(
              value: checked,
              onChanged: (v) => onChanged(v ?? false),
              activeColor: AppColors.primaryBlue,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ),
          ],
        ),
      ),
    );
  }
}
