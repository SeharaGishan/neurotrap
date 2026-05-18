import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:url_launcher/url_launcher.dart';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';
import '../alerts/alerts_screen.dart';
import '../about/about_screen.dart';
import '../contacts/contacts_screen.dart';
import '../license/license_screen.dart';

import '../settings/settings_screen.dart';
import '../../services/background_service.dart';

const String _osBase       = 'http://10.0.2.20:9200';
const String _sessionIndex = 'neurotrap-sessions';

const Color _navy      = Color(0xFF0A1628);
const Color _navyLight = Color(0xFF0D1F3C);
const Color _card      = Color(0xFF0F2340);
const Color _cyan      = Color(0xFF00E5FF);
const Color _white     = Colors.white;
const Color _botColor  = Color(0xFFFFFFFF);
const Color _skColor   = Color(0xFFFFEA00);
const Color _aptColor  = Color(0xFFFF4400);
const Color _green     = Color(0xFF00E676);

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _selectedIndex = 2;

  int _botCount = 0, _skCount = 0, _aptCount = 0;
  String _lastEvent = 'Loading...';
  bool _connected   = false;

  List<double> _botSeries = List.filled(7, 0);
  List<double> _skSeries  = List.filled(7, 0);
  List<double> _aptSeries = List.filled(7, 0);
  List<String> _dayLabels = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];

  List<Map<String, dynamic>> _deceptionActions = [];

  String _timeFilter = '7d';
  Timer? _timer;
  Timer? _vpnTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fetchData();
    NeuroTrapBackgroundService.startService();
    _timer    = Timer.periodic(const Duration(seconds: 15), (_) => _fetchData());
    _vpnTimer = Timer.periodic(const Duration(seconds: 5),  (_) => _checkVpnAndReload());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _vpnTimer?.cancel();
    super.dispose();
  }

  // ── VPN auto-reconnect detection ──────────────────────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('[NT] App resumed — refreshing data');
      _fetchData();
    }
  }

  Future<void> _checkVpnAndReload() async {
    final wasConnected = _connected;
    final alive = await _checkConnection();
    if (!wasConnected && alive) {
      _fetchData(); // VPN just came back — reload everything
    } else if (mounted && alive != _connected) {
      setState(() => _connected = alive);
    }
  }

  // ── Data fetching ─────────────────────────────────────────────────────────

  Future<void> _fetchData() async {
    debugPrint('[NT] _fetchData called');
    final alive = await _checkConnection();
    debugPrint('[NT] connection alive: $alive');
    if (mounted) setState(() => _connected = alive);
    if (!alive) {
      debugPrint('[NT] Not connected — skipping fetch');
      return;
    }
    debugPrint('[NT] Starting data fetch...');
    try {
      await Future.wait([
        _fetchCounts(),
        _fetchLastEvent(),
        _fetchChartData(),
        _fetchDeceptionActions(),
      ]);
      debugPrint('[NT] All fetches complete. Bots=$_botCount SK=$_skCount APT=$_aptCount');
    } catch (e) {
      debugPrint('[NT] Fetch error: $e');
    }
  }

  Future<bool> _checkConnection() async {
    try {
      debugPrint('[NT] Pinging $_osBase/_cluster/health');
      final r = await http.get(Uri.parse('$_osBase/_cluster/health'))
          .timeout(const Duration(seconds: 5));
      debugPrint('[NT] Health status: \${r.statusCode}');
      return r.statusCode == 200;
    } catch (e) {
      debugPrint('[NT] Connection error: $e');
      return false;
    }
  }

  // Sri Lanka time offset
  static const _slt = Duration(hours: 5, minutes: 30);

  DateTime _toSLT(DateTime utc) => utc.toUtc().add(_slt);

  // Time filter → days back
  int get _filterDays => switch (_timeFilter) {
    '1d'  => 1,
    '7d'  => 7,
    '30d' => 30,
    _     => 3650,
  };

  // Timestamp for PPL — exact format OpenSearch accepts
  String _iso(DateTime dt) {
    final u = dt.toUtc();
    final y  = u.year.toString();
    final mo = u.month.toString().padLeft(2,'0');
    final d  = u.day.toString().padLeft(2,'0');
    final h  = u.hour.toString().padLeft(2,'0');
    final mi = u.minute.toString().padLeft(2,'0');
    final s  = u.second.toString().padLeft(2,'0');
    return y + '-' + mo + '-' + d + ' ' + h + ':' + mi + ':' + s;
  }

  Future<void> _fetchCounts() async {
    final since = _iso(DateTime.now().subtract(Duration(days: _filterDays)));
    final classes = ['automated_bot', 'script_kiddie', 'advanced_adversary'];
    final results = await Future.wait(classes.map((cls) {
      final q = 'source=' + _sessionIndex +
          " | where predicted_class='" + cls +
          "' and timestamp >= timestamp('" + since + "')" +
          ' | stats count() as cnt';
      return _ppl(q);
    }));
    if (mounted) setState(() {
      _botCount = _count(results[0]);
      _skCount  = _count(results[1]);
      _aptCount = _count(results[2]);
    });
  }

  Future<void> _fetchLastEvent() async {
    final r = await _ppl(
      'source=$_sessionIndex | fields predicted_class | sort - timestamp | head 1');
    if (mounted && r != null) {
      final rows = r['datarows'] as List?;
      if (rows != null && rows.isNotEmpty) {
        setState(() => _lastEvent = _fmtCls(rows[0][0]?.toString() ?? ''));
      }
    }
  }

  Future<void> _fetchChartData() async {
    final now = DateTime.now().toUtc();
    final sltNow = _toSLT(now);

    if (_timeFilter == '1d') {
      // Today only — from midnight SLT to now
      final todayStart = DateTime.utc(
        sltNow.year, sltNow.month, sltNow.day)
        .subtract(const Duration(hours: 5, minutes: 30));
      final since = _iso(todayStart);

      final q = 'source=' + _sessionIndex +
          " | where timestamp >= timestamp('" + since + "')" +
          ' | fields timestamp, predicted_class';
      final r = await _ppl(q);
      if (r == null || !mounted) return;

      final rows = r['datarows'] as List? ?? [];

      // 24 hourly buckets
      final b   = List.filled(24, 0.0);
      final s   = List.filled(24, 0.0);
      final a   = List.filled(24, 0.0);
      final lbl = List.generate(24, (i) =>
          i % 4 == 0 ? i.toString().padLeft(2,'0') + ':00' : '');

      for (final row in rows) {
        final ts  = row[0]?.toString();
        final cls = row[1]?.toString() ?? '';
        if (ts == null) continue;
        try {
          final cleaned = ts.trim().replaceFirst(' ','T').split('.')[0] + 'Z';
          final utc     = DateTime.parse(cleaned);
          final slt     = _toSLT(utc);
          final hour    = slt.hour;
          if (hour < 0 || hour >= 24) continue;
          if (cls == 'automated_bot')      b[hour]++;
          if (cls == 'script_kiddie')      s[hour]++;
          if (cls == 'advanced_adversary') a[hour]++;
        } catch (_) {}
      }

      if (mounted) setState(() {
        _botSeries = b; _skSeries = s; _aptSeries = a; _dayLabels = lbl;
      });
      return;
    }

    // 7D / 30D / All — daily buckets
    final days = _timeFilter == '7d' ? 7 : _timeFilter == '30d' ? 30 : 90;
    final since = _iso(now.subtract(Duration(days: days)));
    final q = 'source=' + _sessionIndex +
        " | where timestamp >= timestamp('" + since + "')" +
        ' | fields timestamp, predicted_class';
    final r = await _ppl(q);
    if (r == null || !mounted) return;

    final rows = r['datarows'] as List? ?? [];
    final b   = List.filled(days, 0.0);
    final s   = List.filled(days, 0.0);
    final a   = List.filled(days, 0.0);
    final lbl = List.filled(days, '');

    for (int i = 0; i < days; i++) {
      final d   = now.subtract(Duration(days: days - 1 - i));
      final slt = _toSLT(d);
      lbl[i] = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun']
          [(slt.weekday - 1) % 7];
    }

    for (final row in rows) {
      final ts  = row[0]?.toString();
      final cls = row[1]?.toString() ?? '';
      if (ts == null) continue;
      try {
        final cleaned  = ts.trim().replaceFirst(' ','T').split('.')[0] + 'Z';
        final utc      = DateTime.parse(cleaned);
        final diffDays = now.difference(utc).inDays;
        if (diffDays >= days) continue;
        final idx = days - 1 - diffDays;
        if (idx < 0 || idx >= days) continue;
        if (cls == 'automated_bot')      b[idx]++;
        if (cls == 'script_kiddie')      s[idx]++;
        if (cls == 'advanced_adversary') a[idx]++;
      } catch (_) {}
    }

    if (mounted) setState(() {
      _botSeries = b; _skSeries = s; _aptSeries = a; _dayLabels = lbl;
    });
  }

  Future<void> _fetchDeceptionActions() async {
    final r = await _ppl(
      'source=$_sessionIndex | where predicted_class = \'script_kiddie\' or predicted_class = \'advanced_adversary\' | sort - timestamp | head 10 | fields timestamp, dqn_action, predicted_class, src_ip');
    if (mounted && r != null) {
      final schema = r['schema'] as List?;
      final rows   = r['datarows'] as List?;
      if (schema == null || rows == null) return;
      final keys = schema.map((s) => s['name'].toString()).toList();
      setState(() {
        _deceptionActions = rows.map((row) {
          final m = <String, dynamic>{};
          for (int i = 0; i < keys.length; i++) m[keys[i]] = row[i];
          return m;
        }).toList();
      });
    }
  }

  Future<Map<String, dynamic>?> _ppl(String q) async {
    try {
      final r = await http.post(
        Uri.parse('$_osBase/_plugins/_ppl'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'query': q}),
      ).timeout(const Duration(seconds: 10));
      debugPrint('[NT] PPL status: \${r.statusCode} query: \${q.substring(0, q.length > 60 ? 60 : q.length)}');
      if (r.statusCode == 200) return jsonDecode(r.body);
      debugPrint('[NT] PPL error body: \${r.body.substring(0, r.body.length > 200 ? 200 : r.body.length)}');
    } catch (e) {
      debugPrint('[NT] PPL exception: $e');
    }
    return null;
  }

  int _count(Map<String, dynamic>? r) {
    final rows = r?['datarows'] as List?;
    if (rows == null || rows.isEmpty) return 0;
    return (rows[0][0] as num?)?.toInt() ?? 0;
  }

  String _fmtCls(String c) => switch (c) {
    'automated_bot'      => 'Bot',
    'script_kiddie'      => 'Script Kiddie',
    'advanced_adversary' => 'APT',
    _                    => c,
  };

  Color _clsColor(String? c) {
    if (c == null) return _botColor;
    if (c.contains('adversary')) return _aptColor;
    if (c.contains('kiddie'))    return _skColor;
    return _botColor;
  }

  Color _evtColor(String e) {
    if (e.contains('APT'))    return _aptColor;
    if (e.contains('Script')) return _skColor;
    return _botColor;
  }

  String _fmtAction(String? a) {
    if (a == null) return '--';
    return a.replaceAll('_', ' ').split(' ').map((w) =>
      w.isEmpty ? '' : w[0].toUpperCase() + w.substring(1)).join(' ');
  }

  IconData _actionIcon(String? a) => switch (a) {
    'open_fake_service'  => Icons.computer_rounded,
    'inject_fake_data'   => Icons.data_array_rounded,
    'delay_response'     => Icons.timer_rounded,
    'change_filesystem'  => Icons.folder_rounded,
    'escalate_logging'   => Icons.bar_chart_rounded,
    'close_service'      => Icons.block_rounded,
    _                    => Icons.remove_circle_outline,
  };

  // Convert UTC timestamp → Sri Lanka Time → HH:mm
  String _fmtTime(String? ts) {
    if (ts == null || ts.isEmpty) return '--';
    try {
      final cleaned = ts.trim().replaceFirst(' ', 'T').split('.')[0] + 'Z';
      final utc = DateTime.parse(cleaned);
      final slt = utc.add(const Duration(hours: 5, minutes: 30));
      return slt.day.toString().padLeft(2,'0') + '-' +
             slt.month.toString().padLeft(2,'0') + ' ' +
             slt.hour.toString().padLeft(2,'0') + ':' +
             slt.minute.toString().padLeft(2,'0');
    } catch (e) {
      return ts;
    }
  }

  // ── Shutdown ──────────────────────────────────────────────────────────────

  Future<void> _handleShutdown() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.power_settings_new, color: _aptColor, size: 22),
          SizedBox(width: 10),
          Flexible(child: Text('Shutdown NeuroTrap',
            style: TextStyle(color: _white, fontSize: 16))),
        ]),
        content: const Text(
          'Going on leave? This will:\n\n'
          '• Mute all push notifications\n'
          '• Sign you out of the app\n\n'
          'The AI pipeline continues running on AWS.\n\n'
          'Sign back in anytime to resume monitoring.',
          style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: _cyan)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _aptColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Shutdown',
              style: TextStyle(color: _white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    Navigator.push(context,
      MaterialPageRoute(builder: (_) => const _ShutdownScreen()));
    try { await FirebaseMessaging.instance.deleteToken(); } catch (_) {}
    await NeuroTrapBackgroundService.stopService();
    await Future.delayed(const Duration(seconds: 3));
    await FirebaseAuth.instance.signOut();
    if (mounted) Navigator.pushNamedAndRemoveUntil(context, '/', (r) => false);
  }

  void _confirmSignOut() => showDialog(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: _card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Sign Out', style: TextStyle(color: _white)),
      content: const Text('Sign out of NeuroTrap?',
        style: TextStyle(color: Colors.white70)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: _cyan))),
        TextButton(
          onPressed: () async {
            Navigator.pop(context);
            await FirebaseAuth.instance.signOut();
            if (mounted) {
              Navigator.pushNamedAndRemoveUntil(context, '/', (r) => false);
            }
          },
          child: const Text('Sign Out', style: TextStyle(color: _aptColor)),
        ),
      ],
    ),
  );

  void _onNavTap(int i) {
    setState(() => _selectedIndex = i);
    switch (i) {
      case 0: _confirmSignOut(); break;
      case 1:
        Navigator.push(context,
          MaterialPageRoute(builder: (_) => const AlertsScreen()));
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) setState(() => _selectedIndex = 2);
        });
        break;
      case 2: break;
      case 3:
        Navigator.push(context,
          MaterialPageRoute(builder: (_) => const SettingsScreen()));
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) setState(() => _selectedIndex = 2);
        });
        break;
      case 4: _handleShutdown(); break;
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _navy,
      drawer: _buildDrawer(),
      body: Stack(children: [
        SafeArea(
          child: Column(children: [
            _buildTopBar(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 12),
                    _buildHeader(),
                    const SizedBox(height: 4),
                    _buildConnected(),
                    const SizedBox(height: 10),
                    _buildTimeFilter(),
                    const SizedBox(height: 12),
                    _buildStatCards(),
                    const SizedBox(height: 20),
                    _buildTimeline(),
                    const SizedBox(height: 12),
                    _buildLegend(),
                    const SizedBox(height: 24),
                    _buildDeceptionActions(),
                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ),
          ]),
        ),
        Positioned(left: 0, right: 0, bottom: 0, child: _buildNav()),
      ]),
    );
  }

  Widget _buildDrawer() {
    final items = [
      [Icons.home_rounded,          'Home'],
      [Icons.notifications_rounded, 'Alerts'],
      [Icons.info_outline_rounded,  'About'],
      [Icons.menu_book_rounded,     'User Manual'],
      [Icons.gavel_rounded,         'License & Agreements'],
      [Icons.contacts_rounded,      'Contacts'],
      [Icons.settings_rounded,      'Settings'],
    ];
    return Drawer(
      backgroundColor: _navyLight,
      child: SafeArea(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Image.asset('assets/images/logo.png', height: 36,
              errorBuilder: (_, __, ___) => RichText(
                text: const TextSpan(children: [
                  TextSpan(text: 'NEURO', style: TextStyle(
                    color: _white, fontWeight: FontWeight.w900,
                    fontSize: 20, letterSpacing: 2)),
                  TextSpan(text: 'TRAP', style: TextStyle(
                    color: _cyan, fontWeight: FontWeight.w900,
                    fontSize: 20, letterSpacing: 2)),
                ]))),
          ),
          const Divider(color: Colors.white12),
          ...items.map((item) => ListTile(
            leading: Icon(item[0] as IconData, color: _cyan, size: 20),
            title: Text(item[1] as String,
              style: const TextStyle(color: _white, fontSize: 14)),
            onTap: () {
              Navigator.pop(context);
              final label = item[1] as String;
              if (label == 'Home') return;
              if (label == 'Alerts') Navigator.push(context,
                MaterialPageRoute(builder: (_) => const AlertsScreen()));
              if (label == 'Settings') Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()));
              if (label == 'About') Navigator.push(context,
                MaterialPageRoute(builder: (_) => const AboutScreen()));
              if (label == 'Contacts') Navigator.push(context,
                MaterialPageRoute(builder: (_) => const ContactsScreen()));
              if (label == 'License & Agreements') Navigator.push(context,
                MaterialPageRoute(builder: (_) => const LicenseScreen()));
            },
          )),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: GestureDetector(
              onTap: () async {
                Navigator.pop(context);
                try {
                  await launchUrl(
                    Uri.parse('http://10.0.2.20:3000/d/neurotrap-cowrie/neurotrap-e28094-live-attack-intelligence?orgId=1&from=now-7d&to=now&timezone=Asia%2FColombo&refresh=10s'),
                    mode: LaunchMode.externalApplication,
                  );
                } catch (e) {
                  debugPrint('Grafana: $e');
                }
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: _cyan.withValues(alpha: 0.08),
                  border: Border.all(color: _cyan.withValues(alpha: 0.5)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.dashboard_rounded, color: _cyan, size: 18),
                    SizedBox(width: 8),
                    Text('View Grafana', style: TextStyle(
                      color: _cyan, fontSize: 13,
                      fontWeight: FontWeight.bold)),
                  ]),
              ),
            ),
          ),

        ],
      )),
    );
  }

  Widget _buildTopBar() => Column(children: [
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(children: [
        Builder(builder: (ctx) => GestureDetector(
          onTap: () => Scaffold.of(ctx).openDrawer(),
          child: const Icon(Icons.menu, color: _white, size: 26),
        )),
        const Spacer(),
        const Text('Hi Sehara',
          style: TextStyle(color: _white, fontSize: 13,
            fontWeight: FontWeight.w500)),
      ]),
    ),
    Center(
      child: Image.asset('assets/images/logo.png', height: 56,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => RichText(
          text: const TextSpan(children: [
            TextSpan(text: 'NEURO', style: TextStyle(
              color: _white, fontWeight: FontWeight.w900,
              fontSize: 26, letterSpacing: 2)),
            TextSpan(text: 'TRAP', style: TextStyle(
              color: _cyan, fontWeight: FontWeight.w900,
              fontSize: 26, letterSpacing: 2)),
          ]))),
    ),
    const SizedBox(height: 6),
  ]);

  Widget _buildHeader() => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      const Text('Dashboard',
        style: TextStyle(color: _white, fontSize: 22,
          fontWeight: FontWeight.bold)),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: _cyan.withValues(alpha: 0.6)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(children: [
          const Text('Last Event: ',
            style: TextStyle(color: Colors.white70, fontSize: 11)),
          Text(_lastEvent, style: TextStyle(
            color: _evtColor(_lastEvent), fontSize: 11,
            fontWeight: FontWeight.bold)),
        ]),
      ),
    ],
  );

  Widget _buildConnected() => Row(children: [
    Container(width: 8, height: 8,
      decoration: BoxDecoration(
        color: _connected ? _green : Colors.red,
        shape: BoxShape.circle)),
    const SizedBox(width: 6),
    Text(_connected ? 'Connected' : 'Disconnected — VPN required',
      style: TextStyle(
        color: _connected ? _green : Colors.red, fontSize: 12)),
  ]);

  Widget _buildTimeFilter() {
    final filters = [('1d','1D'), ('7d','7D'), ('30d','30D'), ('all','All')];
    return Row(children: [
      const Text('Period:',
        style: TextStyle(color: Colors.white38, fontSize: 11)),
      const SizedBox(width: 8),
      ...filters.map((f) {
        final sel = _timeFilter == f.$1;
        return GestureDetector(
          onTap: () {
            setState(() => _timeFilter = f.$1);
            _fetchCounts();
            _fetchChartData();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.only(right: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: sel ? _cyan.withValues(alpha: 0.15) : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: sel ? _cyan : Colors.white24, width: 1)),
            child: Text(f.$2, style: TextStyle(
              color: sel ? _cyan : Colors.white38, fontSize: 11,
              fontWeight: sel ? FontWeight.bold : FontWeight.normal)),
          ),
        );
      }),
    ]);
  }

  Widget _buildStatCards() => Row(children: [
    Expanded(child: _statCard('BOTS', _botCount, _botColor)),
    const SizedBox(width: 8),
    Expanded(child: _statCard('SCRIPT KIDDIES', _skCount, _skColor)),
    const SizedBox(width: 8),
    Expanded(child: _statCard('APTs', _aptCount, _aptColor)),
  ]);

  Widget _statCard(String label, int value, Color vc) => Container(
    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
    decoration: BoxDecoration(
      color: _card, borderRadius: BorderRadius.circular(10),
      border: Border.all(color: vc.withValues(alpha: 0.25), width: 1)),
    child: Column(children: [
      Text(label, style: const TextStyle(color: Colors.white60, fontSize: 9,
        fontWeight: FontWeight.w600, letterSpacing: 0.5),
        textAlign: TextAlign.center),
      const SizedBox(height: 6),
      Text(value.toString(), style: TextStyle(color: vc, fontSize: 34,
        fontWeight: FontWeight.bold, height: 1)),
    ]),
  );

  Widget _buildTimeline() {
    final label = _timeFilter == '1d' ? 'Today (Hourly)'
                : _timeFilter == '7d' ? 'Last 7 Days'
                : _timeFilter == '30d' ? 'Last 30 Days' : 'All Time';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Attack Timeline', style: TextStyle(
            color: _white, fontSize: 18, fontWeight: FontWeight.bold)),
          Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11)),
        ]),
        const SizedBox(height: 12),
        Container(
          height: 220,
          decoration: BoxDecoration(
            color: const Color(0xFF0D1B2E),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          padding: const EdgeInsets.fromLTRB(0, 8, 8, 0),
          child: _botSeries.isEmpty
            ? const Center(child: CircularProgressIndicator(color: _cyan))
            : _GrafanaChart(
                botSeries:  _botSeries,
                skSeries:   _skSeries,
                aptSeries:  _aptSeries,
                labels:     _dayLabels,
                timeFilter: _timeFilter,
              ),
        ),
      ],
    );
  }



  Widget _buildLegend() => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      _legendDot('Bots', _botColor), const SizedBox(width: 20),
      _legendDot('Script Kiddies', _skColor), const SizedBox(width: 20),
      _legendDot('APTs', _aptColor),
    ]);

  Widget _legendDot(String label, Color color) => Row(children: [
    Container(width: 10, height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
    const SizedBox(width: 5),
    Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11)),
  ]);

  Widget _buildDeceptionActions() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(children: [
        const Icon(Icons.psychology_alt_rounded, color: _cyan, size: 18),
        const SizedBox(width: 8),
        const Text('Deception Actions', style: TextStyle(
          color: _white, fontSize: 18, fontWeight: FontWeight.bold)),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: _cyan.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _cyan.withValues(alpha: 0.3))),
          child: const Text('DQN Agent',
            style: TextStyle(color: _cyan, fontSize: 9)),
        ),
      ]),
      const SizedBox(height: 10),
      if (_deceptionActions.isEmpty)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _card, borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white12)),
          child: const Column(children: [
            Icon(Icons.cloud_off_rounded, color: Colors.white24, size: 32),
            SizedBox(height: 8),
            Text('No data — connect VPN to load',
              style: TextStyle(color: Colors.white38, fontSize: 12)),
          ]),
        )
      else
        ...(_deceptionActions.map((a) => _deceptionCard(a))),
    ],
  );

  Widget _deceptionCard(Map<String, dynamic> a) {
    final action   = a['dqn_action']?.toString() ?? 'do_nothing';
    final cls      = a['predicted_class']?.toString() ?? '';
    final ip       = a['src_ip']?.toString() ?? '--';
    final time     = _fmtTime(a['timestamp']?.toString());
    final clsColor = _clsColor(cls);
    final actionColor = switch (action) {
      'open_fake_service'  => const Color(0xFF00BCD4),
      'inject_fake_data'   => const Color(0xFF9C27B0),
      'delay_response'     => const Color(0xFFFF9800),
      'change_filesystem'  => const Color(0xFF4CAF50),
      'escalate_logging'   => _aptColor,
      'close_service'      => Colors.red,
      _                    => Colors.white38,
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _card, borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(color: actionColor, width: 3))),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: actionColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8)),
          child: Icon(_actionIcon(action), color: actionColor, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_fmtAction(action), style: TextStyle(
              color: actionColor, fontSize: 13, fontWeight: FontWeight.bold)),
            const SizedBox(height: 3),
            Row(children: [
              const Icon(Icons.location_on, color: Colors.white38, size: 11),
              const SizedBox(width: 3),
              Text(ip, style: const TextStyle(
                color: Colors.white54, fontSize: 11)),
            ]),
          ],
        )),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: clsColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6)),
            child: Text(_fmtCls(cls), style: TextStyle(
              color: clsColor, fontSize: 9, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 4),
          Text(time, style: const TextStyle(
            color: Colors.white38, fontSize: 10)),
        ]),
      ]),
    );
  }

  Widget _buildNav() {
    final items = [
      {'icon': Icons.logout,                'label': 'Sign Out', 'i': 0},
      {'icon': Icons.notifications_rounded, 'label': 'Alerts',   'i': 1},
      {'icon': Icons.home_rounded,          'label': 'Home',     'i': 2},
      {'icon': Icons.settings_rounded,      'label': 'Settings', 'i': 3},
      {'icon': Icons.power_settings_new,    'label': 'Shutdown', 'i': 4},
    ];
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.3),
            border: Border(top: BorderSide(
              color: Colors.white.withValues(alpha: 0.1), width: 0.5))),
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: SafeArea(top: false, child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: items.map((item) {
              final idx     = item['i'] as int;
              final isHome  = idx == 2;
              final selected = idx == _selectedIndex;
              return GestureDetector(
                onTap: () => _onNavTap(idx),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: isHome
                      ? const EdgeInsets.all(10)
                      : const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: selected
                        ? _cyan.withValues(alpha: 0.15)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(isHome ? 50 : 10),
                    border: selected
                        ? Border.all(
                            color: _cyan.withValues(alpha: 0.4), width: 1)
                        : null),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(item['icon'] as IconData,
                      color: selected ? _cyan : Colors.white38, size: 22),
                    const SizedBox(height: 3),
                    Text(item['label'] as String, style: TextStyle(
                      color: selected ? _cyan : Colors.white38,
                      fontSize: 9)),
                  ]),
                ),
              );
            }).toList(),
          )),
        ),
      ),
    );
  }
}

