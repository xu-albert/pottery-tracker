import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers/feedback_provider.dart';
import '../../../providers/review_prompt_provider.dart';
import '../../../services/feedback_service.dart';
import '../../../widgets/app_snackbar.dart';

class FeedbackScreen extends ConsumerStatefulWidget {
  const FeedbackScreen({super.key});

  @override
  ConsumerState<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends ConsumerState<FeedbackScreen> {
  static const _maxMessageLength = 2000;

  FeedbackCategory _category = FeedbackCategory.other;
  final _messageController = TextEditingController();
  late final TextEditingController _emailController;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    String email = '';
    try {
      email = FirebaseAuth.instance.currentUser?.email ?? '';
    } catch (_) {}
    _emailController = TextEditingController(text: email);
    _messageController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _messageController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _submitting = true);
    try {
      await ref.read(feedbackServiceProvider).submit(
            category: _category,
            message: _messageController.text.trim(),
            replyEmail: _emailController.text.trim().isEmpty
                ? null
                : _emailController.text.trim(),
          );
      await ref.read(reviewPromptServiceProvider).recordCompleted();
      if (!mounted) return;
      AppSnackbar.show(context, message: l10n.feedbackSentSuccess);
      context.pop();
    } catch (_) {
      if (!mounted) return;
      AppSnackbar.show(context, message: l10n.feedbackSendFailed);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _categoryLabel(FeedbackCategory c, AppLocalizations l10n) {
    switch (c) {
      case FeedbackCategory.bug:
        return l10n.feedbackCategoryBug;
      case FeedbackCategory.feature:
        return l10n.feedbackCategoryFeature;
      case FeedbackCategory.other:
        return l10n.feedbackCategoryOther;
      case FeedbackCategory.praise:
        return l10n.feedbackCategoryPraise;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final canSend = !_submitting && _messageController.text.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.feedbackScreenTitle)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSizes.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<FeedbackCategory>(
              initialValue: _category,
              decoration: InputDecoration(
                labelText: l10n.feedbackCategoryLabel,
                border: const OutlineInputBorder(),
              ),
              items: FeedbackCategory.values
                  .map((c) => DropdownMenuItem(
                        value: c,
                        child: Text(_categoryLabel(c, l10n)),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _category = v);
              },
            ),
            const SizedBox(height: AppSizes.md),
            TextField(
              controller: _messageController,
              maxLength: _maxMessageLength,
              maxLines: 5,
              decoration: InputDecoration(
                labelText: l10n.feedbackMessageLabel,
                hintText: l10n.feedbackMessageHint,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSizes.md),
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: l10n.feedbackReplyEmailLabel,
                hintText: l10n.feedbackReplyEmailHint,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSizes.lg),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _submitting ? null : () => context.pop(),
                    child: Text(l10n.cancel),
                  ),
                ),
                const SizedBox(width: AppSizes.md),
                Expanded(
                  child: ElevatedButton(
                    onPressed: canSend ? _submit : null,
                    child: _submitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(l10n.feedbackSendButton),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
