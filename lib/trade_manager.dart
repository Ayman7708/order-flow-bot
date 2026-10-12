class FlowPosition {
  final String symbol;
  final double entry;
  final double size;      // contract qty
  final double margin;
  final double stopLoss;
  final double takeProfit;
  final bool isLong;
  final int leverage;
  final DateTime openedAt;

  FlowPosition({
    required this.symbol,
    required this.entry,
    required this.size,
    required this.margin,
    required this.stopLoss,
    required this.takeProfit,
    required this.isLong,
    required this.leverage,
    DateTime? openedAt,
  }) : openedAt = openedAt ?? DateTime.now();

  double pnl(double current) =>
      isLong ? (current - entry) * size : (entry - current) * size;

  Map<String, dynamic> toJson() => {
        'symbol': symbol,
        'entry': entry,
        'size': size,
        'margin': margin,
        'stopLoss': stopLoss,
        'takeProfit': takeProfit,
        'isLong': isLong,
        'leverage': leverage,
        'openedAt': openedAt.toIso8601String(),
      };

  factory FlowPosition.fromJson(Map<String, dynamic> j) => FlowPosition(
        symbol: j['symbol'],
        entry: (j['entry'] as num).toDouble(),
        size: (j['size'] as num).toDouble(),
        margin: (j['margin'] as num).toDouble(),
        stopLoss: (j['stopLoss'] as num).toDouble(),
        takeProfit: (j['takeProfit'] as num).toDouble(),
        isLong: j['isLong'] ?? true,
        leverage: (j['leverage'] as num?)?.toInt() ?? 3,
        openedAt: DateTime.tryParse(j['openedAt'] ?? '') ?? DateTime.now(),
      );
}

class FlowTrade {
  final String symbol;
  final String action;      // BUY, SELL, STOP_LOSS, TAKE_PROFIT, MANUAL
  final double price;
  final double pnl;
  final DateTime time;
  final bool isLong;
  final int score;          // signal score when opened
  final double whaleSize;   // largest whale during entry
  final double buyRatio;

  FlowTrade({
    required this.symbol,
    required this.action,
    required this.price,
    required this.pnl,
    required this.time,
    required this.isLong,
    this.score = 0,
    this.whaleSize = 0,
    this.buyRatio = 0.5,
  });

  Map<String, dynamic> toJson() => {
        'symbol': symbol,
        'action': action,
        'price': price,
        'pnl': pnl,
        'time': time.toIso8601String(),
        'isLong': isLong,
        'score': score,
        'whaleSize': whaleSize,
        'buyRatio': buyRatio,
      };

  factory FlowTrade.fromJson(Map<String, dynamic> j) => FlowTrade(
        symbol: j['symbol'],
        action: j['action'],
        price: (j['price'] as num).toDouble(),
        pnl: (j['pnl'] as num).toDouble(),
        time: DateTime.tryParse(j['time'] ?? '') ?? DateTime.now(),
        isLong: j['isLong'] ?? true,
        score: (j['score'] as num?)?.toInt() ?? 0,
        whaleSize: (j['whaleSize'] as num?)?.toDouble() ?? 0,
        buyRatio: (j['buyRatio'] as num?)?.toDouble() ?? 0.5,
      );
}