// ─── GRAFANA-STYLE CHART ─────────────────────────────────────────────────────

class _GrafanaChart extends StatefulWidget {
  final List<double> botSeries, skSeries, aptSeries;
  final List<String> labels;
  final String timeFilter;

  const _GrafanaChart({
    required this.botSeries, required this.skSeries, required this.aptSeries,
    required this.labels, required this.timeFilter,
  });

  @override
  State<_GrafanaChart> createState() => _GrafanaChartState();
}

class _GrafanaChartState extends State<_GrafanaChart> {
  int? _sel;

  double get _maxVal {
    final all = [...widget.botSeries, ...widget.skSeries, ...widget.aptSeries];
    return all.fold(0.0, (a, b) => a > b ? a : b).clamp(1.0, double.infinity);
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.labels.length;
    if (count < 2) return const Center(
      child: Text('No data', style: TextStyle(color: Colors.white38, fontSize: 12)));

    return Column(children: [
      // Tooltip row
      SizedBox(
        height: 28,
        child: _sel != null ? _buildTooltip(_sel!) : const SizedBox(),
      ),
      // Chart
      Expanded(
        child: LayoutBuilder(builder: (ctx, box) {
          return GestureDetector(
            onPanUpdate: (d) {
              final idx = ((d.localPosition.dx - 40) / (box.maxWidth - 40) * (count - 1))
                  .round().clamp(0, count - 1);
              setState(() => _sel = idx);
            },
            onPanEnd: (_) => setState(() => _sel = null),
            onTapDown: (d) {
              final idx = ((d.localPosition.dx - 40) / (box.maxWidth - 40) * (count - 1))
                  .round().clamp(0, count - 1);
              setState(() => _sel = idx);
            },
            child: CustomPaint(
              size: Size(box.maxWidth, box.maxHeight),
              painter: _ChartPainter(
                bot: widget.botSeries,
                sk:  widget.skSeries,
                apt: widget.aptSeries,
                lbl: widget.labels,
                maxVal: _maxVal,
                sel: _sel,
              ),
            ),
          );
        }),
      ),
      const SizedBox(height: 4),
      // Legend row
      Padding(
        padding: const EdgeInsets.only(left: 40, bottom: 4),
        child: Row(children: [
          _leg('Bots',          const Color(0xFF5794F2)),
          const SizedBox(width: 16),
          _leg('Script Kiddies', const Color(0xFFFFEA00)),
          const SizedBox(width: 16),
          _leg('APTs',          const Color(0xFFFF4400)),
        ]),
      ),
    ]);
  }

