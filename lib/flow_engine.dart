import 'dart:math';
import 'whale_detector.dart';

class FlowSignal {
  final String symbol;
  final String direction;   // LONG, SHORT, NONE
  final int rawScore;
  final int finalScore;
  final double entry;
  final double stopLoss;
  final double takeProfit;
  final String reason;
  final FlowSnapshot snapshot;

  FlowSignal({
    required this.symbol,
    required this.direction,
    required this.rawScore,
    required this.finalScore,
    required this.entry,
    required this.stopLoss,
    required this.takeProfit,
    required this.reason,
    required this.snapshot,
  });

  bool get isValid => direction != 'NONE' && finalScore >= 60;
}

class FlowEngine {
  /// Generate signal from flow snapshot
  static FlowSignal analyze({
    required FlowSnapshot snap,
    required int longThreshold,
    required int shortThreshold,
    required double atr1m,   // ATR of 1m candles in price units
    required double balance,
    required double riskPct,
    required int leverage,
  }) {
    final bull = snap.bullishScore;
    final bear = snap.bearishScore;

    final minVol = 20000.0;
    if (snap.totalVolume < minVol) {
      return FlowSignal(
        symbol: snap.symbol, direction: 'NONE',
        rawScore: 0, finalScore: 0,
        entry: snap.priceNow, stopLoss: 0, takeProfit: 0,
        reason: 'حجم ضعيف', snapshot: snap,
      );
    }

    final reasons = <String>[];
    if (snap.whaleCount > 0) reasons.add('🐋${snap.whaleCount}');
    reasons.add('شراء:${(snap.buyRatio * 100).toInt()}%');
    if (snap.priceChangePct.abs() > 0.05) {
      reasons.add('حركة:${snap.priceChangePct.toStringAsFixed(2)}%');
    }

    if (bull >= longThreshold && bull > bear) {
      final sl = snap.priceNow - atr1m * 1.5;
      final tp = snap.priceNow + atr1m * 2.5;
      return FlowSignal(
        symbol: snap.symbol, direction: 'LONG',
        rawScore: bull, finalScore: bull,
        entry: snap.priceNow, stopLoss: sl, takeProfit: tp,
        reason: reasons.join(' | '), snapshot: snap,
      );
    }

    if (bear >= shortThreshold && bear > bull) {
      final sl = snap.priceNow + atr1m * 1.5;
      final tp = snap.priceNow - atr1m * 2.5;
      return FlowSignal(
        symbol: snap.symbol, direction: 'SHORT',
        rawScore: bear, finalScore: bear,
        entry: snap.priceNow, stopLoss: sl, takeProfit: tp,
        reason: reasons.join(' | '), snapshot: snap,
      );
    }

    return FlowSignal(
      symbol: snap.symbol, direction: 'NONE',
      rawScore: max(bull, bear), finalScore: max(bull, bear),
      entry: snap.priceNow, stopLoss: 0, takeProfit: 0,
      reason: reasons.join(' | '), snapshot: snap,
    );
  }

  /// Calculate position margin based on risk
  static double calcMargin({
    required double balance,
    required double entry,
    required double stopLoss,
    required int leverage,
    required double riskPct,
  }) {
    if (entry <= 0 || entry == stopLoss) return 0;
    final riskUsdt = balance * riskPct;
    final slDistPct = (entry - stopLoss).abs() / entry;
    if (slDistPct < 0.0005) return 0;
    final posValue = riskUsdt / slDistPct;
    final margin = posValue / leverage;
    final maxMargin = balance * 0.03;
    return margin > maxMargin ? maxMargin : margin;
  }
}
