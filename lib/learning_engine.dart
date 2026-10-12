import 'dart:math';
import 'trade_manager.dart';

/// A recorded pattern - when X happens, we usually win/lose
class Pattern {
  final String key;         // e.g. "WHALE>200K|BR>0.6|PUMP"
  int wins;
  int losses;
  double avgPnl;
  DateTime lastSeen;

  Pattern({
    required this.key,
    this.wins = 0,
    this.losses = 0,
    this.avgPnl = 0,
    DateTime? lastSeen,
  }) : lastSeen = lastSeen ?? DateTime.now();

  double get winRate => (wins + losses) == 0 ? 0 : wins / (wins + losses);
  int get total => wins + losses;
  bool get isReliable => total >= 3;
  bool get isBad => isReliable && winRate < 0.35;
  bool get isGood => isReliable && winRate > 0.60;

  Map<String, dynamic> toJson() => {
        'key': key,
        'wins': wins,
        'losses': losses,
        'avgPnl': avgPnl,
        'lastSeen': lastSeen.toIso8601String(),
      };

  factory Pattern.fromJson(Map<String, dynamic> j) => Pattern(
        key: j['key'],
        wins: j['wins'] ?? 0,
        losses: j['losses'] ?? 0,
        avgPnl: (j['avgPnl'] as num?)?.toDouble() ?? 0,
        lastSeen: DateTime.tryParse(j['lastSeen'] ?? '') ?? DateTime.now(),
      );
}

/// 5-layer adaptive learning engine
class LearningEngine {
  // Weights for decision criteria
  double whaleWeight = 1.0;
  double buyRatioWeight = 1.0;
  double momentumWeight = 1.0;
  double volumeWeight = 1.0;
  double btcAlignWeight = 1.0;

  // Score thresholds (adaptive)
  int longThreshold = 65;
  int shortThreshold = 65;

  // Stats
  int totalTrades = 0;
  int totalWins = 0;
  int totalLosses = 0;
  double cumulativePnl = 0;
  int consecutiveLosses = 0;
  int consecutiveWins = 0;

  // Patterns
  final Map<String, Pattern> patterns = {};

  // Market state tracking
  String lastMarketState = 'unknown';

  double get winRate => totalTrades == 0 ? 0 : totalWins / totalTrades;

  /// Build pattern key from trade features
  static String patternKey({
    required double whaleSize,
    required double buyRatio,
    required double priceChangePct,
    required int score,
  }) {
    String w;
    if (whaleSize > 300000) w = 'W5';
    else if (whaleSize > 150000) w = 'W4';
    else if (whaleSize > 75000) w = 'W3';
    else if (whaleSize > 30000) w = 'W2';
    else w = 'W1';

    String b;
    if (buyRatio > 0.7) b = 'B4';
    else if (buyRatio > 0.6) b = 'B3';
    else if (buyRatio > 0.5) b = 'B2';
    else if (buyRatio > 0.4) b = 'B1';
    else b = 'B0';

    String m;
    if (priceChangePct > 0.3) m = 'P3';
    else if (priceChangePct > 0.1) m = 'P2';
    else if (priceChangePct > 0) m = 'P1';
    else if (priceChangePct > -0.1) m = 'M1';
    else if (priceChangePct > -0.3) m = 'M2';
    else m = 'M3';

    String s;
    if (score >= 80) s = 'S4';
    else if (score >= 70) s = 'S3';
    else if (score >= 60) s = 'S2';
    else s = 'S1';

    return '$w|$b|$m|$s';
  }

  /// Check if pattern is known to be bad
  bool shouldSkip(String patternKey) {
    final p = patterns[patternKey];
    if (p == null) return false;
    return p.isBad;
  }

