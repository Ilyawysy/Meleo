import 'package:flutter/material.dart';

import '../../../core/design/app_colors.dart';
import '../../../core/design/app_typography.dart';
import '../../../core/preferences/settings_preferences.dart';

class SoundScreen extends StatefulWidget {
  const SoundScreen({super.key});

  @override
  State<SoundScreen> createState() => _SoundScreenState();
}

class _SoundScreenState extends State<SoundScreen> {
  String _completionSound = 'chime';
  String _ambientSound = 'none';
  bool _vibrateOnCompletion = true;
  bool _loaded = false;

  static const _completionOptions = ['chime', 'bell', 'digital', 'none'];
  static const _completionLabels = {'chime': 'Chime', 'bell': 'Bell', 'digital': 'Digital', 'none': 'None'};

  static const _ambientOptions = ['rain', 'forest', 'none'];
  static const _ambientLabels = {'rain': 'Rain', 'forest': 'Forest', 'none': 'None'};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cs = await SettingsPreferences.getCompletionSound();
    final as_ = await SettingsPreferences.getAmbientSound();
    final vib = await SettingsPreferences.getVibrateOnCompletion();
    if (!mounted) return;
    setState(() {
      _completionSound = cs;
      _ambientSound = as_;
      _vibrateOnCompletion = vib;
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            // Nav
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _backButton(),
                  Text('Sound & Vibration', style: AppTypography.heading18()),
                  const SizedBox(width: 36),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // COMPLETION SOUND
            _sectionLabel('COMPLETION SOUND'),
            const SizedBox(height: 8),
            _card([
              for (int i = 0; i < _completionOptions.length; i++) ...[
                if (i > 0) _div(),
                _radioRow(
                  label: _completionLabels[_completionOptions[i]]!,
                  isSelected: _completionSound == _completionOptions[i],
                  showPlay: _completionOptions[i] != 'none',
                  onTap: () async {
                    setState(() => _completionSound = _completionOptions[i]);
                    await SettingsPreferences.setCompletionSound(_completionOptions[i]);
                  },
                ),
              ],
            ]),
            const SizedBox(height: 20),

            // AMBIENT SOUNDS
            _sectionLabel('AMBIENT SOUNDS'),
            const SizedBox(height: 8),
            _card([
              for (int i = 0; i < _ambientOptions.length; i++) ...[
                if (i > 0) _div(),
                _radioRow(
                  label: _ambientLabels[_ambientOptions[i]]!,
                  isSelected: _ambientSound == _ambientOptions[i],
                  showPlay: false,
                  onTap: () async {
                    setState(() => _ambientSound = _ambientOptions[i]);
                    await SettingsPreferences.setAmbientSound(_ambientOptions[i]);
                  },
                ),
              ],
            ]),
            const SizedBox(height: 20),

            // VIBRATION
            _sectionLabel('VIBRATION'),
            const SizedBox(height: 8),
            _card([
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Vibrate on completion',
                        style: AppTypography.body15(fontWeight: FontWeight.w500),
                      ),
                    ),
                    _customSwitch(_vibrateOnCompletion, (v) async {
                      setState(() => _vibrateOnCompletion = v);
                      await SettingsPreferences.setVibrateOnCompletion(v);
                    }),
                  ],
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: AppTypography.caption12(color: AppColors.textLight).copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: 0.8,
      ),
    );
  }

  Widget _card(List<Widget> children) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.greyBg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(children: children),
    );
  }

  Widget _div() => Container(height: 1, color: AppColors.divider);

  Widget _radioRow({
    required String label,
    required bool isSelected,
    required bool showPlay,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        color: isSelected ? const Color(0xFFEFF6FF) : null,
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: AppTypography.body15(
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected ? AppColors.primaryBlue : AppColors.textDark,
                ),
              ),
            ),
            if (showPlay)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(
                  Icons.play_arrow,
                  size: 16,
                  color: isSelected ? AppColors.primaryBlue : AppColors.textLight,
                ),
              ),
            if (isSelected)
              const Icon(Icons.check, size: 18, color: AppColors.primaryBlue),
          ],
        ),
      ),
    );
  }

  Widget _customSwitch(bool value, ValueChanged<bool> onChanged) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 44,
        height: 26,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(13),
          color: value ? AppColors.primaryBlue : const Color(0xFFD4D4D8),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 22,
            height: 22,
            margin: const EdgeInsets.all(2),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  Widget _backButton() {
    return GestureDetector(
      onTap: () => Navigator.pop(context),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.greyBgDarker,
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Icon(Icons.arrow_back, size: 20, color: AppColors.textDark),
      ),
    );
  }
}
