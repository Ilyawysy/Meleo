import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rive/rive.dart';

import '../../../../core/design/app_colors.dart';
import '../../../../core/design/app_typography.dart';
import '../../data/help_api.dart';
import '../../data/help_topics.dart';
import '../../models/help_models.dart';
import '../../providers/active_room_provider.dart';

class HelpFlowScreen extends ConsumerStatefulWidget {
  const HelpFlowScreen({super.key});

  @override
  ConsumerState<HelpFlowScreen> createState() => _HelpFlowScreenState();
}

class _HelpFlowScreenState extends ConsumerState<HelpFlowScreen> {
  final _api = HelpApi();

  int _step = 0;
  String? _topicId;
  String? _subtopicId;
  String? _topicLabel;

  String? _question;
  List<String>? _options;
  String? _answer;
  bool _showCustomInput = false;
  final _customController = TextEditingController();

  HelpCard? _card;
  bool _loading = false;

  bool _showFeedbackCustomInput = false;
  final _feedbackController = TextEditingController();

  @override
  void dispose() {
    _customController.dispose();
    _feedbackController.dispose();
    super.dispose();
  }

  void _back() {
    if (_loading) return;
    if (_step > 0) {
      setState(() {
        _step -= 1;
        _showCustomInput = false;
        _showFeedbackCustomInput = false;
      });
    } else {
      Navigator.of(context).pop();
    }
  }

  Future<void> _loadQuestion() async {
    setState(() => _loading = true);
    try {
      final result = await _api.getQuestion(_topicId!, _subtopicId!);
      if (!mounted) return;
      setState(() {
        _question = result.question;
        _options = result.options;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _question = 'Что сейчас ближе всего описывает твоё состояние?';
        _options = [
          'Просто не могу собраться и начать',
          'Устал и нет сил на задачу',
          'Задача кажется слишком большой',
          'Отвлекаюсь и не могу переключиться',
          'Другое (напишу сам)',
        ];
        _loading = false;
      });
    }
  }

  Future<void> _loadCard({HelpCardPrev? prevCard, String? feedback}) async {
    setState(() => _loading = true);
    try {
      final result = await _api.getCard(
        topicId: _topicId!,
        subtopicId: _subtopicId!,
        question: _question ?? '',
        answer: _answer ?? '',
        prevCard: prevCard,
        feedback: feedback,
      );
      if (!mounted) return;
      setState(() {
        _card = result;
        _loading = false;
        _showFeedbackCustomInput = false;
        _feedbackController.clear();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _card = HelpCard(
          messages: [
            'Иногда начать — это самое сложное. Это нормально.',
            'Попробуй открыть задачу и сделать один маленький шаг — буквально одно действие.',
          ],
          action: const HelpAction(
            label: 'Начать 15 минут',
            type: HelpActionType.focus,
            durationMinutes: 15,
          ),
          feedbackOptions: const [
            'это не помогло',
            'слишком общо',
            'хочу другое действие',
            'Другое (напишу сам)',
          ],
        );
        _loading = false;
        _showFeedbackCustomInput = false;
        _feedbackController.clear();
      });
    }
  }

  void _onSelectTopic(HelpTopic topic) {
    setState(() {
      _topicId = topic.id;
      _topicLabel = topic.label;
      _step = 1;
    });
  }

  void _onSelectSubtopic(HelpSubtopic subtopic) {
    setState(() {
      _subtopicId = subtopic.id;
      _step = 2;
    });
    _loadQuestion();
  }

  void _onSelectOption(String option) {
    final isOther = _options != null &&
        _options!.isNotEmpty &&
        _options!.last == option &&
        option.toLowerCase().contains('друг');
    if (isOther) {
      setState(() {
        _showCustomInput = true;
        _customController.clear();
      });
    } else {
      _answer = option;
      setState(() {
        _step = 3;
        _showCustomInput = false;
      });
      _loadCard();
    }
  }

  void _onSubmitCustomAnswer() {
    final text = _customController.text.trim();
    if (text.isEmpty) return;
    _answer = text;
    setState(() {
      _step = 3;
      _showCustomInput = false;
    });
    _loadCard();
  }

  void _onCardAction() {
    final card = _card;
    if (card == null) return;
    if (card.action.type == HelpActionType.focus) {
      final dur = card.action.durationMinutes ?? 15;
      Navigator.of(context).pop({'action': 'focus', 'duration': dur});
    } else {
      Navigator.of(context).pop();
    }
  }

  void _onFeedbackOption(String feedback) {
    final isOther = _card != null &&
        _card!.feedbackOptions.isNotEmpty &&
        _card!.feedbackOptions.last == feedback &&
        feedback.toLowerCase().contains('друг');
    if (isOther) {
      setState(() {
        _showFeedbackCustomInput = true;
        _feedbackController.clear();
      });
    } else {
      final prev = _card != null ? HelpCardPrev.fromCard(_card!) : null;
      _loadCard(prevCard: prev, feedback: feedback);
    }
  }

  void _onSubmitFeedbackCustom() {
    final text = _feedbackController.text.trim();
    if (text.isEmpty) return;
    final prev = _card != null ? HelpCardPrev.fromCard(_card!) : null;
    _loadCard(prevCard: prev, feedback: text);
  }