  Widget _buildTooltip(int i) {
    final lbl = widget.labels[i];
    final bot = widget.botSeries[i].toInt();
    final sk  = widget.skSeries[i].toInt();
    final apt = widget.aptSeries[i].toInt();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 40),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF1C2E4A),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(children: [
        Text(lbl, style: const TextStyle(color: Colors.white60, fontSize: 9)),
        const SizedBox(width: 8),
        _tip('Bots', bot, const Color(0xFF5794F2)),
        const SizedBox(width: 8),
        _tip('SK', sk,  const Color(0xFFFFEA00)),
        const SizedBox(width: 8),
        _tip('APT', apt, const Color(0xFFFF4400)),
      ]),
    );
  }

  Widget _tip(String l, int v, Color c) => Row(mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 6, height: 6,
        decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
      const SizedBox(width: 3),
      Text('$l: $v', style: TextStyle(color: c, fontSize: 9, fontWeight: FontWeight.bold)),
    ]);

  Widget _leg(String l, Color c) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 12, height: 2, color: c),
    const SizedBox(width: 4),
    Text(l, style: const TextStyle(color: Colors.white38, fontSize: 9)),
  ]);
}

class _ChartPainter extends CustomPainter {
  final List<double> bot, sk, apt;
  final List<String> lbl;
  final double maxVal;
  final int? sel;

