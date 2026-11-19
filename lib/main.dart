import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_v2ray_client/flutter_v2ray.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';

void main() => runApp(const MyApp());

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String currentTheme = 'neon';
  String currentFont = 'manrope';
  String currentColor = '#ff2bd6';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      currentTheme = prefs.getString('theme') ?? 'neon';
      currentFont = prefs.getString('font') ?? 'manrope';
      currentColor = prefs.getString('accentColor') ?? '#ff2bd6';
    });
  }

  void changeTheme(String newTheme) {
    setState(() => currentTheme = newTheme);
    SharedPreferences.getInstance().then((p) => p.setString('theme', newTheme));
  }

  void changeFont(String newFont) {
    setState(() => currentFont = newFont);
    SharedPreferences.getInstance().then((p) => p.setString('font', newFont));
  }

  void changeColor(String newColor) {
    setState(() => currentColor = newColor);
    SharedPreferences.getInstance().then((p) => p.setString('accentColor', newColor));
  }

  TextTheme _getTextTheme() {
    switch (currentFont) {
      case 'oswald':
        return GoogleFonts.oswaldTextTheme();
      case 'lato':
        return GoogleFonts.latoTextTheme();
      case 'poppins':
        return GoogleFonts.poppinsTextTheme();
      default:
        return GoogleFonts.manropeTextTheme();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Monta VPN',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        textTheme: _getTextTheme(),
        useMaterial3: true,
      ),
      home: MainScreen(
        currentTheme: currentTheme,
        onThemeChanged: changeTheme,
        currentFont: currentFont,
        onFontChanged: changeFont,
        currentColor: currentColor,
        onColorChanged: changeColor,
      ),
    );
  }
}

class MainScreen extends StatefulWidget {
  final String currentTheme;
  final Function(String) onThemeChanged;
  final String currentFont;
  final Function(String) onFontChanged;
  final String currentColor;
  final Function(String) onColorChanged;

  const MainScreen({
    super.key,
    required this.currentTheme,
    required this.onThemeChanged,
    required this.currentFont,
    required this.onFontChanged,
    required this.currentColor,
    required this.onColorChanged,
  });

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: _currentIndex == 0
          ? HomeTab(
              key: ValueKey(widget.currentTheme), // Ключ для обновления при смене темы
              theme: widget.currentTheme,
              accentColor: widget.currentColor,
            )
          : SettingsTab(
              currentTheme: widget.currentTheme,
              onThemeChanged: widget.onThemeChanged,
              currentFont: widget.currentFont,
              onFontChanged: widget.onFontChanged,
              currentColor: widget.currentColor,
              onColorChanged: widget.onColorChanged,
            ),
      bottomNavigationBar: Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1B1E21).withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 20,
              offset: const Offset(0, 10),
            )
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: (index) => setState(() => _currentIndex = index),
            backgroundColor: Colors.transparent,
            elevation: 0,
            selectedItemColor: Color(int.parse(widget.currentColor.replaceFirst('#', '0xff'))),
            unselectedItemColor: Colors.grey,
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.home_rounded), label: 'Главная'),
              BottomNavigationBarItem(icon: Icon(Icons.settings_rounded), label: 'Настройки'),
            ],
          ),
        ),
      ),
    );
  }
}

// --- ГЛАВНАЯ ---
class HomeTab extends StatefulWidget {
  final String theme;
  final String accentColor;
  const HomeTab({super.key, required this.theme, required this.accentColor});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> with TickerProviderStateMixin {
  late final V2ray v2ray;
  late AnimationController _pulseController;
  late AnimationController _bgController;
  bool isLoading = false;
  String connectionState = 'DISCONNECTED';

  String subscriptionUrl = "";
  List<V2RayURL> parsedServers = [];
  int currentServer = 0;

  bool autoSelect = true;
  Map<int, int> serverPings = {};

  String trafficUsed = "—";
  String trafficTotal = "—";
  String expireDate = "—";

  String effectType = 'off';
  bool hasInternet = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _checkInternet();

    _pulseController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _bgController = AnimationController(
        vsync: this, duration: const Duration(seconds: 8))
      ..repeat(reverse: true);

    v2ray = V2ray(
      onStatusChanged: (status) {
        if (mounted) setState(() => connectionState = status.state);
      },
    );
    v2ray.initialize(
        notificationIconResourceType: "mipmap",
        notificationIconResourceName: "ic_launcher");
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _bgController.dispose();
    super.dispose();
  }

