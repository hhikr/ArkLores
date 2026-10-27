import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/llm/token_prices.dart';
import '../../shared/l10n/l10n.dart';
import '../../shared/providers/settings_provider.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/ef_widgets.dart';
import '../../shared/widgets/page_frame.dart';

/// The model service's prices, from which the line under each answer works
/// out what the question cost: input and output per million tokens, and
/// what cached input costs as a share of the input price. An empty price is
/// 0; an empty share is 100 (no discount).
class TokenPricesPage extends ConsumerStatefulWidget {
  const TokenPricesPage({super.key});

  @override
  ConsumerState<TokenPricesPage> createState() => _TokenPricesPageState();
}

class _TokenPricesPageState extends ConsumerState<TokenPricesPage> {
  late final TextEditingController _input;
  late final TextEditingController _output;
  late final TextEditingController _cached;
  String? _inputError;
  String? _outputError;
  String? _cachedError;

  static String _shown(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toString();

  @override
  void initState() {
    super.initState();
    final prices = ref.read(tokenPricesProvider);
    _input = TextEditingController(
      text: prices.inputPerMillion > 0 ? _shown(prices.inputPerMillion) : '',
    );
    _output = TextEditingController(
      text: prices.outputPerMillion > 0 ? _shown(prices.outputPerMillion) : '',
    );
    _cached = TextEditingController(
      text: prices.cachedPercent < 100 ? _shown(prices.cachedPercent) : '',
    );
  }

  @override
  void dispose() {
    _input.dispose();
    _output.dispose();
    _cached.dispose();
    super.dispose();
  }

  /// The number in [controller], [empty] when blank, null when it is not a
  /// number in [0, max].
  static double? _read(
    TextEditingController controller, {
    required double empty,
    double max = double.infinity,
  }) {
    final text = controller.text.trim();
    if (text.isEmpty) return empty;
    final value = double.tryParse(text);
    return value != null && value.isFinite && value >= 0 && value <= max
        ? value
        : null;
  }

  Future<void> _save() async {
    final input = _read(_input, empty: 0);
    final output = _read(_output, empty: 0);
    final cached = _read(_cached, empty: 100, max: 100);
    setState(() {
      _inputError = input == null ? context.t.tokenPricesInvalid : null;
      _outputError = output == null ? context.t.tokenPricesInvalid : null;
      _cachedError = cached == null ? context.t.tokenPricesCachedInvalid : null;
    });
    if (input == null || output == null || cached == null) return;
    await ref.read(tokenPricesProvider.notifier).set(
          TokenPrices(
            inputPerMillion: input,
            outputPerMillion: output,
            cachedPercent: cached,
          ),
        );
    if (!mounted) return;
    showToast(context, context.t.tokenPricesSaved);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    Widget field(
      String key,
      TextEditingController controller,
      String label,
      String? error,
      VoidCallback clearError,
    ) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: TextField(
            key: ValueKey(key),
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            style: theme.field(color: theme.textPrimary, size: 15),
            onChanged: (_) {
              if (error != null) setState(clearError);
            },
            decoration: InputDecoration(labelText: label, errorText: error),
          ),
        );
    return PageScaffold(
      title: context.t.settingsTokenPrices,
      scrollUnder: true,
      body: ListView(
        padding: pagePadding(context, const EdgeInsets.fromLTRB(16, 4, 16, 40)),
        children: [
          Text(
            context.t.tokenPricesIntro,
            style: theme.text(14, color: theme.textSecondary, height: 1.6),
          ),
          const SizedBox(height: 16),
          field('token-price-input', _input, context.t.tokenPricesInput,
              _inputError, () => _inputError = null,),
          field('token-price-output', _output, context.t.tokenPricesOutput,
              _outputError, () => _outputError = null,),
          field('token-price-cached', _cached, context.t.tokenPricesCached,
              _cachedError, () => _cachedError = null,),
          Text(
            context.t.tokenPricesCachedHint,
            style: theme.text(13, color: theme.textSecondary, height: 1.5),
          ),
          const SizedBox(height: 16),
          AppButton(
            context.t.apiSettingsSave,
            key: const ValueKey('token-prices-save'),
            kind: ButtonKind.go,
            icon: Icons.save_sharp,
            expand: true,
            onPressed: _save,
          ),
        ],
      ),
    );
  }
}
