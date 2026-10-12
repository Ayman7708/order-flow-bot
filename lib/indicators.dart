import 'dart:math';

class Ind {
  static double? ema(List<double> prices, int period) {
    if (prices.length < period) return null;
    final k = 2 / (period + 1);
    double e = prices.take(period).reduce((a, b) => a + b) / period;
    for (int i = period; i < prices.length; i++) {
      e = prices[i] * k + e * (1 - k);
    }
    return e;
  }

  static double atr(List<double> highs, List<double> lows, List<double> closes, [int period = 14]) {
    if (closes.length < period + 1) return 0;
    double sum = 0;
    for (int i = closes.length - period; i < closes.length; i++) {
      final tr = [
        highs[i] - lows[i],
        (highs[i] - closes[i - 1]).abs(),
        (lows[i] - closes[i - 1]).abs(),
      ].reduce((a, b) => a > b ? a : b);
      sum += tr;
    }
    return sum / period;
  }
}
