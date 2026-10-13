with open('lib/main.dart', 'r', encoding='utf-8') as f:
    src = f.read()

checks = []

# 1) Remove auto-init of background service
old_init = """    // Init background service
    initBackgroundService();
    // Listen to connectivity"""
new_init = """    // Listen to connectivity"""
if old_init in src:
    src = src.replace(old_init, new_init)
    print("✅ Removed auto-init background service")
    checks.append(('auto-init removed', True))
else:
    print("⚠️ Auto-init not found")
    checks.append(('auto-init removed', False))

# 2) Move initBackgroundService to _toggleBot (only when user presses)
old_toggle = """      setState(() => _running = true);
      WakelockPlus.enable();
      await startBgService();"""
new_toggle = """      setState(() => _running = true);
      WakelockPlus.enable();
      // Init and start background service (only when user presses start)
      try {
        await initBackgroundService();
        await Future.delayed(const Duration(milliseconds: 300));
        await startBgService();
      } catch (e) {
        debugPrint('BG service start error: $e');
      }"""
if old_toggle in src:
    src = src.replace(old_toggle, new_toggle)
    print("✅ Moved init to _toggleBot")
    checks.append(('init moved', True))
else:
    print("⚠️ Toggle pattern not found")
    checks.append(('init moved', False))

# 3) Wrap the whole initState in try/catch to prevent crashes
old_initstate_start = """  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabs = TabController(length: 3, vsync: this);"""
new_initstate_start = """  @override
  void initState() {
    super.initState();
    try {
      _safeInit();
    } catch (e) {
      debugPrint('Init error: $e');
      _loaded = true;
    }
  }

  void _safeInit() {
    WidgetsBinding.instance.addObserver(this);
    _tabs = TabController(length: 3, vsync: this);"""
if old_initstate_start in src:
    src = src.replace(old_initstate_start, new_initstate_start)
    print("✅ Wrapped initState in try/catch")
    checks.append(('initState try/catch', True))
else:
    print("⚠️ initState pattern not found")
    checks.append(('initState try/catch', False))

# 4) Wrap the state loading in try/catch too (already done, but verify)
if '_loadState().then' in src or '_loadState();' in src:
    print("✅ _loadState still present")
    checks.append(('loadState exists', True))

with open('lib/main.dart', 'w', encoding='utf-8') as f:
    f.write(src)

print('\n=== Fix Results ===')
for name, ok in checks:
    print(('✅' if ok else '❌') + ' ' + name)

# Verify braces
with open('lib/main.dart', 'r', encoding='utf-8') as f:
    final = f.read()
print(f"\nBraces: {final.count('{')} / {final.count('}')}")
