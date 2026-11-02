/// What the model service charges, as the user typed it in Settings → AI:
/// input and output per million tokens (in whatever currency the service
/// bills) and the price of cached input as a percentage of the input price.
/// Nothing is set by default; the cost of an answer is shown only once a
/// price is.
class TokenPrices {
  const TokenPrices({
    this.inputPerMillion = 0,
    this.outputPerMillion = 0,
    this.cachedPercent = 100,
  });

  factory TokenPrices.fromJson(Map<String, dynamic> json) {
    double n(String key, double fallback) {
      final value = json[key];
      return value is num && value.isFinite && value >= 0
          ? value.toDouble()
          : fallback;
    }

    return TokenPrices(
      inputPerMillion: n('input', 0),
      outputPerMillion: n('output', 0),
      cachedPercent: n('cached_percent', 100).clamp(0, 100).toDouble(),
    );
  }

  final double inputPerMillion;
  final double outputPerMillion;

  /// Cached input costs this share of [inputPerMillion], 0–100 (100: the
  /// service gives no discount, or does not cache).
  final double cachedPercent;

  bool get isSet => inputPerMillion > 0 || outputPerMillion > 0;

  /// The price of [prompt] input tokens ([cached] of them served from the
  /// provider's cache) and [completion] output tokens.
  double cost({
    required int prompt,
    required int cached,
    required int completion,
  }) {
    final hit = cached.clamp(0, prompt);
    final input = (prompt - hit) + hit * cachedPercent / 100;
    return (input * inputPerMillion + completion * outputPerMillion) / 1e6;
  }

  Map<String, Object> toJson() => {
        'input': inputPerMillion,
        'output': outputPerMillion,
        'cached_percent': cachedPercent,
      };

  @override
  bool operator ==(Object other) =>
      other is TokenPrices &&
      other.inputPerMillion == inputPerMillion &&
      other.outputPerMillion == outputPerMillion &&
      other.cachedPercent == cachedPercent;

  @override
  int get hashCode =>
      Object.hash(inputPerMillion, outputPerMillion, cachedPercent);
}

/// A price: two decimals from 1 up, three significant digits below
/// (`12.40`, `0.385`, `0.00412`).
String formatCost(double cost) {
  if (cost >= 1) return cost.toStringAsFixed(2);
  if (cost <= 0) return '0';
  return double.parse(cost.toStringAsPrecision(3)).toString();
}
