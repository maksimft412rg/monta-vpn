import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_v2ray_client/flutter_v2ray.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';

void main() => runApp(const MyApp());

// ============================================================
//  НАСТРОЙКИ ПРИЛОЖЕНИЯ (хранятся в SharedPreferences)
// ============================================================
class ThemeDef {
  final String name;
  final Color bg;
  final Color accent2;
  const ThemeDef(this.name, this.bg, this.accent2);
}

const Map<String, ThemeDef> kThemes = {
  'neon': ThemeDef('Неон', Color(0xFF0A0812), Color(0xFF7B2CFF)),
  'autumn': ThemeDef('Осень', Color(0xFF120B07), Color(0xFFC2391B)),
  'ice': ThemeDef('Лёд', Color(0xFF070C16), Color(0xFF3D5BFF)),
  'hw': ThemeDef('Хэллоуин', Color(0xFF0D0814), Color(0xFF8B2CFF)),
  'forest': ThemeDef('Лес', Color(0xFF07120C), Color(0xFF1B9C5A)),
};

const List<String> kAccentColors = [
  '#ff2bd6',
  '#ff8a1f',
  '#3dd9ff',
  '#7bff6b',
  '#ffd43b',
  '#ff4d4d',
];

const Map<String, String> kFonts = {
  'manrope': 'Manrope',
  'oswald': 'Oswald',
  'lato': 'Lato',
  'poppins': 'Poppins',
};

const Map<String, String> kEffects = {
  'off': 'Выкл',
  'snow': 'Снег',
  'leaves': 'Листопад',
};

Color hexColor(String hex, {Color fallback = const Color(0xFFFF2BD6)}) {
  try {
    return Color(int.parse(hex.replaceFirst('#', '0xff')));
  } catch (_) {
    return fallback;
  }
}

class AppSettings extends ChangeNotifier {
  String theme = 'neon';
  String font = 'manrope';
  String color = '#ff2bd6';
  String effect = 'off';
  String subscriptionUrl = '';
  bool bypassRussia = true;
  bool killSwitch = false;
  bool autoStart = false;
  bool fragmentation = false;
  bool autoSelect = true;
  Set<String> favorites = {};

  ThemeDef get themeDef => kThemes[theme] ?? kThemes['neon']!;
  Color get accent => hexColor(color);
  Color get bg => themeDef.bg;
  Color get accent2 => themeDef.accent2;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    theme = p.getString('theme') ?? 'neon';
    font = p.getString('font') ?? 'manrope';
    color = p.getString('accentColor') ?? '#ff2bd6';
    effect = p.getString('effectType') ?? 'off';
    subscriptionUrl = p.getString('subscriptionUrl') ?? '';
    bypassRussia = p.getBool('bypassRussia') ?? true;
    killSwitch = p.getBool('killSwitch') ?? false;
    autoStart = p.getBool('autoStart') ?? false;
    fragmentation = p.getBool('fragmentation') ?? false;
    autoSelect = p.getBool('autoSelect') ?? true;
    favorites = (p.getStringList('favorites') ?? []).toSet();
    notifyListeners();
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('theme', theme);
    await p.setString('font', font);
    await p.setString('accentColor', color);
    await p.setString('effectType', effect);
    await p.setString('subscriptionUrl', subscriptionUrl);
    await p.setBool('bypassRussia', bypassRussia);
    await p.setBool('killSwitch', killSwitch);
    await p.setBool('autoStart', autoStart);
    await p.setBool('fragmentation', fragmentation);
    await p.setBool('autoSelect', autoSelect);
    await p.setStringList('favorites', favorites.toList());
  }

  void update(void Function() change) {
    change();
    notifyListeners();
    save();
  }

  void toggleFavorite(String remark) {
    update(() {
      if (!favorites.remove(remark)) favorites.add(remark);
    });
  }
}

// ============================================================
//  VPN-КОНТРОЛЛЕР (вся логика подключения в одном месте)
// ============================================================
class VpnController extends ChangeNotifier {
  final AppSettings settings;
  VpnController(this.settings);

  late final V2ray v2ray;
  StreamSubscription? _connSub;
  Timer? _timer;
  DateTime? _connectedAt;

  String state = 'DISCONNECTED';
  bool loading = false;
  bool pinging = false;
  bool hasInternet = true;

  List<V2RayURL> servers = [];
  Map<int, int> pings = {};
  int current = 0;

  String trafficUsed = '—';
  String trafficTotal = '—';
  double trafficProgress = 0;
  String expireDate = '—';
  int? daysLeft;
  DateTime? lastUpdated;

  Duration connectedFor = Duration.zero;
  int downSpeed = 0;
  int upSpeed = 0;
  int totalDown = 0;
  int totalUp = 0;

