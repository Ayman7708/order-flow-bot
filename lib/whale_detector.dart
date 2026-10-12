import 'ws_service.dart';

/// Snapshot of market flow for one symbol
class FlowSnapshot {
  final String symbol;
  final double totalVolume;      // USD in window
  final double buyVolume;
  final double sellVolume;
  final int tradeCount;
  final int whaleCount;          // orders > threshold
  final double whaleVolume;      // USD from whales
  final double largestOrder;     // biggest single order
  final double priceStart;
  final double priceNow;
  final int windowMs;

  FlowSnapshot({
    required this.symbol,
    required this.totalVolume,
    required this.buyVolume,
    required this.sellVolume,
    required this.tradeCount,
    required this.whaleCount,
    required this.whaleVolume,
    required this.largestOrder,
    required this.priceStart,
    required this.priceNow,
    required this.windowMs,
  });

  double get buyRatio => totalVolume == 0 ? 0.5 : buyVolume / totalVolume;
  double get sellRatio => totalVolume == 0 ? 0.5 : sellVolume / totalVolume;
  double get priceChangePct =>
      priceStart == 0 ? 0 : (priceNow - priceStart) / priceStart * 100;
  double get whaleRatio => totalVolume == 0 ? 0 : whaleVolume / totalVolume;

  /// Bullish score 0-100
  int get bullishScore {
    int s = 0;
    if (buyRatio > 0.55) s += 25;
    else if (buyRatio > 0.5) s += 10;
    if (whaleCount >= 3) s += 20;
    else if (whaleCount >= 1) s += 10;
    if (whaleRatio > 0.4) s += 20;
    if (priceChangePct > 0.15) s += 20;
    else if (priceChangePct > 0.05) s += 10;
    if (largestOrder > 200000) s += 15;
    else if (largestOrder > 100000) s += 8;
    return s.clamp(0, 100);
  }

  /// Bearish score 0-100
  int get bearishScore {
    int s = 0;
    if (sellRatio > 0.55) s += 25;
    else if (sellRatio > 0.5) s += 10;
    if (whaleCount >= 3) s += 20;
    else if (whaleCount >= 1) s += 10;
    if (whaleRatio > 0.4) s += 20;
    if (priceChangePct < -0.15) s += 20;
    else if (priceChangePct < -0.05) s += 10;
    if (largestOrder > 200000) s += 15;
    else if (largestOrder > 100000) s += 8;
    return s.clamp(0, 100);
  }
}

/// Holds rolling window of trade events per symbol
class WhaleDetector {
  final int windowSeconds;
  final double whaleThreshold; // USD

  WhaleDetector({
    this.windowSeconds = 10,
    this.whaleThreshold = 50000,
  });

  final Map<String, List<TradeEvent>> _windows = {};
  final Map<String, double> _priceStart = {};

  void addEvent(TradeEvent e) {
    _windows.putIfAbsent(e.symbol, () => []);
    _windows[e.symbol]!.add(e);
    _priceStart.putIfAbsent(e.symbol, () => e.price);

    // Trim old
    final cutoff = DateTime.now().millisecondsSinceEpoch - windowSeconds * 1000;
    _windows[e.symbol]!.removeWhere((t) => t.time < cutoff);
    if (_windows[e.symbol]!.isEmpty) {
      _priceStart[e.symbol] = e.price;
    }
  }

  FlowSnapshot? snapshot(String symbol) {
    final list = _windows[symbol];
    if (list == null || list.isEmpty) return null;

    double total = 0, buy = 0, sell = 0, whaleVol = 0, largest = 0;
    int whales = 0;

    for (final t in list) {
      final v = t.value;
      total += v;
      if (t.isBuyer) buy += v; else sell += v;
      if (v > whaleThreshold) {
        whales++;
        whaleVol += v;
      }
      if (v > largest) largest = v;
    }

    return FlowSnapshot(
      symbol: symbol,
      totalVolume: total,
      buyVolume: buy,
      sellVolume: sell,
      tradeCount: list.length,
      whaleCount: whales,
      whaleVolume: whaleVol,
      largestOrder: largest,
      priceStart: _priceStart[symbol] ?? list.first.price,
      priceNow: list.last.price,
      windowMs: windowSeconds * 1000,
    );
  }

  Set<String> get symbols => _windows.keys.toSet();
}
