with open('lib/main.dart', 'r', encoding='utf-8') as f:
    src = f.read()

checks = []

# Import bg_service
if "import 'bg_service.dart';" not in src:
    src = src.replace(
        "import 'whale_detector.dart';",
        "import 'whale_detector.dart';\nimport 'bg_service.dart';\nimport 'package:connectivity_plus/connectivity_plus.dart';"
    )
    checks.append(('import bg_service', "import 'bg_service.dart';" in src))
else:
    checks.append(('import bg_service', True))

# Add connectivity state
if '_hasInternet' not in src:
    src = src.replace(
        "  int _totalTicks = 0;",
        "  bool _hasInternet = true;\n  StreamSubscription? _connSub;\n  int _totalTicks = 0;"
    )
    checks.append(('connectivity state', '_hasInternet' in src))
else:
    checks.append(('connectivity state', True))

# Init connectivity in initState
old_init = """    _loadState();
    _ws.stream.listen(_onEvent);
    _startTime = DateTime.now();"""

new_init = """    _loadState();
    _ws.stream.listen(_onEvent);
    _startTime = DateTime.now();
    // Init background service
    initBackgroundService();
    // Listen to connectivity
    _connSub = Connectivity().onConnectivityChanged.listen((results) {
      final has = results.any((r) => r != ConnectivityResult.none);
      if (has != _hasInternet) {
        setState(() => _hasInternet = has);
        if (has && _running) {
          // Reconnect when internet is back
          _ws.connect(WATCH);
        }
        Notifications.show(
          has ? '🌐 عاد الإنترنت' : '📵 انقطع الإنترنت',
          has ? 'البوت استأنف العمل' : 'البوت ينتظر الاتصال',
        );
      }
    });"""

if old_init in src:
    src = src.replace(old_init, new_init)
    checks.append(('init connectivity', '_connSub = Connectivity()' in src))
else:
    checks.append(('init connectivity', False))

# Update dispose
src = src.replace(
    "    WakelockPlus.disable();\n    WidgetsBinding.instance.removeObserver(this);\n    _loop?.cancel();",
    "    _connSub?.cancel();\n    WidgetsBinding.instance.removeObserver(this);\n    _loop?.cancel();"
)

# Update _toggleBot to use background service
old_toggle = """  void _toggleBot() {
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
  }"""

new_toggle = """  Future<void> _toggleBot() async {
    if (_running) {
      _loop?.cancel();
      _ws.disconnect();
      setState(() => _running = false);
      WakelockPlus.disable();
      await stopBgService();
      Notifications.show('⏹ إيقاف البوت', 'توقف التداول');
    } else {
      setState(() => _running = true);
      WakelockPlus.enable();
      await startBgService();
      _ws.connect(WATCH);
      _loop = Timer.periodic(const Duration(milliseconds: LOOP_MS), (_) => _tick());
      Notifications.show('▶ بدء البوت', 'يعمل الآن في الخلفية 24/7');
    }
  }"""

if old_toggle in src:
    src = src.replace(old_toggle, new_toggle)
    checks.append(('toggle bg service', 'await startBgService()' in src))
else:
    checks.append(('toggle bg service', False))

# Auto-restart on app open if was running
old_after_load = """    if (mounted) setState(() => _loaded = true);
  }

  Future<void> _saveState() async {"""

new_after_load = """    if (mounted) setState(() => _loaded = true);
    // Auto-restart if was running before
    try {
      final data = await Store.load();
      if (data != null && data['wasRunning'] == true) {
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted && !_running) _toggleBot();
        });
      }
    } catch (_) {}
  }

  Future<void> _saveState() async {"""

if old_after_load in src:
    src = src.replace(old_after_load, new_after_load)
    checks.append(('auto restart', 'wasRunning' in src))
else:
    checks.append(('auto restart', False))

# Save wasRunning state
src = src.replace(
    "'totalWhales': _totalWhales,\n      });",
    "'totalWhales': _totalWhales,\n        'wasRunning': _running,\n      });"
)

with open('lib/main.dart', 'w', encoding='utf-8') as f:
    f.write(src)

print('=== Integration Results ===')
for name, ok in checks:
    print(('✅' if ok else '❌') + ' ' + name)
print('===========================')

with open('lib/main.dart', 'r', encoding='utf-8') as f:
    final = f.read()
print(f"Braces: {final.count('{')} / {final.count('}')}")