  Future<void> _checkInternet() async {
    final results = await Connectivity().checkConnectivity();
    if (mounted) {
      setState(() {
        hasInternet = results.isNotEmpty && !results.contains(ConnectivityResult.none);
      });
    }
  }

  Color getAccentColor() {
    try {
      return Color(int.parse(widget.accentColor.replaceFirst('#', '0xff')));
    } catch (e) {
      return const Color(0xFFFF2BD6);
    }
  }

  Map<String, Color> getThemeColors() {
    switch (widget.theme) {
      case 'autumn':
        return {
          'bg': const Color(0xFF120B07),
          'accent': getAccentColor(),
          'accent2': const Color(0xFFC2391B)
        };
      case 'ice':
        return {
          'bg': const Color(0xFF070C16),
          'accent': getAccentColor(),
          'accent2': const Color(0xFF3D5BFF)
        };
      case 'hw':
        return {
          'bg': const Color(0xFF0D0814),
          'accent': getAccentColor(),
          'accent2': const Color(0xFF8B2CFF)
        };
      default:
        return {
          'bg': const Color(0xFF0A0812),
          'accent': getAccentColor(),
          'accent2': const Color(0xFF7B2CFF)
        };
    }
  }

  Future<void> _loadSettings() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      subscriptionUrl = prefs.getString('subscriptionUrl') ?? "";
      effectType = prefs.getString('effectType') ?? 'off';
      autoSelect = prefs.getBool('autoSelect') ?? true;
    });
    if (subscriptionUrl.isNotEmpty) _fetchSubscription();
  }

  Future<void> _fetchSubscription() async {
    if (subscriptionUrl.isEmpty) return;
    if (!hasInternet) {
      _showErrorDialog('У вас нет интернета. Проверьте подключение.');
      return;
    }
    if (mounted) setState(() => isLoading = true);
    try {
      final response = await http.get(Uri.parse(subscriptionUrl));
      final userInfo = response.headers['subscription-userinfo'];
      if (userInfo != null) {
        final parts = userInfo.split(';');
        int upload = 0, download = 0, total = 0, expire = 0;
        for (var part in parts) {
          final kv = part.trim().split('=');
          if (kv.length == 2) {
            switch (kv[0]) {
              case 'upload':
                upload = int.tryParse(kv[1]) ?? 0;
                break;
              case 'download':
                download = int.tryParse(kv[1]) ?? 0;
                break;
              case 'total':
                total = int.tryParse(kv[1]) ?? 0;
                break;
              case 'expire':
                expire = int.tryParse(kv[1]) ?? 0;
                break;
            }
          }
        }
        trafficUsed =
            "${((upload + download) / (1024 * 1024 * 1024)).toStringAsFixed(2)} ГБ";
        trafficTotal = "${(total / (1024 * 1024 * 1024)).toStringAsFixed(1)} ГБ";
        if (expire > 0) {
          expireDate = DateTime.fromMillisecondsSinceEpoch(expire * 1000)
              .toString()
              .split(' ')[0];
        }
      }

      final content = response.body.trim();
      String decodedContent = content;
      try {
        decodedContent = utf8.decode(base64.decode(content));
      } catch (_) {}

      parsedServers.clear();
      for (var line in decodedContent.split('\n')) {
        line = line.trim();
        if (line.startsWith('vless://') ||
            line.startsWith('vmess://') ||
            line.startsWith('trojan://') ||
            line.startsWith('hy2://') ||
            line.startsWith('hysteria2://') ||
            line.startsWith('ss://')) {
          try {
            parsedServers.add(V2ray.parseFromURL(line));
          } catch (_) {}
        }
      }
      if (parsedServers.isEmpty) {
        _showErrorDialog('В подписке нет серверов');
      } else {
        _measurePings();
      }
    } catch (e) {
      _showErrorDialog('Ошибка загрузки подписки. Проверьте интернет.');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _measurePings() async {
    for (int i = 0; i < parsedServers.length; i++) {
      try {
        final delay = await v2ray.getServerDelay(
            config: parsedServers[i].getFullConfiguration());
        if (mounted) setState(() => serverPings[i] = delay);
      } catch (_) {
        if (mounted) setState(() => serverPings[i] = 9999);
      }
    }
    if (autoSelect && serverPings.isNotEmpty) {
      int best = 0;
      int minPing = 99999;
      serverPings.forEach((id, ping) {
        if (ping < minPing) {
          minPing = ping;
          best = id;
        }
      });
      if (mounted) setState(() => currentServer = best);
    }
  }

  void toggleVPN() async {
    if (connectionState == 'CONNECTED') {
      v2ray.stopV2Ray();
      if (mounted) setState(() => connectionState = 'DISCONNECTED');
      return;
    }
    if (parsedServers.isEmpty) {
      _showErrorDialog('Подписка не добавлена или пуста. Зайдите в Настройки.');
      return;
    }
    setState(() => isLoading = true);
    try {
      final parser = parsedServers[currentServer];
      final hasPermission = await v2ray.requestPermission();
      if (hasPermission) {
        await v2ray.startV2Ray(
          remark: parser.remark,
          config: parser.getFullConfiguration(),
          proxyOnly: false,
        );
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) setState(() => connectionState = 'CONNECTED');
      } else {
        _showErrorDialog('Разрешение на VPN не получено');
      }
    } catch (e) {
      _showErrorDialog('Ошибка подключения: $e');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _showErrorDialog(String message) {
    if (mounted) {
      showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
                title: const Text('Ошибка'),
                content: Text(message),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('ОК'))
                ],
              ));
    }
  }

  void _showQRCode() {
    if (subscriptionUrl.isEmpty) {
      _showErrorDialog('Сначала добавьте подписку в Настройках');
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1B1E21),
        title: const Text('QR-код подписки',
            style: TextStyle(color: Colors.white)),
        content: Container(
          width: 250,
          height: 250,
          color: Colors.white,
          child: QrImageView(
            data: subscriptionUrl,
            version: QrVersions.auto,
            size: 230,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Закрыть', style: TextStyle(color: getAccentColor())),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isConnected = connectionState == 'CONNECTED';
    final colors = getThemeColors();

    return Stack(
      children: [
        AnimatedBuilder(
          animation: _bgController,
          builder: (context, child) {
            return Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(-0.8 + (_bgController.value * 0.2),
                      -0.8 + (_bgController.value * 0.1)),
                  radius: 1.8,
                  colors: [
                    colors['bg']!,
                    colors['accent2']!
                        .withValues(alpha: 0.3 + (_bgController.value * 0.2)),
                  ],
                ),
              ),
            );
          },
        ),
        if (effectType != 'off' && mounted)
          WeatherEffect(key: ValueKey(effectType), type: effectType),
        SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 100),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Row(
                    children: [
                      ClipOval(
                        child: Image.asset(
                          'assets/logo.png',
                          width: 40,
                          height: 40,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: colors['accent']!.withValues(alpha: 0.2),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.shield_rounded,
                                  color: colors['accent'], size: 24),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text('Monta VPN',
                          style: GoogleFonts.manrope(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: 1)),
                      const Spacer(),
                      if (!hasInternet)
                        const Icon(Icons.wifi_off_rounded,
                            color: Colors.red, size: 24),
                      IconButton(
                        icon: Icon(Icons.qr_code_rounded,
                            color: colors['accent'], size: 24),
                        onPressed: _showQRCode,
                      ),
                    ],
                  ),
                ),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(32),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.08)),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 30,
                          offset: const Offset(0, 15))
                    ],
                  ),
                  child: Column(
                    children: [
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          ScaleTransition(
                            scale: Tween(begin: 0.95, end: 1.15)
                                .animate(_pulseController),
                            child: Container(
                              width: 200,
                              height: 200,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: (isConnected
                                            ? Colors.green
                                            : colors['accent']!)
                                        .withValues(alpha: 0.15),
                                    width: 1),
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: isLoading ? null : toggleVPN,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 250),
                              width: 150,
                              height: 150,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: isConnected
                                      ? [Colors.green, Colors.greenAccent]
                                      : [
                                          colors['accent']!,
                                          colors['accent2']!
                                        ],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: (isConnected
                                            ? Colors.green
                                            : colors['accent']!)
                                        .withValues(alpha: 0.6),
                                    blurRadius: 40,
                                    spreadRadius: 10,
                                  ),
                                ],
                              ),
                              child: isLoading
                                  ? const Center(
                                      child: CircularProgressIndicator(
                                          color: Colors.white))
                                  : const Icon(
                                      Icons.power_settings_new_rounded,
                                      size: 60,
                                      color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text(
                        isConnected ? 'VPN Включен' : 'VPN Отключен',
                        style: GoogleFonts.manrope(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: Colors.white),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        isConnected
                            ? 'Ваш трафик защищен'
                            : 'Нажмите для подключения',
                        style:
                            TextStyle(fontSize: 14, color: Colors.grey[400]),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Expanded(
                          child: _buildInfoCard(Icons.data_usage_rounded,
                              'Трафик', '$trafficUsed / $trafficTotal')),
                      const SizedBox(width: 12),
                      Expanded(
                          child: _buildInfoCard(Icons.calendar_today_rounded,
                              'Срок', expireDate)),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(16),
                      border:
                          Border.all(color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Авто-выбор сервера',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.white)),
                        Switch(
                          value: autoSelect,
                          activeColor: colors['accent'],
                          onChanged: (v) {
                            setState(() => autoSelect = v);
                            SharedPreferences.getInstance().then((prefs) {
                              prefs.setBool('autoSelect', v);
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(24),
                      border:
                          Border.all(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Серверы',
                                style: GoogleFonts.manrope(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white)),
                            IconButton(
                              icon: const Icon(Icons.refresh_rounded,
                                  color: Colors.grey, size: 20),
                              onPressed: () {
                                _checkInternet();
                                _fetchSubscription();
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (parsedServers.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(20),
                            child: Center(
                              child: Text(
                                hasInternet
                                    ? 'Подписка не добавлена'
                                    : 'У вас нет интернета',
                                style: TextStyle(
                                    color: hasInternet
                                        ? Colors.grey
                                        : Colors.red),
                              ),
                            ),
                          )
                        else
                          ...parsedServers.asMap().entries.map((entry) {
                            final ping = serverPings[entry.key];
                            return GestureDetector(
                              onTap: () =>
                                  setState(() => currentServer = entry.key),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: currentServer == entry.key
                                      ? colors['accent']!
                                          .withValues(alpha: 0.15)
                                      : Colors.white.withValues(alpha: 0.03),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                      color: currentServer == entry.key
                                          ? colors['accent']!
                                          : Colors.transparent,
                                      width: 1.5),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: currentServer == entry.key
                                            ? colors['accent']!
                                                .withValues(alpha: 0.2)
                                            : Colors.white
                                                .withValues(alpha: 0.05),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Icon(Icons.dns_rounded,
                                          color: currentServer == entry.key
                                              ? colors['accent']
                                              : Colors.grey,
                                          size: 18),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        entry.value.remark,
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: currentServer == entry.key
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (ping != null)
                                      Text(
                                        ping == 9999 ? 'н/д' : '$ping мс',
                                        style: TextStyle(
                                          color: ping == 9999
                                              ? Colors.red
                                              : ping < 100
                                                  ? Colors.green
                                                  : ping < 200
                                                      ? Colors.orange
                                                      : Colors.red,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    if (currentServer == entry.key)
                                      Icon(Icons.check_circle_rounded,
                                          color: colors['accent'], size: 20),
                                  ],
                                ),
                              ),
                            );
                          }),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoCard(IconData icon, String title, String value) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, 5))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: getAccentColor().withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: getAccentColor(), size: 20),
          ),
          const SizedBox(height: 10),
          Text(title, style: TextStyle(fontSize: 12, color: Colors.grey[400])),
          const SizedBox(height: 2),
          Text(value,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.white)),
        ],
      ),
    );
  }
}

