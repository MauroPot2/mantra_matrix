import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_sharing.dart';
import 'package:mantra_matrix/features/auction/presentation/providers/auction_sharing_providers.dart';

class JoinAuctionCodeDialog extends ConsumerStatefulWidget {
  const JoinAuctionCodeDialog({super.key});

  @override
  ConsumerState<JoinAuctionCodeDialog> createState() =>
      _JoinAuctionCodeDialogState();
}

class _JoinAuctionCodeDialogState extends ConsumerState<JoinAuctionCodeDialog> {
  final _controller = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = AuctionShareInvite.normalizeEntryCode(_controller.text);
    if (code.length != 8 || _submitting) {
      setState(() => _error = 'Inserisci il codice di 8 caratteri.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await ref
          .read(auctionSharingRepositoryProvider)
          .requestAccessByCode(entryCode: code);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Entra in un’asta'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Inserisci il codice condiviso dal proprietario. Dopo la richiesta, '
              'l’owner dovrà approvarti e associarti alla tua squadra.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9-]')),
                LengthLimitingTextInputFormatter(9),
              ],
              decoration: InputDecoration(
                labelText: 'Codice di ingresso',
                hintText: '7K9M-P4QX',
                prefixIcon: const Icon(Icons.key_rounded),
                errorText: _error,
              ),
              onChanged: (value) {
                final normalized = AuctionShareInvite.normalizeEntryCode(value);
                if (normalized.length == 8 && value != normalized) {
                  final formatted = '${normalized.substring(0, 4)}-${normalized.substring(4)}';
                  _controller.value = TextEditingValue(
                    text: formatted,
                    selection: TextSelection.collapsed(offset: formatted.length),
                  );
                }
              },
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('Annulla'),
        ),
        FilledButton.icon(
          onPressed: _submitting ? null : _submit,
          icon: _submitting
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.login_rounded),
          label: Text(_submitting ? 'Invio…' : 'Chiedi accesso'),
        ),
      ],
    );
  }
}
