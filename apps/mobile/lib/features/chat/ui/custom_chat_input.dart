import 'package:flutter/material.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_typography.dart';

class CustomChatInput extends StatefulWidget {
  final TextEditingController controller;
  final Function(String content) onSend;
  final bool isLoading;

  const CustomChatInput({
    super.key,
    required this.controller,
    required this.onSend,
    this.isLoading = false,
  });

  @override
  State<CustomChatInput> createState() => _CustomChatInputState();
}

class _CustomChatInputState extends State<CustomChatInput> {
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _handleSend() {
    final content = widget.controller.text.trim();
    if (content.isEmpty) return;
    widget.onSend(content);
    widget.controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 34),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.greyBgDarker, width: 1)),
      ),
      child: Container(
        height: 50,
        padding: const EdgeInsets.only(left: 18, right: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: widget.controller,
                focusNode: _focusNode,
                style: AppTypography.body15(),
                decoration: InputDecoration(
                  hintText: 'Спросите что-нибудь...',
                  hintStyle:
                      AppTypography.body15(color: AppColors.textLight),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  isDense: true,
                ),
                maxLines: 1,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _handleSend(),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: widget.isLoading ? null : _handleSend,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF2563EB),
                      Color(0xFF7C3AED),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: widget.isLoading
                    ? const Padding(
                        padding: EdgeInsets.all(8),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(
                        Icons.arrow_upward,
                        color: Colors.white,
                        size: 18,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