  String? error;

  bool get isConnected => state == 'CONNECTED';
  bool get isConnecting => state == 'CONNECTING';

  Future<void> init() async {
    v2ray = V2ray(onStatusChanged: _onStatus);
    try {
      await v2ray.initialize(
        notificationIconResourceType: 'mipmap',
        notificationIconResourceName: 'ic_launcher',
      );
    } catch (_) {}
    await _checkInternet();
    try {
      _connSub = Connectivity().onConnectivityChanged.listen((dynamic r) {
        final list = r is List ? r : [r];
        final ok = !list.contains(ConnectivityResult.none);
        if (ok != hasInternet) {
          hasInternet = ok;
          notifyListeners();
        }
      });
    } catch (_) {}
    if (settings.subscriptionUrl.isNotEmpty) {
      await loadCachedSubscription();
      fetchSubscription(silent: true);
    }
  }

  @override
  void dispose() {
    _connSub?.cancel();
    _timer?.cancel();
    super.dispose();
  }

  int _num(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    return int.tryParse('$v') ?? 0;
  }

  void _onStatus(V2RayStatus status) {
    final dyn = status as dynamic;
    final newState = status.state;
    try {
      downSpeed = _num(dyn.downloadSpeed);
      upSpeed = _num(dyn.uploadSpeed);
      totalDown = _num(dyn.download);
      totalUp = _num(dyn.upload);
    } catch (_) {}
    if (newState == 'CONNECTED' && _connectedAt == null) {
      _connectedAt = DateTime.now();
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_connectedAt != null) {
          connectedFor = DateTime.now().difference(_connectedAt!);
          notifyListeners();
        }
      });
    }
    if (newState != 'CONNECTED') {
      _connectedAt = null;
      _timer?.cancel();
      connectedFor = Duration.zero;
      downSpeed = 0;
      upSpeed = 0;
    }
    state = newState;
    notifyListeners();
  }

  Future<void> _checkInternet() async {
    try {
      final dynamic r = await Connectivity().checkConnectivity();
      final list = r is List ? r : [r];
      hasInternet = !list.contains(ConnectivityResult.none);
    } catch (_) {
      hasInternet = true;
    }
    notifyListeners();
  }

  // ---------- Подписка ----------
  Future<void> loadCachedSubscription() async {
    final p = await SharedPreferences.getInstance();
    final cached = p.getString('cachedSubscription');
    if (cached != null && cached.isNotEmpty) _parseServers(cached);
  }

  void _parseServers(String body) {
    String decoded = body.trim();
    try {
      decoded = utf8.decode(base64.decode(base64.normalize(decoded)));
    } catch (_) {}
    final list = <V2RayURL>[];
    for (var line in decoded.split('\n')) {
      line = line.trim();
      if (line.startsWith('vless://') ||
          line.startsWith('vmess://') ||
          line.startsWith('trojan://') ||
          line.startsWith('hy2://') ||
          line.startsWith('hysteria2://') ||
          line.startsWith('ss://')) {
        try {
          list.add(V2ray.parseFromURL(line));
        } catch (_) {}
      }
    }
    servers = list;
    if (current >= servers.length) current = 0;
    notifyListeners();
  }

  Future<void> fetchSubscription({bool silent = false}) async {
    final url = settings.subscriptionUrl.trim();
    if (url.isEmpty) {
      error = 'Подписка не добавлена. Откройте «Настройки».';
      notifyListeners();
      return;
    }
    await _checkInternet();
    if (!hasInternet) {
      if (!silent) error = 'Нет интернета. Проверьте подключение.';
      notifyListeners();
      return;
    }
    loading = true;
    error = null;
    notifyListeners();
    try {
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }
      _parseUserInfo(response.headers['subscription-userinfo']);
      _parseServers(response.body);
      if (servers.isEmpty) {
        error = 'В подписке нет серверов';
      } else {
        final p = await SharedPreferences.getInstance();
        await p.setString('cachedSubscription', response.body);
        lastUpdated = DateTime.now();
        measurePings();
      }
    } catch (e) {
      if (servers.isEmpty) {
        error = 'Ошибка загрузки подписки. Проверьте ссылку и интернет.';
      }
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  void _parseUserInfo(String? info) {
    if (info == null) return;
    int upload = 0, download = 0, total = 0, expire = 0;
    for (final part in info.split(';')) {
      final kv = part.trim().split('=');
      if (kv.length != 2) continue;
      final v = int.tryParse(kv[1]) ?? 0;
      switch (kv[0]) {
        case 'upload':
          upload = v;
          break;
        case 'download':
          download = v;
          break;
        case 'total':
          total = v;
          break;
        case 'expire':
          expire = v;
          break;
      }
    }
    const gb = 1024 * 1024 * 1024;
    final used = upload + download;
    trafficUsed = '${(used / gb).toStringAsFixed(2)} ГБ';
    trafficTotal = total > 0 ? '${(total / gb).toStringAsFixed(1)} ГБ' : '∞';
    trafficProgress = total > 0 ? (used / total).clamp(0.0, 1.0) : 0;
    if (expire > 0) {
      final d = DateTime.fromMillisecondsSinceEpoch(expire * 1000);
      expireDate = d.toString().split(' ')[0];
      daysLeft = d.difference(DateTime.now()).inDays;
    }
  }

  // ---------- Пинг ----------
  Future<void> measurePings() async {
    if (servers.isEmpty || pinging) return;
    pinging = true;
    pings = {};
    notifyListeners();
    final tasks = <Future<void>>[];
    for (int i = 0; i < servers.length; i++) {
      tasks.add(_pingOne(i));
    }
    await Future.wait(tasks);
    pinging = false;
    if (settings.autoSelect && !isConnected && pings.isNotEmpty) {
      int best = current;
      int minPing = 99998;
      pings.forEach((id, ping) {
        if (ping < minPing) {
          minPing = ping;
          best = id;
        }
      });
      if (minPing < 99998) current = best;
    }
    notifyListeners();
  }

  Future<void> _pingOne(int i) async {
    final server = servers[i];
    final dyn = server as dynamic;
    String address = '';
    int port = 443;
    try {
      address = (dyn.address ?? '').toString();
    } catch (_) {}
    try {
      port = _num(dyn.port);
      if (port == 0) port = 443;
    } catch (_) {}
    if (address.isEmpty) {
      pings[i] = 9999;
      return;
    }
    try {
      final start = DateTime.now();
      final socket = await Socket.connect(address, port,
          timeout: const Duration(seconds: 3));
      socket.destroy();
      pings[i] = DateTime.now().difference(start).inMilliseconds;
    } catch (_) {
      pings[i] = 9999;
    }
    notifyListeners();
  }

  void selectServer(int i) {
    if (isConnected) return; // нельзя менять сервер на лету
    current = i;
    notifyListeners();
  }

  // ---------- Подключение ----------
  Future<void> toggle() async {
    if (isConnected || isConnecting) {
      v2ray.stopV2Ray();
      state = 'DISCONNECTED';
      notifyListeners();
      return;
    }
    if (servers.isEmpty) {
      error = 'Подписка не добавлена или пуста. Зайдите в «Настройки».';
      notifyListeners();
      return;
    }
    error = null;
    loading = true;
    state = 'CONNECTING';
    notifyListeners();
    try {
      final parser = servers[current];
      final ok = await v2ray.requestPermission();
      if (ok) {
        await v2ray.startV2Ray(
          remark: parser.remark,
          config: parser.getFullConfiguration(),
          proxyOnly: false,
        );
      } else {
        state = 'DISCONNECTED';
        error = 'Разрешение на VPN не получено';
      }
    } catch (e) {
      state = 'DISCONNECTED';
      error = 'Ошибка подключения: $e';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  void clearError() {
    error = null;
    notifyListeners();
  }
}

// ============================================================
//  ХЕЛПЕРЫ
// ============================================================
String formatSpeed(int bytesPerSec) {
  if (bytesPerSec < 1024) return '$bytesPerSec Б/с';
  if (bytesPerSec < 1024 * 1024) {
    return '${(bytesPerSec / 1024).toStringAsFixed(1)} КБ/с';
  }
  return '${(bytesPerSec / (1024 * 1024)).toStringAsFixed(1)} МБ/с';
}

String formatBytes(int b) {
  if (b < 1024) return '$b Б';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} КБ';
  if (b < 1024 * 1024 * 1024) return '${(b / (1024 * 1024)).toStringAsFixed(1)} МБ';
  return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(2)} ГБ';
}