// --- АНИМАЦИЯ ЭФФЕКТОВ (СНЕГ/ЛИСТОПАД) ---
class WeatherEffect extends StatefulWidget {
  final String type;
  const WeatherEffect({super.key, required this.type});

  @override
  State<WeatherEffect> createState() => _WeatherEffectState();
}

class _WeatherEffectState extends State<WeatherEffect>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<Particle> _particles = [];
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(seconds: 1))
      ..repeat();
    final count = widget.type == 'leaves' ? 20 : 40;
    for (int i = 0; i < count; i++) {
      _particles.add(Particle.random(_random, widget.type));
    }
    _controller.addListener(() {
      if (mounted) {
        setState(() {
          for (var p in _particles) {
            p.update();
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.stop();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
        painter: ParticlePainter(_particles, widget.type), size: Size.infinite);
  }
}

class Particle {
  double x, y, speed, size, angle, rotationSpeed;
  String type;
  Color color;

  Particle(
      {required this.x,
      required this.y,
      required this.speed,
      required this.size,
      required this.type,
      required this.angle,
      required this.rotationSpeed,
      required this.color});

  factory Particle.random(Random random, String type) {
    final isLeaf = type == 'leaves';
    return Particle(
      x: random.nextDouble() * 400,
      y: random.nextDouble() * 800,
      speed: 1 + random.nextDouble() * 3,
      size: isLeaf ? 6 + random.nextDouble() * 8 : 2 + random.nextDouble() * 4,
      type: type,
      angle: random.nextDouble() * 6,
      rotationSpeed: (random.nextDouble() - 0.5) * 0.1,
      color: isLeaf
          ? [
              const Color(0xFFFF8A1F),
              const Color(0xFFD9461A),
              const Color(0xFFF2B134),
              const Color(0xFFA8341C)
            ][random.nextInt(4)]
          : Colors.white.withValues(alpha: 0.6),
    );
  }

  void update() {
    y += speed;
    if (type == 'leaves') {
      x += sin(angle) * 1.5;
      angle += rotationSpeed;
    }
    if (y > 800) {
      y = -20;
      x = Random().nextDouble() * 400;
    }
  }
}

class ParticlePainter extends CustomPainter {
  final List<Particle> particles;
  final String type;
  ParticlePainter(this.particles, this.type);

  @override
  void paint(Canvas canvas, Size size) {
    for (var p in particles) {
      if (type == 'snow') {
        final paint = Paint()
          ..color = p.color
          ..style = PaintingStyle.fill;
        canvas.drawCircle(Offset(p.x, p.y), p.size, paint);
      } else {
        canvas.save();
        canvas.translate(p.x, p.y);
        canvas.rotate(p.angle);
        final paint = Paint()
          ..color = p.color
          ..style = PaintingStyle.fill;
        canvas.drawOval(
            Rect.fromCenter(
                center: Offset.zero, width: p.size, height: p.size / 2),
            paint);
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// --- НАСТРОЙКИ (ПОЛНОСТЬЮ ДОПИСАННЫЙ БЛОК) ---
class SettingsTab extends StatefulWidget {
  final String currentTheme;
  final Function(String) onThemeChanged;
  final String currentFont;
  final Function(String) onFontChanged;
  final String currentColor;
  final Function(String) onColorChanged;

  const SettingsTab({
    super.key,
    required this.currentTheme,
    required this.onThemeChanged,
    required this.currentFont,
    required this.onFontChanged,
    required this.currentColor,
    required this.onColorChanged,
  });

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  final TextEditingController _linkController = TextEditingController();
  bool bypassRussia = true;
  bool killSwitch = false;
  bool autoStart = false;
  bool fragmentation = false;
  String effectType = 'off';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _linkController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _linkController.text = prefs.getString('subscriptionUrl') ?? "";
      bypassRussia = prefs.getBool('bypassRussia') ?? true;
      killSwitch = prefs.getBool('killSwitch') ?? false;
      autoStart = prefs.getBool('autoStart') ?? false;
      fragmentation = prefs.getBool('fragmentation') ?? false;
      effectType = prefs.getString('effectType') ?? 'off';
    });
  }

  Future<void> _saveSettings() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('subscriptionUrl', _linkController.text.trim());
    await prefs.setBool('bypassRussia', bypassRussia);
    await prefs.setBool('killSwitch', killSwitch);
    await prefs.setBool('autoStart', autoStart);
    await prefs.setBool('fragmentation', fragmentation);
    await prefs.setString('effectType', effectType);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сохранено!')),
      );
    }
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 5),
      child: Text(title,
          style: GoogleFonts.manrope(
              fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
    );
  }

  Widget _buildSwitch(String title, String subtitle, bool value,
      Function(bool) onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: TextStyle(color: Colors.grey[400], fontSize: 11)),
              ],
            ),
          ),
          Switch(
            value: value,
            activeColor: Color(int.parse(widget.currentColor.replaceFirst('#', '0xff'))),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0A0812), Color(0xFF120B1A)],
        ),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Настройки',
                  style: GoogleFonts.manrope(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: Colors.white)),
              const SizedBox(height: 30),
              _buildSectionTitle('Подписка'),
              TextField(
                controller: _linkController,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'https://...',
                  hintStyle: const TextStyle(color: Colors.grey),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.05),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 20),
              _buildSectionTitle('Туннель'),
              _buildSwitch('Обход РФ', 'Госуслуги и банки напрямую', bypassRussia,
                  (v) => setState(() => bypassRussia = v)),
              const SizedBox(height: 10),
              _buildSwitch('Kill Switch', 'Блокировать интернет при обрыве VPN',
                  killSwitch, (v) => setState(() => killSwitch = v)),
              const SizedBox(height: 10),
              _buildSwitch('Автозапуск', 'Включать VPN при старте телефона',
                  autoStart, (v) => setState(() => autoStart = v)),
              const SizedBox(height: 10),
              _buildSwitch('Фрагментация', 'Обход DPI (если провайдер режет)',
                  fragmentation, (v) => setState(() => fragmentation = v)),
              const SizedBox(height: 20),
              _buildSectionTitle('Внешний вид'),
              Text('Цвет акцента',
                  style: GoogleFonts.manrope(
                      fontSize: 14, color: Colors.grey)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  '#ff2bd6',
                  '#ff8a1f',
                  '#34b6ff',
                  '#2ee6a6',
                  '#8b2cff',
                  '#ff5c6c',
                  '#ffb020'
                ].map((color) {
                  final isSelected = widget.currentColor == color;
                  return GestureDetector(
                    onTap: () => widget.onColorChanged(color),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Color(
                            int.parse(color.replaceFirst('#', '0xff'))),
                        shape: BoxShape.circle,
                        border: isSelected
                            ? Border.all(color: Colors.white, width: 3)
                            : null,
                        boxShadow: [
                          BoxShadow(
                              color: Color(
                                      int.parse(color.replaceFirst('#', '0xff')))
                                  .withValues(alpha: 0.5),
                              blurRadius: 10)
                        ],
                      ),
                      child: isSelected
                          ? const Icon(Icons.check,
                              color: Colors.white, size: 20)
                          : null,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 15),
              Text('Тема',
                  style: GoogleFonts.manrope(
                      fontSize: 14, color: Colors.grey)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: widget.currentTheme,
                    dropdownColor: const Color(0xFF1B1E21),
                    isExpanded: true,
                    icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
                    style: const TextStyle(color: Colors.white),
                    items: const [
                      DropdownMenuItem(value: 'neon', child: Text('Neon')),
                      DropdownMenuItem(value: 'autumn', child: Text('Autumn')),
                      DropdownMenuItem(value: 'ice', child: Text('Ice')),
                      DropdownMenuItem(value: 'hw', child: Text('Hacker Way')),
                    ],
                    onChanged: (v) {
                      if (v != null) widget.onThemeChanged(v);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 15),
              Text('Шрифт',
                  style: GoogleFonts.manrope(
                      fontSize: 14, color: Colors.grey)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: widget.currentFont,
                    dropdownColor: const Color(0xFF1B1E21),
                    isExpanded: true,
                    icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
                    style: const TextStyle(color: Colors.white),
                    items: const [
                      DropdownMenuItem(value: 'manrope', child: Text('Manrope')),
                      DropdownMenuItem(value: 'oswald', child: Text('Oswald')),
                      DropdownMenuItem(value: 'lato', child: Text('Lato')),
                      DropdownMenuItem(value: 'poppins', child: Text('Poppins')),
                    ],
                    onChanged: (v) {
                      if (v != null) widget.onFontChanged(v);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 15),
              Text('Эффекты',
                  style: GoogleFonts.manrope(
                      fontSize: 14, color: Colors.grey)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: effectType,
                    dropdownColor: const Color(0xFF1B1E21),
                    isExpanded: true,
                    icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
                    style: const TextStyle(color: Colors.white),
                    items: const [
                      DropdownMenuItem(value: 'off', child: Text('Выкл')),
                      DropdownMenuItem(value: 'snow', child: Text('Снег')),
                      DropdownMenuItem(value: 'leaves', child: Text('Листопад')),
                    ],
                    onChanged: (v) => setState(() => effectType = v ?? 'off'),
                  ),
                ),
              ),
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saveSettings,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(
                        int.parse(widget.currentColor.replaceFirst('#', '0xff'))),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text('Сохранить',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
