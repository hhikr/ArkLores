import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/update/app_update_provider.dart';
import '../../shared/l10n/l10n.dart';
import '../../shared/widgets/ef_widgets.dart';
import '../../shared/widgets/smooth_page_route.dart';
import 'update_page.dart';

/// Checks once after the main screen opens; never starts a download.
class UpdateStartup extends ConsumerStatefulWidget {
  const UpdateStartup({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<UpdateStartup> createState() => _UpdateStartupState();
}

class _UpdateStartupState extends ConsumerState<UpdateStartup> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_check()));
  }

  Future<void> _check() async {
    if (!mounted) return;
    final enabled = ref.read(autoUpdateCheckProvider);
    if (!enabled) return;
    try {
      final release = await ref
          .read(appUpdateProvider.notifier)
          .autoCheck(enabled: enabled);
      if (!mounted || release == null) return;
      showToast(
        context,
        context.t.updateFound(release.versionName),
        action: SnackBarAction(
          label: context.t.updateFoundOpen,
          onPressed: () => Navigator.of(context).push(
            smoothPageRoute<void>(builder: (_) => const UpdatePage()),
          ),
        ),
      );
    } catch (_) {
      // A startup check must not interrupt opening the app.
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