String formatDuration(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
}

Color pingColor(int ping) {
  if (ping >= 9999) return Colors.redAccent;
  if (ping < 100) return Colors.greenAccent;
  if (ping < 200) return Colors.orangeAccent;
  return Colors.redAccent;
}

Widget glass({
  required Widget child,
  EdgeInsets padding = const EdgeInsets.all(16),
  double radius = 24,
  Color? borderColor,
}) {
  return Container(
    padding: padding,
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: borderColor ?? Colors.white.withValues(alpha: 0.08)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.2),
          blurRadius: 24,
          offset: const Offset(0, 10),
        ),
      ],
    ),
    child: child,
  );
}

// ============================================================
//  ПРИЛОЖЕНИЕ
// ============================================================
class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final AppSettings settings = AppSettings();
  late final VpnController vpn;
  bool ready = false;

  @override
  void initState() {
    super.initState();
    vpn = VpnController(settings);
    _boot();
  }

  Future<void> _boot() async {
    await settings.load();
    if (mounted) setState(() => ready = true);
    await vpn.init();
  }

  @override
  void dispose() {
    vpn.dispose();
    settings.dispose();
    super.dispose();
  }

  TextTheme _textTheme() {
    switch (settings.font) {
      case 'oswald':
        return GoogleFonts.oswaldTextTheme(ThemeData.dark().textTheme);
      case 'lato':
        return GoogleFonts.latoTextTheme(ThemeData.dark().textTheme);
      case 'poppins':
        return GoogleFonts.poppinsTextTheme(ThemeData.dark().textTheme);
      default:
        return GoogleFonts.manropeTextTheme(ThemeData.dark().textTheme);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        return MaterialApp(
          title: 'Monta VPN',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            brightness: Brightness.dark,
            textTheme: _textTheme(),
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: settings.accent,
              brightness: Brightness.dark,
            ),
          ),
          home: ready
              ? MainScreen(settings: settings, vpn: vpn)
              : Scaffold(
                  backgroundColor: settings.bg,
                  body: const Center(child: CircularProgressIndicator()),
                ),
        );
      },
    );
  }
}