  /// Learn from a closed trade
  void learnFromTrade(FlowTrade trade) {
    totalTrades++;
    cumulativePnl += trade.pnl;

    final patternKeyStr = patternKey(
      whaleSize: trade.whaleSize,
      buyRatio: trade.buyRatio,
      priceChangePct: 0,
      score: trade.score,
    );

    final p = patterns.putIfAbsent(patternKeyStr, () => Pattern(key: patternKeyStr));
    if (trade.pnl > 0) {
      p.wins++;
      totalWins++;
      consecutiveWins++;
      consecutiveLosses = 0;
    } else if (trade.pnl < 0) {
      p.losses++;
      totalLosses++;
      consecutiveLosses++;
      consecutiveWins = 0;
    }
    final n = p.wins + p.losses;
    if (n > 0) {
      p.avgPnl = ((p.avgPnl * (n - 1)) + trade.pnl) / n;
    }
    p.lastSeen = DateTime.now();

    // ============ AUTO-ADJUST WEIGHTS ============
    _adjustWeights(trade);

    // ============ AUTO-ADJUST THRESHOLDS ============
    _adjustThresholds();

    // ============ CLEANUP ============
    if (patterns.length > 300) {
      // Remove oldest/worst patterns
      final list = patterns.values.toList()
        ..sort((a, b) => a.winRate.compareTo(b.winRate));
      for (int i = 0; i < 50; i++) {
        patterns.remove(list[i].key);
      }
    }
  }

  void _adjustWeights(FlowTrade trade) {
    final win = trade.pnl > 0;
    final delta = win ? 1.03 : 0.97;

    if (trade.whaleSize > 100000) whaleWeight = _clamp(whaleWeight * delta);
    if (trade.buyRatio > 0.6 || trade.buyRatio < 0.4) {
      buyRatioWeight = _clamp(buyRatioWeight * delta);
    }
    if (trade.score >= 70) {
      momentumWeight = _clamp(momentumWeight * delta);
    }
  }

  void _adjustThresholds() {
    if (totalTrades < 5) return;

    if (winRate < 0.35) {
      longThreshold = min(85, longThreshold + 2);
      shortThreshold = min(85, shortThreshold + 2);
    } else if (winRate > 0.60) {
      longThreshold = max(50, longThreshold - 1);
      shortThreshold = max(50, shortThreshold - 1);
    }

    // Consecutive losses - be more careful
    if (consecutiveLosses >= 3) {
      longThreshold = min(90, longThreshold + 3);
      shortThreshold = min(90, shortThreshold + 3);
    }
  }

  double _clamp(double v) => v.clamp(0.3, 3.0).toDouble();

  /// Compute boost for a signal based on weights
  int computeWeightedScore({
    required int rawScore,
    required double whaleSize,
    required double buyRatio,
    required double priceChangePct,
  }) {
    double s = rawScore.toDouble();
    s *= whaleWeight * 0.9 + buyRatioWeight * 0.1;
    if (whaleSize > 200000) s += 5;
    if (priceChangePct > 0.3) s += 5;
    return s.clamp(0, 100).toInt();
  }

  Map<String, dynamic> toJson() => {
        'whaleWeight': whaleWeight,
        'buyRatioWeight': buyRatioWeight,
        'momentumWeight': momentumWeight,
        'volumeWeight': volumeWeight,
        'btcAlignWeight': btcAlignWeight,
        'longThreshold': longThreshold,
        'shortThreshold': shortThreshold,
        'totalTrades': totalTrades,
        'totalWins': totalWins,
        'totalLosses': totalLosses,
        'cumulativePnl': cumulativePnl,
        'patterns': patterns.map((k, v) => MapEntry(k, v.toJson())),
      };

  void loadFromJson(Map<String, dynamic> j) {
    try {
      whaleWeight = (j['whaleWeight'] as num?)?.toDouble() ?? 1.0;
      buyRatioWeight = (j['buyRatioWeight'] as num?)?.toDouble() ?? 1.0;
      momentumWeight = (j['momentumWeight'] as num?)?.toDouble() ?? 1.0;
      volumeWeight = (j['volumeWeight'] as num?)?.toDouble() ?? 1.0;
      btcAlignWeight = (j['btcAlignWeight'] as num?)?.toDouble() ?? 1.0;
      longThreshold = (j['longThreshold'] as num?)?.toInt() ?? 65;
      shortThreshold = (j['shortThreshold'] as num?)?.toInt() ?? 65;
      totalTrades = (j['totalTrades'] as num?)?.toInt() ?? 0;
      totalWins = (j['totalWins'] as num?)?.toInt() ?? 0;
      totalLosses = (j['totalLosses'] as num?)?.toInt() ?? 0;
      cumulativePnl = (j['cumulativePnl'] as num?)?.toDouble() ?? 0;
      if (j['patterns'] != null) {
        patterns.clear();
        (j['patterns'] as Map).forEach((k, v) {
          patterns[k.toString()] = Pattern.fromJson(Map<String, dynamic>.from(v));
        });
      }
    } catch (_) {}
  }
}