  Scaffold _buildEmptyStateScaffold() {
    return Scaffold(
      backgroundColor: AppColors.greyBg,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textDark),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('Не могу начать', style: AppTypography.heading18()),
        centerTitle: false,
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _GhostHeader(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Сначала выбери комнату для фокуса',
                      style: AppTypography.heading18(),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Я подскажу, как начать, когда ты определишься.',
                      style: AppTypography.body14(),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primaryBlue,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text(
                          'Понятно',
                          style: AppTypography.body14(
                            color: AppColors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeRoomId = ref.watch(activeRoomIdProvider);
    if (activeRoomId == null) {
      return _buildEmptyStateScaffold();
    }

    return Scaffold(
      backgroundColor: AppColors.greyBg,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textDark),
          onPressed: _back,
        ),
        title: Text(_stepTitle, style: AppTypography.heading18()),
        centerTitle: false,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                '${_step + 1} / 4',
                style: AppTypography.body13(color: AppColors.textLight),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _GhostHeader(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  String get _stepTitle {
    switch (_step) {
      case 0:
        return 'Что мешает начать?';
      case 1:
        return _topicLabel ?? 'Уточни';
      case 2:
        return 'Что именно сейчас?';
      case 3:
        return 'Карточка';
      default:
        return '';
    }
  }

  Widget _buildBody() {
    switch (_step) {
      case 0:
        return _buildTopics();
      case 1:
        return _buildSubtopics();
      case 2:
        return _buildQuestion();
      case 3:
        return _buildCard();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildTopics() {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: kHelpTopics.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final t = kHelpTopics[i];
        final subtitle = t.subtopics.map((s) => s.label).join(' · ');
        return _OptionCard(
          title: t.label,
          subtitle: subtitle,
          onTap: () => _onSelectTopic(t),
        );
      },
    );
  }

  Widget _buildSubtopics() {
    final topic = kHelpTopics.where((t) => t.id == _topicId).firstOrNull;
    final subtopics = topic?.subtopics ?? [];
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: subtopics.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final s = subtopics[i];
        return _OptionCard(
          title: s.label,
          onTap: () => _onSelectSubtopic(s),
        );
      },
    );
  }

  Widget _buildQuestion() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final question = _question ?? '';
    final options = _options ?? [];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Text(
          'Персонализированный вопрос под твою ситуацию',
          style: AppTypography.caption12(),
        ),
        const SizedBox(height: 8),
        Text(question, style: AppTypography.heading18()),
        const SizedBox(height: 16),
        for (final opt in options) ...[
          _OptionCard(
            title: opt,
            onTap: () => _onSelectOption(opt),
          ),
          const SizedBox(height: 10),
        ],
        if (_showCustomInput) ...[
          const SizedBox(height: 4),
          TextField(
            controller: _customController,
            autofocus: true,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Опишу своими словами...',
              hintStyle: AppTypography.body14(),
              filled: true,
              fillColor: AppColors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: AppColors.primaryBlue, width: 2),
              ),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
          const SizedBox(height: 12),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _customController,
            builder: (context, value, _) {
              final enabled = value.text.trim().isNotEmpty;
              return SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: enabled ? _onSubmitCustomAnswer : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    disabledBackgroundColor: AppColors.border,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Дальше',
                    style: AppTypography.body14(
                      color: enabled ? AppColors.white : AppColors.textLight,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ],
    );
  }

  Widget _buildCard() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final card = _card;
    if (card == null) return const SizedBox.shrink();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        for (final msg in card.messages) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(msg, style: AppTypography.body14()),
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.primaryBlue, width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ДЕЙСТВИЕ',
                style: AppTypography.caption11(color: AppColors.primaryBlue),
              ),
              const SizedBox(height: 4),
              Text(card.action.label, style: AppTypography.heading16()),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: FilledButton(
                  onPressed: _onCardAction,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    card.action.label,
                    style: AppTypography.body14(
                      color: AppColors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text('КАК КАРТОЧКА?', style: AppTypography.sectionTitle()),
        const SizedBox(height: 8),
        for (final f in card.feedbackOptions) ...[
          _OptionCard(
            title: f,
            onTap: () => _onFeedbackOption(f),
          ),
          const SizedBox(height: 8),
        ],
        if (_showFeedbackCustomInput) ...[
          const SizedBox(height: 4),
          TextField(
            controller: _feedbackController,
            autofocus: true,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Напишу своими словами...',
              hintStyle: AppTypography.body14(),
              filled: true,
              fillColor: AppColors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: AppColors.primaryBlue, width: 2),
              ),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
          const SizedBox(height: 12),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _feedbackController,
            builder: (context, value, _) {
              final enabled = value.text.trim().isNotEmpty;
              return SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: enabled ? _onSubmitFeedbackCustom : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    disabledBackgroundColor: AppColors.border,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Отправить',
                    style: AppTypography.body14(
                      color: enabled ? AppColors.white : AppColors.textLight,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ],
    );
  }
}

// ──────────────── Ghost header ────────────────

class _GhostHeader extends StatefulWidget {
  const _GhostHeader();

  @override
  State<_GhostHeader> createState() => _GhostHeaderState();
}

class _GhostHeaderState extends State<_GhostHeader> {
  File? _file;
  RiveWidgetController? _controller;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final file = await File.asset(
        'assets/rive/ghost.riv',
        riveFactory: Factory.rive,
      );
      if (file == null) return;
      if (!mounted) {
        file.dispose();
        return;
      }
      setState(() {
        _file = file;
        _controller = RiveWidgetController(file);
      });
    } catch (_) {
      // Fallback icon will render.
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _file?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 40),
      child: SizedBox(
        height: 200,
        child: Center(
          child: SizedBox(
            width: 200,
            height: 200,
            child: _controller != null
                ? RiveWidget(controller: _controller!, fit: Fit.contain)
                : const Icon(
                    Icons.sentiment_neutral,
                    size: 80,
                    color: Color(0x66888888),
                  ),
          ),
        ),
      ),
    );
  }
}

// ──────────────── Reusable option card ────────────────

class _OptionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  const _OptionCard({
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppColors.border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: AppTypography.body14(fontWeight: FontWeight.w600),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style: AppTypography.caption12(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
