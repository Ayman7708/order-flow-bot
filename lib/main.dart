import 'dart:async';
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'flow_engine.dart';
import 'learning_engine.dart';
import 'services.dart';
import 'trade_manager.dart';
import 'whale_detector.dart';
import 'ws_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  Notifications.init();
  runApp(const FlowApp());
}

const List<String> WATCH = [
  'BTCUSDT', 'ETHUSDT', 'SOLUSDT', 'BNBUSDT', 'XRPUSDT',
  'DOGEUSDT', 'ADAUSDT', 'AVAXUSDT', 'LINKUSDT', 'DOTUSDT',
  'MATICUSDT', 'NEARUSDT', 'APTUSDT', 'ARBUSDT', 'OPUSDT',
];

const int LEVERAGE = 7;
const double RISK_PCT = 0.01;
const int LOOP_MS = 2000; // check every 3 sec
const int MAX_POS_PER_SYMBOL = 5;

class FlowApp extends StatelessWidget {
  const FlowApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Order Flow Bot',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0A0E17),
        colorScheme: const ColorScheme.dark(primary: const Color(0xFF4ADE80)),
      ),
      builder: (c, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late TabController _tabs;
  final _ws = WsService();
  final _detector = WhaleDetector(windowSeconds: 8, whaleThreshold: 20000);
  final _learn = LearningEngine();

  double _balance = 1000;
  double _initialBalance = 1000;
  bool _running = false;
  bool _loaded = false;

  final Map<String, List<FlowPosition>> _positions = {};
  final List<FlowTrade> _trades = [];
  final Map<String, FlowSnapshot> _snapshots = {};
  final Map<String, double> _prices = {};

  int _totalTicks = 0;
  int _totalWhales = 0;
  DateTime _startTime = DateTime.now();
  Timer? _loop;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabs = TabController(length: 3, vsync: this);
    _loadState();
    _ws.stream.listen(_onEvent);
    _startTime = DateTime.now();
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    WidgetsBinding.instance.removeObserver(this);
    _loop?.cancel();
    _ws.dispose();
    _tabs.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.inactive) {
      _saveState();
    }
    super.didChangeAppLifecycleState(state);
  }

  Future<void> _loadState() async {
    try {
      final data = await Store.load();
      if (data != null && mounted) {
        setState(() {
          _balance = (data['balance'] as num?)?.toDouble() ?? 1000;
          _initialBalance = (data['initialBalance'] as num?)?.toDouble() ?? 1000;
          final posRaw = (data['positions'] as Map<String, dynamic>?) ?? {};
          _positions.clear();
          posRaw.forEach((k, v) {
            final list = (v as List).map((e) =>
                FlowPosition.fromJson(Map<String, dynamic>.from(e))).toList();
            if (list.isNotEmpty) _positions[k] = list;
          });
          final trRaw = (data['trades'] as List?) ?? [];
          _trades.clear();
          for (final t in trRaw) {
            _trades.add(FlowTrade.fromJson(Map<String, dynamic>.from(t)));
          }
          if (data['learning'] != null) {
            _learn.loadFromJson(Map<String, dynamic>.from(data['learning']));
          }
          _totalWhales = (data['totalWhales'] as num?)?.toInt() ?? 0;
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _loaded = true);
  }

  Future<void> _saveState() async {
    try {
      final posMap = <String, dynamic>{};
      _positions.forEach((k, v) => posMap[k] = v.map((e) => e.toJson()).toList());
      await Store.save({
        'balance': _balance,
        'initialBalance': _initialBalance,
        'positions': posMap,
        'trades': _trades.map((t) => t.toJson()).toList(),
        'learning': _learn.toJson(),
        'totalWhales': _totalWhales,
      });
    } catch (_) {}
  }

  void _onEvent(TradeEvent e) {
    _detector.addEvent(e);
    _prices[e.symbol] = e.price;
    _totalTicks++;
    if (e.value > 20000) _totalWhales++;
  }

  void _toggleBot() {
    if (_running) {
      _loop?.cancel();
      _ws.disconnect();
      setState(() => _running = false);
      WakelockPlus.disable();
    } else {
      setState(() => _running = true);
      WakelockPlus.enable();
      _ws.connect(WATCH);
      _loop = Timer.periodic(const Duration(milliseconds: LOOP_MS), (_) => _tick());
    }
  }

  Future<void> _tick() async {
    if (!mounted) return;
    // Update snapshots for all watched symbols
    for (final s in WATCH) {
      final snap = _detector.snapshot(s);
      if (snap != null) _snapshots[s] = snap;
    }

    // Check SL/TP for open positions
    _checkExits();

    // Look for entries
    if (_running) _lookForEntries();

    setState(() {});
    _saveState();
  }

  void _checkExits() {
    for (final sym in _positions.keys.toList()) {
      final list = _positions[sym]!;
      final price = _prices[sym];
      if (price == null) continue;

      for (int i = list.length - 1; i >= 0; i--) {
        final p = list[i];
        final slHit = p.isLong ? price <= p.stopLoss : price >= p.stopLoss;
        final tpHit = p.isLong ? price >= p.takeProfit : price <= p.takeProfit;

        if (slHit || tpHit) {
          final pnl = p.pnl(price);
          _balance += p.margin + pnl;
          _trades.insert(0, FlowTrade(
            symbol: sym,
            action: slHit ? 'STOP_LOSS' : 'TAKE_PROFIT',
            price: price,
            pnl: pnl,
            time: DateTime.now(),
            isLong: p.isLong,
          ));
          list.removeAt(i);
          _learn.learnFromTrade(_trades.first);
          Notifications.show(
            pnl >= 0 ? '🎯 ربح $sym' : '🛑 خسارة $sym',
            'PnL: \$${pnl.toStringAsFixed(2)} | الرصيد: \$${_balance.toStringAsFixed(2)}',
          );
        }
      }
      if (list.isEmpty) _positions.remove(sym);
      if (_trades.length > 300) _trades.removeLast();
    }
  }

  void _lookForEntries() {
    for (final sym in WATCH) {
      final snap = _snapshots[sym];
      if (snap == null) continue;

      final current = _positions[sym]?.length ?? 0;
      if (current >= MAX_POS_PER_SYMBOL) continue;

      // Rough ATR estimate from price change in window
      final atr = snap.priceNow * 0.002; // 0.2% approximate

      final sig = FlowEngine.analyze(
        snap: snap,
        longThreshold: _learn.longThreshold,
        shortThreshold: _learn.shortThreshold,
        atr1m: atr,
        balance: _balance,
        riskPct: RISK_PCT,
        leverage: LEVERAGE,
      );

      if (!sig.isValid) continue;

      // Learning: skip bad patterns
      final pk = LearningEngine.patternKey(
        whaleSize: snap.largestOrder,
        buyRatio: snap.buyRatio,
        priceChangePct: snap.priceChangePct,
        score: sig.finalScore,
      );
      if (_learn.shouldSkip(pk)) continue;

      // Risk: check balance
      final margin = FlowEngine.calcMargin(
        balance: _balance,
        entry: sig.entry,
        stopLoss: sig.stopLoss,
        leverage: LEVERAGE,
        riskPct: RISK_PCT,
      );
      if (margin <= 0 || margin > _balance) continue;

      _openPosition(sym, sig, margin, snap);
    }
  }

  void _openPosition(String sym, FlowSignal sig, double margin, FlowSnapshot snap) {
    final size = (margin * LEVERAGE) / sig.entry;
    final pos = FlowPosition(
      symbol: sym,
      entry: sig.entry,
      size: size,
      margin: margin,
      stopLoss: sig.stopLoss,
      takeProfit: sig.takeProfit,
      isLong: sig.direction == 'LONG',
      leverage: LEVERAGE,
    );
    _positions.putIfAbsent(sym, () => []).add(pos);
    _balance -= margin;
    _trades.insert(0, FlowTrade(
      symbol: sym,
      action: sig.direction == 'LONG' ? 'BUY' : 'SELL',
      price: sig.entry,
      pnl: 0,
      time: DateTime.now(),
      isLong: sig.direction == 'LONG',
      score: sig.finalScore,
      whaleSize: snap.largestOrder,
      buyRatio: snap.buyRatio,
    ));
    Notifications.show(
      sig.direction == 'LONG' ? '🟢 شراء $sym' : '🔴 بيع $sym',
      'قوة: ${sig.finalScore} | ${sig.reason}',
    );
  }

  void _manualClose(String sym, int idx) {
    final list = _positions[sym];
    if (list == null || idx >= list.length) return;
    final p = list[idx];
    final price = _prices[sym];
    if (price == null) return;
    final pnl = p.pnl(price);
    _balance += p.margin + pnl;
    _trades.insert(0, FlowTrade(
      symbol: sym, action: 'MANUAL', price: price, pnl: pnl,
      time: DateTime.now(), isLong: p.isLong,
    ));
    list.removeAt(idx);
    if (list.isEmpty) _positions.remove(sym);
    _learn.learnFromTrade(_trades.first);
    setState(() {});
    _saveState();
  }

  void _resetAll() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF131A26),
        title: const Text('إعادة تعيين', style: TextStyle(color: Colors.white)),
        content: const Text('سيتم مسح كل البيانات. متأكد؟', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await Store.clear();
              setState(() {
                _balance = 1000;
                _initialBalance = 1000;
                _positions.clear();
                _trades.clear();
                _totalWhales = 0;
                _totalTicks = 0;
                _startTime = DateTime.now();
              });
            },
            child: const Text('نعم', style: TextStyle(color: Color(0xFFEF4444))),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(
        backgroundColor: Color(0xFF0A0E17),
        body: Center(child: CircularProgressIndicator(color: Color(0xFF4ADE80))),
      );
    }
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF131A26),
        elevation: 0,
        title: const Text('Order Flow Bot', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.restart_alt, color: Color(0xFFEF4444)),
            onPressed: _resetAll,
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _ws.isConnected ? const Color(0xFF4ADE80) : const Color(0xFFF59E0B),
              )),
              const SizedBox(width: 6),
              Text(_ws.isConnected ? 'مباشر' : 'انتظار', style: const TextStyle(fontSize: 11)),
            ]),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: const Color(0xFF4ADE80),
          labelColor: const Color(0xFF4ADE80),
          unselectedLabelColor: Colors.white54,
          tabs: const [
            Tab(text: 'الرئيسية'),
            Tab(text: 'السجل'),
            Tab(text: 'التعلم'),
          ],
        ),
      ),
      body: Column(children: [
        _buildBalanceBar(),
        Expanded(child: TabBarView(controller: _tabs, children: [
          _buildMain(),
          _buildTrades(),
          _buildLearning(),
        ])),
        _buildStartBtn(),
      ]),
    );
  }

  Widget _buildBalanceBar() {
    final pnl = _balance - _initialBalance;
    final pct = _initialBalance > 0 ? pnl / _initialBalance * 100 : 0.0;
    final color = pnl >= 0 ? const Color(0xFF4ADE80) : const Color(0xFFEF4444);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [Color(0xFF1E3A2F), Color(0xFF16241C)]),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('الرصيد', style: TextStyle(color: Colors.white54, fontSize: 11)),
          Text('\$${_balance.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF4ADE80))),
        ]),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          const Text('PnL', style: TextStyle(color: Colors.white54, fontSize: 11)),
          Text('${pnl >= 0 ? '+' : ''}\$${pnl.toStringAsFixed(2)}',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color)),
          Text('${pnl >= 0 ? '+' : ''}${pct.toStringAsFixed(2)}%', style: TextStyle(fontSize: 10, color: color)),
        ]),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          const Text('صفقات', style: TextStyle(color: Colors.white54, fontSize: 11)),
          Text('${_trades.where((t) => t.pnl != 0).length}',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF60A5FA))),
          Text('🐋 $_totalWhales', style: const TextStyle(fontSize: 10, color: Color(0xFFF59E0B))),
        ]),
      ]),
    );
  }

  Widget _buildMain() {
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: WATCH.length,
      itemBuilder: (context, i) {
        final sym = WATCH[i];
        final snap = _snapshots[sym];
        final price = _prices[sym];
        final posList = _positions[sym] ?? [];
        final bull = snap?.bullishScore ?? 0;
        final bear = snap?.bearishScore ?? 0;

        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF131A26),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: posList.isNotEmpty
                  ? const Color(0xFF4ADE80).withOpacity(0.4)
                  : const Color(0xFF1E2838),
            ),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Row(children: [
                Text(sym.replaceAll('USDT', ''),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                if (posList.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4ADE80).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('${posList.length}', style: const TextStyle(fontSize: 10, color: Color(0xFF4ADE80))),
                  ),
                ],
              ]),
              Text(price != null ? '\$${price.toStringAsFixed(price < 1 ? 5 : 2)}' : '...',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13, color: Color(0xFF60A5FA))),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(child: _scoreBar('شراء', bull, const Color(0xFF4ADE80))),
              const SizedBox(width: 6),
              Expanded(child: _scoreBar('بيع', bear, const Color(0xFFEF4444))),
            ]),
            if (snap != null && snap.whaleCount > 0) ...[
              const SizedBox(height: 4),
              Text('🐋 ${snap.whaleCount} أمر كبير | ${(snap.buyRatio * 100).toInt()}% شراء | حركة ${snap.priceChangePct.toStringAsFixed(2)}%',
                  style: const TextStyle(fontSize: 10, color: Color(0xFF8892A6))),
            ],
            if (posList.isNotEmpty) ...[
              const SizedBox(height: 6),
              for (int j = 0; j < posList.length; j++)
                _positionRow(sym, j, posList[j], price ?? posList[j].entry),
            ],
          ]),
        );
      },
    );
  }

  Widget _scoreBar(String label, int score, Color color) {
    return Row(children: [
      SizedBox(width: 35, child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold))),
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: score / 100,
            minHeight: 6,
            backgroundColor: const Color(0xFF1A2332),
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ),
      const SizedBox(width: 6),
      Text('$score', style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
    ]);
  }

  Widget _positionRow(String sym, int idx, FlowPosition p, double price) {
    final pnl = p.pnl(price);
    final color = pnl >= 0 ? const Color(0xFF4ADE80) : const Color(0xFFEF4444);
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2332),
        borderRadius: BorderRadius.circular(6),
        border: Border(right: BorderSide(color: p.isLong ? const Color(0xFF4ADE80) : const Color(0xFFEF4444), width: 2)),
      ),
      child: Row(children: [
        Text(p.isLong ? 'L' : 'S',
            style: TextStyle(color: p.isLong ? const Color(0xFF4ADE80) : const Color(0xFFEF4444),
                fontSize: 11, fontWeight: FontWeight.bold)),
        const SizedBox(width: 6),
        Expanded(child: Text('@\$${p.entry.toStringAsFixed(price < 1 ? 5 : 2)}',
            style: const TextStyle(fontSize: 10, color: Color(0xFF8892A6)))),
        Text('${pnl >= 0 ? '+' : ''}\$${pnl.toStringAsFixed(2)}',
            style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
        const SizedBox(width: 4),
        GestureDetector(
          onTap: () => _manualClose(sym, idx),
          child: const Icon(Icons.close, size: 16, color: Color(0xFFEF4444)),
        ),
      ]),
    );
  }

  Widget _buildTrades() {
    final closed = _trades.where((t) => t.pnl != 0).toList();
    final wins = closed.where((t) => t.pnl > 0).length;
    final losses = closed.where((t) => t.pnl < 0).length;
    final totalPnl = closed.fold<double>(0, (s, t) => s + t.pnl);
    final wr = closed.isEmpty ? 0.0 : wins / closed.length * 100;

    return Column(children: [
      Container(
        margin: const EdgeInsets.all(8),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF131A26),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF60A5FA)),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          _stat('رابحة', '$wins', const Color(0xFF4ADE80)),
          _stat('خاسرة', '$losses', const Color(0xFFEF4444)),
          _stat('نجاح', '${wr.toStringAsFixed(0)}%', const Color(0xFFF59E0B)),
          _stat('PnL', '${totalPnl >= 0 ? "+" : ""}\$${totalPnl.toStringAsFixed(1)}',
              totalPnl >= 0 ? const Color(0xFF4ADE80) : const Color(0xFFEF4444)),
        ]),
      ),
      Expanded(
        child: _trades.isEmpty
            ? const Center(child: Text('لا توجد صفقات', style: TextStyle(color: Color(0xFF4B5563))))
            : ListView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: _trades.length,
                itemBuilder: (c, i) {
                  final t = _trades[i];
                  Color color = const Color(0xFF4ADE80);
                  String label = 'شراء';
                  if (t.action == 'SELL') { color = const Color(0xFFEF4444); label = 'بيع'; }
                  if (t.action == 'STOP_LOSS') { color = const Color(0xFFDC2626); label = 'وقف'; }
                  if (t.action == 'TAKE_PROFIT') { color = const Color(0xFF16A34A); label = 'هدف'; }
                  if (t.action == 'MANUAL') { color = const Color(0xFF60A5FA); label = 'يدوي'; }
                  return Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A2332),
                      borderRadius: BorderRadius.circular(6),
                      border: Border(right: BorderSide(color: color, width: 2)),
                    ),
                    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('$label ${t.symbol}',
                            style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
                        Text('${t.time.hour}:${t.time.minute.toString().padLeft(2, '0')} | \$${t.price.toStringAsFixed(t.price < 1 ? 5 : 2)}',
                            style: const TextStyle(color: Color(0xFF8892A6), fontSize: 10)),
                      ]),
                      if (t.pnl != 0)
                        Text('${t.pnl >= 0 ? '+' : ''}\$${t.pnl.toStringAsFixed(2)}',
                            style: TextStyle(color: t.pnl >= 0 ? const Color(0xFF4ADE80) : const Color(0xFFEF4444),
                                fontWeight: FontWeight.bold, fontSize: 12)),
                    ]),
                  );
                },
              ),
      ),
    ]);
  }

  Widget _stat(String label, String value, Color color) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(value, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.bold)),
      Text(label, style: const TextStyle(color: Color(0xFF8892A6), fontSize: 10)),
    ]);
  }

  Widget _buildLearning() {
    final wr = _learn.totalTrades == 0 ? 0.0 : _learn.winRate * 100;
    final goodPats = _learn.patterns.values.where((p) => p.isGood).length;
    final badPats = _learn.patterns.values.where((p) => p.isBad).length;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF131A26),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF60A5FA)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('🧠 نظام التعلم الذكي',
                style: TextStyle(color: Color(0xFF60A5FA), fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 8),
            _row('إجمالي الصفقات', '${_learn.totalTrades}'),
            _row('رابحة / خاسرة', '${_learn.totalWins} / ${_learn.totalLosses}'),
            _row('نسبة النجاح', '${wr.toStringAsFixed(1)}%'),
            _row('الربح التراكمي', '\$${_learn.cumulativePnl.toStringAsFixed(2)}'),
            _row('خسائر متتالية', '${_learn.consecutiveLosses}'),
            _row('انتصارات متتالية', '${_learn.consecutiveWins}'),
          ]),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF131A26),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFF59E0B)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('⚙️ العتبات المتكيفة',
                style: TextStyle(color: Color(0xFFF59E0B), fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 8),
            _row('عتبة الشراء', '${_learn.longThreshold}'),
            _row('عتبة البيع', '${_learn.shortThreshold}'),
            const SizedBox(height: 8),
            const Text('📊 الأوزان', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
            _row('وزن الحوت', _learn.whaleWeight.toStringAsFixed(2)),
            _row('وزن نسبة الشراء', _learn.buyRatioWeight.toStringAsFixed(2)),
            _row('وزن الزخم', _learn.momentumWeight.toStringAsFixed(2)),
          ]),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF131A26),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF4ADE80)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('📚 الأنماط المحفوظة',
                style: TextStyle(color: Color(0xFF4ADE80), fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 8),
            _row('إجمالي الأنماط', '${_learn.patterns.length}'),
            _row('✅ أنماط ناجحة', '$goodPats', color: const Color(0xFF4ADE80)),
            _row('❌ أنماط فاشلة', '$badPats', color: const Color(0xFFEF4444)),
            const SizedBox(height: 6),
            const Text('الأنماط الفاشلة يتم تجاهلها تلقائياً',
                style: TextStyle(color: Color(0xFF8892A6), fontSize: 10)),
          ]),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF131A26),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF1E2838)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('📡 إحصائيات الاتصال',
                style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 8),
            _row('Ticks المستلمة', '$_totalTicks'),
            _row('الأوامر الكبيرة', '$_totalWhales'),
            _row('حالة الاتصال', _ws.isConnected ? 'متصل ✅' : 'منقطع ❌',
                color: _ws.isConnected ? const Color(0xFF4ADE80) : const Color(0xFFEF4444)),
            _row('مدة التشغيل', _uptime()),
          ]),
        ),
      ],
    );
  }

  String _uptime() {
    final d = DateTime.now().difference(_startTime);
    if (d.inHours > 0) return '${d.inHours}س ${d.inMinutes % 60}د';
    if (d.inMinutes > 0) return '${d.inMinutes}د ${d.inSeconds % 60}ث';
    return '${d.inSeconds}ث';
  }

  Widget _row(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        Text(value, style: TextStyle(color: color ?? const Color(0xFF60A5FA), fontSize: 12, fontFamily: 'monospace')),
      ]),
    );
  }

  Widget _buildStartBtn() {
    return Container(
      padding: const EdgeInsets.all(10),
      color: const Color(0xFF131A26),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: _running ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: _toggleBot,
          child: Text(
            _running ? '⏹ إيقاف البوت' : '▶ بدء البوت',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ),
      ),
    );
  }
}
