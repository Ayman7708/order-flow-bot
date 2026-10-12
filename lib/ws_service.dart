import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Single aggTrade event from Binance
class TradeEvent {
  final String symbol;
  final double price;
  final double quantity;
  final bool isBuyer; // true = buy, false = sell
  final int time; // ms
  TradeEvent({
    required this.symbol,
    required this.price,
    required this.quantity,
    required this.isBuyer,
    required this.time,
  });

  double get value => price * quantity; // USD value
}

/// WebSocket service - connects to Binance futures aggTrade stream
class WsService {
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _reconnect;
  final Set<String> _symbols = {};
  final _controller = StreamController<TradeEvent>.broadcast();
  bool _connected = false;

  Stream<TradeEvent> get stream => _controller.stream;
  bool get isConnected => _connected;

  /// Connect to combined stream of symbols
  /// Example: BTCUSDT, ETHUSDT -> btcusdt@aggTrade/ethusdt@aggTrade
  void connect(List<String> symbols) {
    _symbols.clear();
    _symbols.addAll(symbols.map((s) => s.toLowerCase()));
    _openConnection();
  }

  void _openConnection() {
    if (_symbols.isEmpty) return;
    _sub?.cancel();
    try {
      _channel?.sink.close();
    } catch (_) {}

    final streams = _symbols.map((s) => '$s@aggTrade').join('/');
    final url = 'wss://fstream.binance.com/stream?streams=$streams';
    debugPrint('🔌 WS connecting: ${_symbols.length} symbols');

    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));
      _connected = true;
      _sub = _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
        cancelOnError: false,
      );
    } catch (e) {
      debugPrint('WS error: $e');
      _connected = false;
      _scheduleReconnect();
    }
  }

  void _onMessage(dynamic data) {
    try {
      final raw = data is String ? data : utf8.decode(data);
      debugPrint('WS RAW: ${raw.substring(0, raw.length > 200 ? 200 : raw.length)}');
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final d = json['data'] as Map<String, dynamic>?;
      if (d == null) {
        debugPrint('No data field');
        return;
      }

      final symbol = (d['s'] as String?) ?? '';
      if (symbol.isEmpty) return;

      final price = double.tryParse(d['p'].toString()) ?? 0;
      final qty = double.tryParse(d['q'].toString()) ?? 0;
      final isBuyer = (d['m'] as bool?) == false; // 'm' true means buyer is market maker = sell
      final time = (d['T'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;

      if (price <= 0 || qty <= 0) return;

      _controller.add(TradeEvent(
        symbol: symbol,
        price: price,
        quantity: qty,
        isBuyer: isBuyer,
        time: time,
      ));
    } catch (_) {}
  }

  void _onError(dynamic e) {
    debugPrint('WS stream error: $e');
    _connected = false;
    _scheduleReconnect();
  }

  void _onDone() {
    debugPrint('WS closed');
    _connected = false;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _reconnect?.cancel();
    _reconnect = Timer(const Duration(seconds: 5), () {
      if (!_connected && _symbols.isNotEmpty) {
        debugPrint('WS reconnecting...');
        _openConnection();
      }
    });
  }

  void disconnect() {
    _reconnect?.cancel();
    _sub?.cancel();
    try {
      _channel?.sink.close();
    } catch (_) {}
    _connected = false;
    _symbols.clear();
  }

  void dispose() {
    disconnect();
    _controller.close();
  }
}