  const _ChartPainter({
    required this.bot, required this.sk, required this.apt,
    required this.lbl, required this.maxVal, required this.sel});

  static const double _L = 40, _B = 20, _T = 4, _R = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final n  = lbl.length;
    final cw = size.width - _L - _R;
    final ch = size.height - _B - _T;

    _grid(canvas, size, cw, ch);
    _series(canvas, bot, const Color(0xFF5794F2), cw, ch, n);
    _series(canvas, sk,  const Color(0xFFFFEA00), cw, ch, n);
    _series(canvas, apt, const Color(0xFFFF4400), cw, ch, n);
    _xLabels(canvas, size, cw, ch, n);

    if (sel != null) {
      final x = _L + (sel! / (n - 1)) * cw;
      canvas.drawLine(Offset(x, _T), Offset(x, _T + ch),
        Paint()..color = Colors.white24..strokeWidth = 1);
      _dot(canvas, bot, const Color(0xFF5794F2), sel!, cw, ch, n);
      _dot(canvas, sk,  const Color(0xFFFFEA00), sel!, cw, ch, n);
      _dot(canvas, apt, const Color(0xFFFF4400), sel!, cw, ch, n);
    }
  }

  void _grid(Canvas canvas, Size size, double cw, double ch) {
    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (int i = 0; i <= 4; i++) {
      final y = _T + ch - (i / 4) * ch;
      canvas.drawLine(Offset(_L, y), Offset(_L + cw, y),
        Paint()..color = Colors.white.withOpacity(0.07)..strokeWidth = 1);
      final v = ((i / 4) * maxVal).round().toString();
      tp.text = TextSpan(text: v,
        style: const TextStyle(color: Colors.white38, fontSize: 8));
      tp.layout();
      tp.paint(canvas, Offset(_L - tp.width - 4, y - tp.height / 2));
    }
    canvas.drawLine(Offset(_L, _T + ch), Offset(_L + cw, _T + ch),
      Paint()..color = Colors.white24..strokeWidth = 1);
  }

  void _series(Canvas canvas, List<double> data, Color color,
      double cw, double ch, int n) {
    if (data.isEmpty || n < 2) return;
    final lp = Paint()..color = color..strokeWidth = 1.5
      ..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
    final fp = Paint()..color = color.withOpacity(0.1)..style = PaintingStyle.fill;
    final path = Path();
    final fill = Path();
    for (int i = 0; i < n; i++) {
      final x = _L + (i / (n - 1)) * cw;
      final y = _T + ch - (data[i] / maxVal).clamp(0, 1) * ch;
      if (i == 0) {
        path.moveTo(x, y);
        fill.moveTo(x, _T + ch);
        fill.lineTo(x, y);
      } else {
        final px = _L + ((i - 1) / (n - 1)) * cw;
        final py = _T + ch - (data[i-1] / maxVal).clamp(0, 1) * ch;
        final cx = (px + x) / 2;
        path.cubicTo(cx, py, cx, y, x, y);
        fill.cubicTo(cx, py, cx, y, x, y);
      }
    }
    fill.lineTo(_L + cw, _T + ch);
    fill.close();
    canvas.drawPath(fill, fp);
    canvas.drawPath(path, lp);
  }

  void _dot(Canvas canvas, List<double> data, Color color,
      int i, double cw, double ch, int n) {
    if (i >= data.length || n < 2) return;
    final x = _L + (i / (n - 1)) * cw;
    final y = _T + ch - (data[i] / maxVal).clamp(0, 1) * ch;
    canvas.drawCircle(Offset(x, y), 4, Paint()..color = color);
    canvas.drawCircle(Offset(x, y), 2.5, Paint()..color = const Color(0xFF0D1B2E));
    canvas.drawCircle(Offset(x, y), 1.5, Paint()..color = color);
  }

  void _xLabels(Canvas canvas, Size size, double cw, double ch, int n) {
    final tp = TextPainter(textDirection: TextDirection.ltr);
    final step = (n / 5).ceil().clamp(1, n);
    for (int i = 0; i < n; i += step) {
      if (i >= lbl.length || lbl[i].isEmpty) continue;
      final x = _L + (i / (n - 1)) * cw;
      tp.text = TextSpan(text: lbl[i],
        style: TextStyle(
          color: sel == i ? Colors.white70 : Colors.white38,
          fontSize: 8));
      tp.layout();
      tp.paint(canvas, Offset(x - tp.width / 2, size.height - _B + 3));
    }
  }

  @override
  bool shouldRepaint(_ChartPainter o) => o.sel != sel || o.maxVal != maxVal;
}