class MainScreen extends StatefulWidget {
  final AppSettings settings;
  final VpnController vpn;
  const MainScreen({super.key, required this.settings, required this.vpn});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with SingleTickerProviderStateMixin {
  int _index = 0;
  late final AnimationController _bg;

  @override
  void initState() {
    super.initState();
    _bg = AnimationController(vsync: this, duration: const Duration(seconds: 8))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _bg.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    return Scaffold(
      extendBody: true,
      backgroundColor: s.bg,
      body: Stack(
        children: [
          AnimatedBuilder(
            animation: _bg,
            builder: (context, _) => Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(-0.8 + _bg.value * 0.3, -0.8 + _bg.value * 0.2),
                  radius: 1.8,
                  colors: [
                    s.bg,
                    s.accent2.withValues(alpha: 0.25 + _bg.value * 0.2),
                  ],
                ),
              ),
            ),
          ),
          if (s.effect != 'off') WeatherEffect(key: ValueKey(s.effect), type: s.effect),
          IndexedStack(
            index: _index,
            children: [
              HomeTab(
                settings: s,
                vpn: widget.vpn,
                onOpenServers: () => setState(() => _index = 1),
              ),
              ServersTab(settings: s, vpn: widget.vpn),
              SettingsTab(settings: s, vpn: widget.vpn),
            ],
          ),
        ],
      ),
      bottomNavigationBar: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        decoration: BoxDecoration(
          color: const Color(0xFF1B1E21).withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: BottomNavigationBar(
            currentIndex: _index,
            onTap: (i) => setState(() => _index = i),
            backgroundColor: Colors.transparent,
            elevation: 0,
            type: BottomNavigationBarType.fixed,
            selectedItemColor: s.accent,
            unselectedItemColor: Colors.grey,
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.shield_rounded), label: 'Главная'),
              BottomNavigationBarItem(icon: Icon(Icons.dns_rounded), label: 'Серверы'),
              BottomNavigationBarItem(icon: Icon(Icons.tune_rounded), label: 'Настройки'),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
//  ГЛАВНАЯ
// ============================================================
class HomeTab extends StatefulWidget {
  final AppSettings settings;
  final VpnController vpn;
  final VoidCallback onOpenServers;
  const HomeTab({
    super.key,
    required this.settings,
    required this.vpn,
    required this.onOpenServers,
  });

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  void _showQr() {
    final url = widget.settings.subscriptionUrl;
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сначала добавьте подписку в «Настройках»')),
      );
      return;
    }
    showQrDialog(context, url, widget.settings.accent);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    return ListenableBuilder(
      listenable: widget.vpn,
      builder: (context, _) {
        final v = widget.vpn;
        final accent = s.accent;
        final connected = v.isConnected;
        final connecting = v.isConnecting;
        final mainColor = connected ? Colors.greenAccent.shade400 : accent;

        String title = 'VPN отключен';
        String subtitle = 'Нажмите для подключения';
        if (connecting) {
          title = 'Подключение…';
          subtitle = 'Устанавливаем защищённый туннель';
        } else if (connected) {
          title = 'VPN включен';
          subtitle = 'Ваш трафик защищён';
        }

        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
            child: Column(
              children: [
                // шапка
                Row(
                  children: [
                    ClipOval(
                      child: Image.asset(
                        'assets/logo.png',
                        width: 42,
                        height: 42,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.shield_rounded, color: accent, size: 24),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Monta VPN',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 1,
                      ),
                    ),
                    const Spacer(),
                    if (!v.hasInternet)
                      const Padding(
                        padding: EdgeInsets.only(right: 4),
                        child: Icon(Icons.wifi_off_rounded, color: Colors.redAccent),
                      ),
                    IconButton(
                      icon: Icon(Icons.qr_code_rounded, color: accent),
                      onPressed: _showQr,
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                if (v.error != null) _ErrorBanner(text: v.error!, onClose: v.clearError),

                // кнопка
                glass(
                  radius: 36,
                  padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
                  child: Column(
                    children: [
                      SizedBox(
                        width: 230,
                        height: 230,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            AnimatedBuilder(
                              animation: _pulse,
                              builder: (context, _) {
                                final t = _pulse.value;
                                return Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    Container(
                                      width: 190 + 40 * t,
                                      height: 190 + 40 * t,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: mainColor.withValues(alpha: 0.35 - 0.25 * t),
                                          width: 2,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      width: 170 + 20 * t,
                                      height: 170 + 20 * t,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: mainColor.withValues(alpha: 0.18),
                                          width: 1,
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                            GestureDetector(
                              onTap: v.loading && !connecting ? null : v.toggle,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                width: 150,
                                height: 150,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: connected
                                        ? [Colors.green, Colors.greenAccent]
                                        : [accent, s.accent2],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: mainColor.withValues(alpha: 0.55),
                                      blurRadius: 40,
                                      spreadRadius: 8,
                                    ),
                                  ],
                                ),
                                child: connecting
                                    ? const Center(
                                        child: CircularProgressIndicator(color: Colors.white),
                                      )
                                    : const Icon(
                                        Icons.power_settings_new_rounded,
                                        size: 64,
                                        color: Colors.white,
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(subtitle, style: TextStyle(fontSize: 14, color: Colors.grey[400])),
                      if (connected) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.greenAccent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            formatDuration(v.connectedFor),
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: Colors.greenAccent,
                              letterSpacing: 2,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // скорость
                if (connected) ...[
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          icon: Icons.south_rounded,
                          color: Colors.greenAccent,
                          title: 'Загрузка',
                          value: formatSpeed(v.downSpeed),
                          sub: formatBytes(v.totalDown),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StatCard(
                          icon: Icons.north_rounded,
                          color: accent,
                          title: 'Отдача',
                          value: formatSpeed(v.upSpeed),
                          sub: formatBytes(v.totalUp),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],

                // текущий сервер
                GestureDetector(
                  onTap: widget.onOpenServers,
                  child: glass(
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(Icons.public_rounded, color: accent),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Сервер', style: TextStyle(fontSize: 12, color: Colors.grey[400])),
                              const SizedBox(height: 2),
                              Text(
                                v.servers.isEmpty
                                    ? 'Не выбран'
                                    : v.servers[v.current].remark,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (v.pings[v.current] != null)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Text(
                              v.pings[v.current]! >= 9999 ? 'н/д' : '${v.pings[v.current]} мс',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: pingColor(v.pings[v.current]!),
                              ),
                            ),
                          ),
                        const Icon(Icons.chevron_right_rounded, color: Colors.grey),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // подписка
                glass(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.data_usage_rounded, color: accent, size: 20),
                          const SizedBox(width: 8),
                          const Text(
                            'Подписка',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const Spacer(),
                          v.loading && !connecting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : IconButton(
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(Icons.refresh_rounded, color: Colors.grey, size: 20),
                                  onPressed: () => v.fetchSubscription(),
                                ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: v.trafficProgress,
                          minHeight: 8,
                          backgroundColor: Colors.white.withValues(alpha: 0.08),
                          valueColor: AlwaysStoppedAnimation(
                            v.trafficProgress > 0.9 ? Colors.redAccent : accent,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${v.trafficUsed} / ${v.trafficTotal}',
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                          Text(
                            v.daysLeft == null
                                ? 'до ${v.expireDate}'
                                : v.daysLeft! < 0
                                    ? 'Истекла'
                                    : 'Осталось ${v.daysLeft} дн.',
                            style: TextStyle(
                              color: (v.daysLeft != null && v.daysLeft! <= 3)
                                  ? Colors.orangeAccent
                                  : Colors.grey[400],
                            ),
                          ),
                        ],
                      ),
                      if (v.lastUpdated != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Обновлено: ${v.lastUpdated!.hour.toString().padLeft(2, '0')}:${v.lastUpdated!.minute.toString().padLeft(2, '0')}',
                          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String value;
  final String sub;
  const _StatCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.value,
    required this.sub,
  });

  @override
  Widget build(BuildContext context) {
    return glass(
      radius: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 6),
              Text(title, style: TextStyle(fontSize: 12, color: Colors.grey[400])),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 2),
          Text('всего $sub', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String text;
  final VoidCallback onClose;
  const _ErrorBanner({required this.text, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(
        color: Colors.redAccent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Colors.redAccent),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 13))),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close_rounded, size: 18, color: Colors.grey),
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

void showQrDialog(BuildContext context, String data, Color accent) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF1B1E21),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: const Text('QR-код подписки', style: TextStyle(color: Colors.white)),
      content: Container(
        width: 250,
        height: 250,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: QrImageView(
          data: data,
          version: QrVersions.auto,
          size: 230,
          backgroundColor: Colors.white,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: data));
            Navigator.pop(ctx);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Ссылка скопирована')),
            );
          },
          child: Text('Копировать', style: TextStyle(color: accent)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text('Закрыть', style: TextStyle(color: accent)),
        ),
      ],
    ),
  );
}

// ============================================================
//  СЕРВЕРЫ
// ============================================================
class ServersTab extends StatefulWidget {
  final AppSettings settings;
  final VpnController vpn;
  const ServersTab({super.key, required this.settings, required this.vpn});

  @override
  State<ServersTab> createState() => _ServersTabState();
}

class _ServersTabState extends State<ServersTab> {
  String query = '';
  bool sortByPing = true;

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    return ListenableBuilder(
      listenable: Listenable.merge([widget.vpn, s]),
      builder: (context, _) {
        final v = widget.vpn;
        final accent = s.accent;

        var indices = List<int>.generate(v.servers.length, (i) => i);
        if (query.isNotEmpty) {
          indices = indices
              .where((i) => v.servers[i].remark.toLowerCase().contains(query.toLowerCase()))
              .toList();
        }
        indices.sort((a, b) {
          final fa = s.favorites.contains(v.servers[a].remark) ? 0 : 1;
          final fb = s.favorites.contains(v.servers[b].remark) ? 0 : 1;
          if (fa != fb) return fa - fb;
          if (sortByPing) {
            return (v.pings[a] ?? 99999).compareTo(v.pings[b] ?? 99999);
          }
          return a.compareTo(b);
        });

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Серверы',
                        style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Сортировка',
                      icon: Icon(
                        sortByPing ? Icons.speed_rounded : Icons.sort_by_alpha_rounded,
                        color: accent,
                      ),
                      onPressed: () => setState(() => sortByPing = !sortByPing),
                    ),
                    v.pinging
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : IconButton(
                            tooltip: 'Проверить пинг',
                            icon: Icon(Icons.network_ping_rounded, color: accent),
                            onPressed: v.measurePings,
                          ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  onChanged: (t) => setState(() => query = t),
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Поиск сервера',
                    hintStyle: const TextStyle(color: Colors.grey),
                    prefixIcon: const Icon(Icons.search_rounded, color: Colors.grey),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.05),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                glass(
                  radius: 16,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Авто-выбор лучшего сервера',
                          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                      Switch(
                        value: s.autoSelect,
                        activeColor: accent,
                        onChanged: (val) => s.update(() => s.autoSelect = val),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: v.servers.isEmpty
                      ? Center(
                          child: Text(
                            v.hasInternet ? 'Подписка не добавлена' : 'У вас нет интернета',
                            style: TextStyle(color: v.hasInternet ? Colors.grey : Colors.redAccent),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 120),
                          itemCount: indices.length,
                          itemBuilder: (context, k) {
                            final i = indices[k];
                            final server = v.servers[i];
                            final ping = v.pings[i];
                            final selected = v.current == i;
                            final fav = s.favorites.contains(server.remark);
                            return GestureDetector(
                              onTap: () {
                                if (v.isConnected) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Отключите VPN, чтобы сменить сервер'),
                                    ),
                                  );
                                  return;
                                }
                                v.selectServer(i);
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: selected
                                      ? accent.withValues(alpha: 0.15)
                                      : Colors.white.withValues(alpha: 0.03),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: selected ? accent : Colors.transparent,
                                    width: 1.5,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: selected
                                            ? accent.withValues(alpha: 0.2)
                                            : Colors.white.withValues(alpha: 0.05),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Icon(
                                        Icons.dns_rounded,
                                        color: selected ? accent : Colors.grey,
                                        size: 18,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        server.remark,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                                        ),
                                      ),
                                    ),
                                    if (ping != null)
                                      Padding(
                                        padding: const EdgeInsets.only(right: 4),
                                        child: Text(
                                          ping >= 9999 ? 'н/д' : '$ping мс',
                                          style: TextStyle(
                                            color: pingColor(ping),
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    GestureDetector(
                                      onTap: () => s.toggleFavorite(server.remark),
                                      child: Padding(
                                        padding: const EdgeInsets.all(6),
                                        child: Icon(
                                          fav ? Icons.star_rounded : Icons.star_border_rounded,
                                          color: fav ? Colors.amber : Colors.grey,
                                          size: 22,
                                        ),
                                      ),
                                    ),
                                    if (selected) Icon(Icons.check_circle_rounded, color: accent, size: 20),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ============================================================
//  ЭФФЕКТЫ (СНЕГ / ЛИСТОПАД)
// ============================================================
class WeatherEffect extends StatefulWidget {
  final String type;
  const WeatherEffect({super.key, required this.type});

  @override
  State<WeatherEffect> createState() => _WeatherEffectState();
}

class _WeatherEffectState extends State<WeatherEffect> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final List<Particle> _particles = [];
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    final count = widget.type == 'leaves' ? 22 : 45;
    for (int i = 0; i < count; i++) {
      _particles.add(Particle.random(_random, widget.type));
    }
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 1))
      ..addListener(() {
        for (final p in _particles) {
          p.update(_random);
        }
      })
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: ParticlePainter(_particles, widget.type, _controller),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class Particle {
  double x, y, speed, size, angle, rotationSpeed;
  final bool leaf;
  Color color;

  Particle({
    required this.x,
    required this.y,
    required this.speed,
    required this.size,
    required this.leaf,
    required this.angle,
    required this.rotationSpeed,
    required this.color,
  });

  // x, y и speed — в долях экрана (0..1)
  factory Particle.random(Random r, String type) {
    final leaf = type == 'leaves';
    const leafColors = [
      Color(0xFFFF8A1F),
      Color(0xFFD9461A),
      Color(0xFFF2B134),
      Color(0xFFA8341C),
    ];
    return Particle(
      x: r.nextDouble(),
      y: r.nextDouble(),
      speed: 0.0012 + r.nextDouble() * 0.003,
      size: leaf ? 7 + r.nextDouble() * 9 : 2 + r.nextDouble() * 3.5,
      leaf: leaf,
      angle: r.nextDouble() * 6,
      rotationSpeed: (r.nextDouble() - 0.5) * 0.12,
      color: leaf ? leafColors[r.nextInt(4)] : Colors.white.withValues(alpha: 0.65),
    );
  }

  void update(Random r) {
    y += speed;
    if (leaf) {
      x += sin(angle) * 0.002;
      angle += rotationSpeed;
    } else {
      x += sin(y * 12 + angle) * 0.0006;
    }
    if (y > 1.05) {
      y = -0.05;
      x = r.nextDouble();
    }
  }
}

class ParticlePainter extends CustomPainter {
  final List<Particle> particles;
  final String type;
  ParticlePainter(this.particles, this.type, Listenable repaint) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    for (final p in particles) {
      paint.color = p.color;
      final dx = p.x * size.width;
      final dy = p.y * size.height;
      if (!p.leaf) {
        canvas.drawCircle(Offset(dx, dy), p.size, paint);
      } else {
        canvas.save();
        canvas.translate(dx, dy);
        canvas.rotate(p.angle);
        canvas.drawOval(
          Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size / 2),
          paint,
        );
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(covariant ParticlePainter old) => old.type != type;
}

// ============================================================
//  НАСТРОЙКИ
// ============================================================
class SettingsTab extends StatefulWidget {
  final AppSettings settings;
  final VpnController vpn;
  const SettingsTab({super.key, required this.settings, required this.vpn});

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  final TextEditingController _link = TextEditingController();

  @override
  void initState() {
    super.initState();
    _link.text = widget.settings.subscriptionUrl;
  }

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      _toast('Буфер обмена пуст');
      return;
    }
    setState(() => _link.text = text);
  }

  Future<void> _saveSubscription() async {
    final s = widget.settings;
    final url = _link.text.trim();
    if (url.isNotEmpty && !url.startsWith('http')) {
      _toast('Ссылка должна начинаться с https://');
      return;
    }
    s.update(() => s.subscriptionUrl = url);
    _toast('Сохранено!');
    FocusScope.of(context).unfocus();
    if (url.isNotEmpty) widget.vpn.fetchSubscription();
  }

  Widget _title(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10, top: 4),
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.5,
            color: widget.settings.accent,
          ),
        ),
      );

  Widget _switch(String title, String sub, bool value, ValueChanged<bool> onChanged) {
    return glass(
      radius: 18,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 2),
                Text(sub, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
              ],
            ),
          ),
          Switch(value: value, activeColor: widget.settings.accent, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    final accent = widget.settings.accent;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? accent : Colors.transparent, width: 1.5),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: Colors.white,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Настройки',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white),
                ),
                const SizedBox(height: 24),

                _title('Подписка'),
                TextField(
                  controller: _link,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  maxLines: 3,
                  minLines: 2,
                  decoration: InputDecoration(
                    hintText: 'https://...',
                    hintStyle: const TextStyle(color: Colors.grey),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.05),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _paste,
                        icon: const Icon(Icons.content_paste_rounded, size: 18),
                        label: const Text('Вставить'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _saveSubscription,
                        icon: const Icon(Icons.save_rounded, size: 18),
                        label: const Text('Сохранить'),
                        style: FilledButton.styleFrom(
                          backgroundColor: s.accent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                _title('Туннель'),
                _switch('Обход РФ', 'Госуслуги и банки напрямую', s.bypassRussia,
                    (v) => s.update(() => s.bypassRussia = v)),
                const SizedBox(height: 10),
                _switch('Kill Switch', 'Блокировать интернет при обрыве VPN', s.killSwitch,
                    (v) => s.update(() => s.killSwitch = v)),
                const SizedBox(height: 10),
                _switch('Автозапуск', 'Включать VPN при старте телефона', s.autoStart,
                    (v) => s.update(() => s.autoStart = v)),
                const SizedBox(height: 10),
                _switch('Фрагментация', 'Обход DPI (если провайдер режет)', s.fragmentation,
                    (v) => s.update(() => s.fragmentation = v)),
                const SizedBox(height: 24),

                _title('Тема'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: kThemes.entries
                      .map((e) => _chip(e.value.name, s.theme == e.key, () => s.update(() => s.theme = e.key)))
                      .toList(),
                ),
                const SizedBox(height: 24),

                _title('Акцентный цвет'),
                Wrap(
                  spacing: 14,
                  runSpacing: 10,
                  children: kAccentColors.map((c) {
                    final selected = s.color == c;
                    return GestureDetector(
                      onTap: () => s.update(() => s.color = c),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: hexColor(c),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: selected ? Colors.white : Colors.transparent,
                            width: 3,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: hexColor(c).withValues(alpha: selected ? 0.6 : 0.2),
                              blurRadius: 14,
                            ),
                          ],
                        ),
                        child: selected
                            ? const Icon(Icons.check_rounded, color: Colors.white, size: 20)
                            : null,
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),

                _title('Шрифт'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: kFonts.entries
                      .map((e) => _chip(e.value, s.font == e.key, () => s.update(() => s.font = e.key)))
                      .toList(),
                ),
                const SizedBox(height: 24),

                _title('Эффекты'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: kEffects.entries
                      .map((e) => _chip(e.value, s.effect == e.key, () => s.update(() => s.effect = e.key)))
                      .toList(),
                ),
                const SizedBox(height: 24),

                _title('Дополнительно'),
                glass(
                  radius: 18,
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      ListTile(
                        leading: Icon(Icons.qr_code_rounded, color: s.accent),
                        title: const Text('QR-код подписки', style: TextStyle(color: Colors.white)),
                        onTap: () {
                          if (s.subscriptionUrl.isEmpty) {
                            _toast('Сначала добавьте подписку');
                          } else {
                            showQrDialog(context, s.subscriptionUrl, s.accent);
                          }
                        },
                      ),
                      Divider(height: 1, color: Colors.white.withValues(alpha: 0.06)),
                      ListTile(
                        leading: Icon(Icons.copy_rounded, color: s.accent),
                        title: const Text('Скопировать ссылку', style: TextStyle(color: Colors.white)),
                        onTap: () {
                          if (s.subscriptionUrl.isEmpty) {
                            _toast('Сначала добавьте подписку');
                          } else {
                            Clipboard.setData(ClipboardData(text: s.subscriptionUrl));
                            _toast('Ссылка скопирована');
                          }
                        },
                      ),
                      Divider(height: 1, color: Colors.white.withValues(alpha: 0.06)),
                      ListTile(
                        leading: const Icon(Icons.restart_alt_rounded, color: Colors.redAccent),
                        title: const Text('Сбросить оформление', style: TextStyle(color: Colors.white)),
                        onTap: () {
                          s.update(() {
                            s.theme = 'neon';
                            s.font = 'manrope';
                            s.color = '#ff2bd6';
                            s.effect = 'off';
                          });
                          _toast('Оформление сброшено');
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Center(
                  child: Text(
                    'Monta VPN',
                    style: TextStyle(color: Colors.grey[700], fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
