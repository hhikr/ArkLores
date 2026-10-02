import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression guard for the Riverpod lifecycle rule that crashed the app
/// shell after install (see `wiki_browser_page.dart` initState fix):
/// writing a provider inside initState throws "Tried to modify a provider
/// while the widget tree was building"; deferring the write to a post-frame
/// callback is the supported pattern.
final _testIntProvider = StateProvider<int>((ref) => 0);

class _LifecycleWriteProbe extends ConsumerStatefulWidget {
  const _LifecycleWriteProbe({required this.deferWrite});
  final bool deferWrite;

  @override
  ConsumerState<_LifecycleWriteProbe> createState() =>
      _LifecycleWriteProbeState();
}

class _LifecycleWriteProbeState extends ConsumerState<_LifecycleWriteProbe> {
  @override
  void initState() {
    super.initState();
    if (widget.deferWrite) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(_testIntProvider.notifier).state = 1;
        }
      });
    } else {
      ref.read(_testIntProvider.notifier).state = 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}

void main() {
  testWidgets('deferring the provider write to a post-frame callback is safe',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: const MaterialApp(home: _LifecycleWriteProbe(deferWrite: true)),
      ),
    );
    await tester.pump(); // flush the post-frame callback
    expect(tester.takeException(), isNull);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(_LifecycleWriteProbe)),
    );
    expect(container.read(_testIntProvider), 1);
  });
}