// ─── SHUTDOWN SCREEN// ─── SHUTDOWN SCREEN ──────────────────────────────────────────────────────────

class _ShutdownScreen extends StatefulWidget {
  const _ShutdownScreen();
  @override
  State<_ShutdownScreen> createState() => _ShutdownScreenState();
}

class _ShutdownScreenState extends State<_ShutdownScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _spin;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(
      vsync: this, duration: const Duration(seconds: 2))..repeat();
  }

  @override
  void dispose() { _spin.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          RotationTransition(turns: _spin,
            child: const Icon(Icons.settings_rounded,
              color: Colors.white38, size: 48)),
          const SizedBox(height: 20),
          const Text('Shutting Down',
            style: TextStyle(color: Colors.white60,
              fontSize: 16, letterSpacing: 2)),
          const SizedBox(height: 60),
          Image.asset('assets/images/logo.png', height: 44,
            errorBuilder: (_, __, ___) => RichText(
              text: const TextSpan(children: [
                TextSpan(text: 'NEURO', style: TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w900,
                  fontSize: 20, letterSpacing: 3)),
                TextSpan(text: 'TRAP', style: TextStyle(
                  color: Color(0xFF00E5FF), fontWeight: FontWeight.w900,
                  fontSize: 20, letterSpacing: 3)),
              ]))),
          const SizedBox(height: 8),
          const Text('SECURITY THAT EVOLVES',
            style: TextStyle(color: Colors.white38,
              fontSize: 8, letterSpacing: 2)),
        ],
      )),
    );
  }
}
