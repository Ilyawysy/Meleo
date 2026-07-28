import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_client.dart';
import '../../../core/providers/logout_controller.dart';

class DeleteAccountDialog extends ConsumerStatefulWidget {
  const DeleteAccountDialog({super.key});

  @override
  ConsumerState<DeleteAccountDialog> createState() =>
      _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends ConsumerState<DeleteAccountDialog> {
  final _controller = TextEditingController();
  bool _loading = false;
  String _input = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    setState(() => _loading = true);
    try {
      final client = ApiClient();
      final r = await client.send(
        'DELETE',
        client.uri('/api/v1/auth/account'),
      );
      if (!mounted) return;
      if (r.statusCode == 200 || r.statusCode == 204) {
        final logoutNotifier = ref.read(logoutControllerProvider.notifier);
        Navigator.of(context).pop();
        await logoutNotifier.logout();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка удаления аккаунта: ${r.statusCode}'),
          ),
        );
        setState(() => _loading = false);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canDelete = _input == 'DELETE';
    return AlertDialog(
      title: const Text('Удалить аккаунт'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Это действие необратимо. Все ваши данные будут удалены безвозвратно.',
          ),
          const SizedBox(height: 16),
          const Text('Введите DELETE для подтверждения:'),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            decoration: const InputDecoration(
              hintText: 'DELETE',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => setState(() => _input = v),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: (_loading || !canDelete) ? null : _confirm,
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          child: _loading
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Удалить'),
        ),
      ],
    );
  }
}
