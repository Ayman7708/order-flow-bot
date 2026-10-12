import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class TradeEvent {
  final String symbol;
  final double price;
  final double quantity;
  final bool isBuyer;
  final int time;
  TradeEvent({
    required this.symbol,
    required this.price,
    required this.quantity,
    required this.isBuyer,
    required this.time,
  });
  double get value => price * quantity;
}

/// REST Polling service - uses Binance aggTrades endpoint
/// Polls every 2 seconds for each symbol (in parallel)
class WsService {
  Timer? _pollTimer;
  Timer? _symbolRotate;
  final Set<String> _symbols = {};
  final _controller = StreamController<TradeEvent>.broadcast();
  bool _connected = false;
  int _consecutiveErrors = 0;
  int _lastPollCount = 0;
  final Map<String, int> _lastId = {};

  Stream<TradeEvent> get stream => _controller.stream;
  bool get isConnected => _connected;
  int get lastPollCount => _lastPollCount;

  void connect(List<String> symbols) {
    _symbols.clear();
    _symbols.addAll(symbols.map((s) => s.toUpperCase()));
    _connected = true;
    _startPolling();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _poll());
  }

  Future<void> _poll() async {
    if (_symbols.isEmpty) return;

    // Poll all symbols in parallel
    final futures = _symbols.map((s) => _fetchAggTrades(s)).toList();
    final results = await Future.wait(futures);

    int count = 0;
    int errors = 0;
    for (final r in results) {
      if (r == null) { errors++; continue; }
      count += r;
    }
    _lastPollCount = count;
    _consecutiveErrors = errors;

    if (errors == _symbols.length) {
      // All failed
      _connected = false;
    } else {
      _connected = true;
    }
  }

  Future<int?> _fetchAggTrades(String symbol) async {
    try {
      // Binance futures aggTrades endpoint
      // Get last 100 trades in last 2 seconds
      final since = DateTime.now().millisecondsSinceEpoch - 2000;
      final url = Uri.parse(
        'https://fapi.binance.com/fapi/v1/aggTrades?symbol=$symbol&startTime=$since&limit=100',
      );
      final res = await http.get(url).timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) return null;

      final List data = json.decode(res.body) as List;
      if (data.isEmpty) return 0;

      for (final item in data) {
        try {
          final price = double.tryParse(item['p'].toString()) ?? 0;
          final qty = double.tryParse(item['q'].toString()) ?? 0;
          final time = (item['T'] as num?)?.toInt() ?? 0;
          final isBuyerMaker = item['m'] as bool? ?? false;

          if (price <= 0 || qty <= 0) continue;

          _controller.add(TradeEvent(
            symbol: symbol,
            price: price,
            quantity: qty,
            isBuyer: !isBuyerMaker,
            time: time,
          ));
        } catch (_) {}
      }
      return data.length;
    } catch (e) {
      debugPrint('Poll error $symbol: $e');
      return null;
    }
  }

  void disconnect() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _connected = false;
    _symbols.clear();
  }

  void dispose() {
    disconnect();
    _controller.close();
  }
}
