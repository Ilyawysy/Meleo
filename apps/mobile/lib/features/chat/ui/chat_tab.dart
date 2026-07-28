import 'package:flutter/material.dart';
import 'package:rive/rive.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_typography.dart';
import '../models/chat_item.dart';
import 'chat_widget_card.dart';
import 'custom_chat_input.dart';

class ChatTab extends StatefulWidget {
  final List<ChatItem> items;
  final Function(String content) onSend;
  final bool isLoading;
  final void Function(String entityType, String entityId)? onOpenEntity;
  final VoidCallback? onThreadsTap;
  final VoidCallback? onBack;
  final bool canSendChat;
  final int? chatRemaining;
  final int? chatLimit;

  const ChatTab({
    super.key,
    required this.items,
    required this.onSend,
    this.isLoading = false,
    this.onOpenEntity,
    this.onThreadsTap,
    this.onBack,
    this.canSendChat = true,
    this.chatRemaining,
    this.chatLimit,
  });

  @override
  State<ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<ChatTab> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();

  void _handleSend(String content) {
    if (content.trim().isEmpty) return;
    widget.onSend(content);
    _controller.clear();
    Future.delayed(Duration.zero, () {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  void _sendQuickAction(String text) {
    if (!widget.canSendChat) return;
    widget.onSend(text);
    Future.delayed(Duration.zero, () {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  bool get _isEmpty => widget.items.isEmpty && !widget.isLoading;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (widget.onBack != null)
                  GestureDetector(
                    onTap: widget.onBack,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: const Icon(
                        Icons.arrow_back,
                        size: 18,
                        color: AppColors.textDark,
                      ),
                    ),
                  )
                else
                  const SizedBox(width: 40),
                if (widget.onThreadsTap != null)
                  GestureDetector(
                    onTap: widget.onThreadsTap,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: const Icon(
                        Icons.chat_bubble_outline,
                        size: 18,
                        color: AppColors.textDark,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _isEmpty ? _buildEmptyState() : _buildMessages(),
          ),
          if (!widget.canSendChat)
            _buildUpgradeBanner(),
          if (widget.canSendChat)
            CustomChatInput(
              controller: _controller,
              onSend: _handleSend,
              isLoading: widget.isLoading,
            )
          else
            _buildDisabledInput(),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Empty state
  // ---------------------------------------------------------------------------
  Widget _buildEmptyState() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        children: [
          const SizedBox(height: 16),
          const _GhostAnimation(),
          const SizedBox(height: 16),
          // Prompt cards (tappable, send preset query)
          _promptCard(Icons.center_focus_strong_outlined,
              'Что сейчас с моим фокусом?'),
          const SizedBox(height: 10),
          _promptCard(Icons.lightbulb_outline, 'Главные инсайты'),
          const SizedBox(height: 10),
          _promptCard(Icons.bar_chart_rounded, 'Отчёт за неделю'),
          const SizedBox(height: 10),
          _promptCard(Icons.checklist_rounded, 'Что сделать сегодня?'),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _promptCard(IconData icon, String text) {
    return GestureDetector(
      onTap: () => _sendQuickAction(text),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.greyBg,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.primaryBlue),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: AppTypography.body14(fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Messages
  // ---------------------------------------------------------------------------
  Widget _buildMessages() {
    final itemCount = widget.items.length + (widget.isLoading ? 1 : 0);

    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      itemCount: itemCount,
      itemBuilder: (context, i) {
        // Loading indicator
        if (widget.isLoading && i == widget.items.length) {
          return _buildAiBubbleWrapper(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primaryBlue,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Думаю...',
                  style: AppTypography.body14(color: AppColors.textMedium),
                ),
              ],
            ),
          );
        }

        final item = widget.items[i];

        // Widget card (rendered inside AI bubble)
        if (!item.isMessage && item.widget != null) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _buildAiBubbleWrapper(
              child: ChatWidgetCard(
                widgetData: item.widget!,
                onOpenEntity: widget.onOpenEntity,
              ),
            ),
          );
        }

        // Message
        final m = item.message!;
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: m.isMe ? _buildUserMessage(m.text) : _buildAiMessage(m.text),
        );
      },
    );
  }

  Widget _buildAiMessage(String text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // AI label
        Row(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: AppColors.primaryBlue,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.auto_awesome,
                color: Colors.white,
                size: 12,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              'Meleo ИИ',
              style: AppTypography.caption12(color: AppColors.textMedium),
            ),
          ],
        ),
        const SizedBox(height: 4),
        // Bubble
        Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78,
          ),
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: AppColors.greyBgDarker,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(4),
              topRight: Radius.circular(20),
              bottomRight: Radius.circular(20),
              bottomLeft: Radius.circular(20),
            ),
          ),
          child: Text(
            text,
            style: AppTypography.body14().copyWith(height: 1.5),
          ),
        ),
      ],
    );
  }

  Widget _buildAiBubbleWrapper({required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: AppColors.primaryBlue,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.auto_awesome,
                color: Colors.white,
                size: 12,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              'Meleo ИИ',
              style: AppTypography.caption12(color: AppColors.textMedium),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78,
          ),
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: AppColors.greyBgDarker,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(4),
              topRight: Radius.circular(20),
              bottomRight: Radius.circular(20),
              bottomLeft: Radius.circular(20),
            ),
          ),
          child: child,
        ),
      ],
    );
  }

  Widget _buildUserMessage(String text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.7,
          ),
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF2563EB), Color(0xFF7C3AED)],
            ),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
              bottomRight: Radius.circular(4),
              bottomLeft: Radius.circular(20),
            ),
          ),
          child: Text(
            text,
            style: AppTypography.body14(color: Colors.white)
                .copyWith(height: 1.5),
          ),
        ),
      ],
    );
  }

  Widget _buildUpgradeBanner() {
    final used = widget.chatLimit != null && widget.chatRemaining != null
        ? widget.chatLimit! - widget.chatRemaining!
        : widget.chatLimit ?? 0;
    final limit = widget.chatLimit ?? 0;
    return Container(
      color: const Color(0xFFFEF3C7),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lock_outline, size: 18, color: Color(0xFFD97706)),
              const SizedBox(width: 10),
              Text(
                'Дневной лимит исчерпан ($used/$limit сообщений)',
                style: AppTypography.body14(
                  color: const Color(0xFF92400E),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Перейдите на Pro: безлимитные диалоги с AI, приоритетные ответы и расширенные инсайты.',
            style: AppTypography.body14(color: const Color(0xFFA16207))
                .copyWith(fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton(
              onPressed: () {},
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD97706),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: EdgeInsets.zero,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.workspace_premium, size: 16, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(
                    'Перейти на Pro',
                    style: AppTypography.body14(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDisabledInput() {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFF4F4F5))),
      ),
      padding: const EdgeInsets.only(top: 12, left: 20, right: 20, bottom: 34),
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          color: const Color(0xFFF4F4F5),
          borderRadius: BorderRadius.circular(24),
        ),
        padding: const EdgeInsets.only(left: 18, right: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Лимит на сегодня исчерпан',
                style: AppTypography.body14(color: const Color(0xFFA1A1AA))
                    .copyWith(fontSize: 15),
              ),
            ),
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFFE4E4E7),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(
                Icons.arrow_upward,
                size: 18,
                color: Color(0xFFA1A1AA),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GhostAnimation extends StatefulWidget {
  const _GhostAnimation();

  @override
  State<_GhostAnimation> createState() => _GhostAnimationState();
}

class _GhostAnimationState extends State<_GhostAnimation> {
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
    return SizedBox(
      width: 200,
      height: 200,
      child: _controller != null
          ? RiveWidget(controller: _controller!, fit: Fit.contain)
          : const Icon(
              Icons.auto_awesome,
              size: 80,
              color: Color(0x66888888),
            ),
    );
  }
}
