import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_v2ray_client/flutter_v2ray.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';

void main() => runApp(const MyApp());

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String currentTheme = 'neon';
  String currentFont = 'manrope';

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
    });
  }

  void changeTheme(String newTheme) => setState(() => currentTheme = newTheme);
  void changeFont(String newFont) => setState(() => currentFont = newFont);

  TextTheme _getTextTheme() {
    switch (currentFont) {
      case 'oswald': return GoogleFonts.oswaldTextTheme();
      case 'lato': return GoogleFonts.latoTextTheme();
      case 'poppins': return GoogleFonts.poppinsTextTheme();
      default: return GoogleFonts.manropeTextTheme();
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
      ),
    );
  }
}

class MainScreen extends StatefulWidget {
  final String currentTheme;
  final Function(String) onThemeChanged;
  final String currentFont;
  final Function(String) onFontChanged;

  const MainScreen({
    super.key,
    required this.currentTheme,
    required this.onThemeChanged,
    required this.currentFont,
    required this.onFontChanged,
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
          ? HomeTab(theme: widget.currentTheme)
          : SettingsTab(
              currentTheme: widget.currentTheme,
              onThemeChanged: widget.onThemeChanged,
              currentFont: widget.currentFont,
              onFontChanged: widget.onFontChanged,
            ),
      bottomNavigationBar: Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1B1E21).withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 20, offset: const Offset(0, 10))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: (index) => setState(() => _currentIndex = index),
            backgroundColor: Colors.transparent,
            elevation: 0,
            selectedItemColor: const Color(0xFFFF2BD6),
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

// --- ГЛАВНАЯ (КРАСИВАЯ ВЕРСИЯ) ---
class HomeTab extends StatefulWidget {
  final String theme;
  const HomeTab({super.key, required this.theme});

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

  String trafficUsed = "—";
  String trafficTotal = "—";
  String expireDate = "—";

  bool weatherEffects = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
    _bgController = AnimationController(vsync: this, duration: const Duration(seconds: 8))..repeat(reverse: true);

    v2ray = V2ray(
      onStatusChanged: (status) {
        if (mounted) setState(() => connectionState = status.state);
      },
    );
    v2ray.initialize(notificationIconResourceType: "mipmap", notificationIconResourceName: "ic_launcher");
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _bgController.dispose();
    super.dispose();
  }

  Map<String, Color> getThemeColors() {
    switch (widget.theme) {
      case 'autumn': return {'bg': const Color(0xFF120B07), 'accent': const Color(0xFFFF8A1F), 'accent2': const Color(0xFFC2391B)};
      case 'ice': return {'bg': const Color(0xFF070C16), 'accent': const Color(0xFF34B6FF), 'accent2': const Color(0xFF3D5BFF)};
      case 'hw': return {'bg': const Color(0xFF0D0814), 'accent': const Color(0xFFFF7A00), 'accent2': const Color(0xFF8B2CFF)};
      default: return {'bg': const Color(0xFF0A0812), 'accent': const Color(0xFFFF2BD6), 'accent2': const Color(0xFF7B2CFF)};
    }
  }

  Future<void> _loadSettings() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      subscriptionUrl = prefs.getString('subscriptionUrl') ?? "";
      weatherEffects = prefs.getBool('weatherEffects') ?? false;
    });
    if (subscriptionUrl.isNotEmpty) _fetchSubscription();
  }

  Future<void> _fetchSubscription() async {
    if (subscriptionUrl.isEmpty) return;
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
              case 'upload': upload = int.tryParse(kv[1]) ?? 0; break;
              case 'download': download = int.tryParse(kv[1]) ?? 0; break;
              case 'total': total = int.tryParse(kv[1]) ?? 0; break;
              case 'expire': expire = int.tryParse(kv[1]) ?? 0; break;
            }
          }
        }
        trafficUsed = "${((upload + download) / (1024 * 1024 * 1024)).toStringAsFixed(2)} ГБ";
        trafficTotal = "${(total / (1024 * 1024 * 1024)).toStringAsFixed(1)} ГБ";
        if (expire > 0) expireDate = DateTime.fromMillisecondsSinceEpoch(expire * 1000).toString().split(' ')[0];
      }

      final content = response.body.trim();
      String decodedContent = content;
      try { decodedContent = utf8.decode(base64.decode(content)); } catch (_) {}

      final lines = decodedContent.split('\n');
      parsedServers.clear();
      for (var line in lines) {
        line = line.trim();
        if (line.startsWith('vless://') || line.startsWith('vmess://') || 
            line.startsWith('trojan://') || line.startsWith('hy2://') || 
            line.startsWith('hysteria2://') || line.startsWith('ss://')) {
          try { parsedServers.add(V2ray.parseFromURL(line)); } catch (_) {}
        }
      }
      if (parsedServers.isEmpty) _showErrorDialog('В подписке нет серверов');
    } catch (e) {
      _showErrorDialog('Ошибка загрузки подписки');
    } finally {
      if (mounted) setState(() => isLoading = false);
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
      if (await v2ray.requestPermission()) {
        v2ray.startV2Ray(remark: parser.remark, config: parser.getFullConfiguration(), proxyOnly: false);
        if (mounted) setState(() => connectionState = 'CONNECTED');
      }
    } catch (e) {
      _showErrorDialog('Ошибка подключения: $e');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _showErrorDialog(String message) {
    if (mounted) {
      showDialog(context: context, builder: (ctx) => AlertDialog(
        title: const Text('Ошибка'), content: Text(message),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ОК'))],
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isConnected = connectionState == 'CONNECTED';
    final colors = getThemeColors();

    return Stack(
      children: [
        // Анимированный фон
        AnimatedBuilder(
          animation: _bgController,
          builder: (context, child) {
            return Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(-0.8 + (_bgController.value * 0.2), -0.8 + (_bgController.value * 0.1)),
                  radius: 1.8,
                  colors: [
                    colors['bg']!,
                    colors['accent2']!.withValues(alpha: 0.3 + (_bgController.value * 0.2)),
                  ],
                ),
              ),
            );
          },
        ),
        
        if (weatherEffects && mounted) const WeatherEffect(),

        SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 100),
            child: Column(
              children: [
                // Шапка
                Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: colors['accent']!.withValues(alpha: 0.2), shape: BoxShape.circle),
                        child: Icon(Icons.shield_rounded, color: colors['accent'], size: 32),
                      ),
                      const SizedBox(width: 10),
                      Text('Monta VPN', style: GoogleFonts.manrope(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 1)),
                    ],
                  ),
                ),

                // Кнопка подключения в стеклянной карточке
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(32),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 30, offset: const Offset(0, 15))],
                  ),
                  child: Column(
                    children: [
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          ScaleTransition(
                            scale: Tween(begin: 0.95, end: 1.15).animate(_pulseController),
                            child: Container(
                              width: 200, height: 200,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: (isConnected ? Colors.green : colors['accent']!).withValues(alpha: 0.15), width: 1),
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: isLoading ? null : toggleVPN,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 250),
                              width: 150, height: 150,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: isConnected ? [Colors.green, Colors.greenAccent] : [colors['accent']!, colors['accent2']!],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: (isConnected ? Colors.green : colors['accent']!).withValues(alpha: 0.6),
                                    blurRadius: 40,
                                    spreadRadius: 10,
                                  ),
                                ],
                              ),
                              child: isLoading
                                  ? const Center(child: CircularProgressIndicator(color: Colors.white))
                                  : const Icon(Icons.power_settings_new_rounded, size: 60, color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text(
                        isConnected ? 'VPN Включен' : 'VPN Отключен',
                        style: GoogleFonts.manrope(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        isConnected ? 'Ваш трафик защищен' : 'Нажмите для подключения',
                        style: TextStyle(fontSize: 14, color: Colors.grey[400]),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Карточки (Трафик и Срок)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Expanded(child: _buildInfoCard(Icons.data_usage_rounded, 'Трафик', '$trafficUsed / $trafficTotal')),
                      const SizedBox(width: 12),
                      Expanded(child: _buildInfoCard(Icons.calendar_today_rounded, 'Срок', expireDate)),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Серверы
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Серверы', style: GoogleFonts.manrope(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                            IconButton(
                              icon: const Icon(Icons.refresh_rounded, color: Colors.grey, size: 20),
                              onPressed: () {
                                _fetchSubscription();
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (parsedServers.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(20),
                            child: Center(child: Text('Подписка не добавлена', style: TextStyle(color: Colors.grey))),
                          )
                        else
                          ...parsedServers.asMap().entries.map((entry) {
                            return GestureDetector(
                              onTap: () => setState(() => currentServer = entry.key),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: currentServer == entry.key ? colors['accent']!.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.03),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: currentServer == entry.key ? colors['accent']! : Colors.transparent, width: 1.5),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: currentServer == entry.key ? colors['accent']!.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Icon(Icons.dns_rounded, color: currentServer == entry.key ? colors['accent'] : Colors.grey, size: 18),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        entry.value.remark,
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: currentServer == entry.key ? FontWeight.bold : FontWeight.normal,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (currentServer == entry.key)
                                      Icon(Icons.check_circle_rounded, color: colors['accent'], size: 20),
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
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, 5))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xFFFF2BD6).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: const Color(0xFFFF2BD6), size: 20),
          ),
          const SizedBox(height: 10),
          Text(title, style: TextStyle(fontSize: 12, color: Colors.grey[400])),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
        ],
      ),
    );
  }
}

// --- АНИМАЦИЯ СНЕГА ---
class WeatherEffect extends StatefulWidget {
  const WeatherEffect({super.key});

  @override
  State<WeatherEffect> createState() => _WeatherEffectState();
}

class _WeatherEffectState extends State<WeatherEffect> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<Snowflake> _flakes = [];
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat();
    for (int i = 0; i < 30; i++) {
      _flakes.add(Snowflake.random(_random));
    }
    _controller.addListener(() {
      if (mounted) {
        setState(() {
          for (var flake in _flakes) {
            flake.update();
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
    return CustomPaint(painter: SnowPainter(_flakes), size: Size.infinite);
  }
}

class Snowflake {
  double x, y, speed, size;
  Snowflake({required this.x, required this.y, required this.speed, required this.size});
  factory Snowflake.random(Random random) {
    return Snowflake(
      x: random.nextDouble() * 400,
      y: random.nextDouble() * 800,
      speed: 1 + random.nextDouble() * 3,
      size: 2 + random.nextDouble() * 4,
    );
  }
  void update() {
    y += speed;
    if (y > 800) {
      y = -10;
      x = Random().nextDouble() * 400;
    }
  }
}

class SnowPainter extends CustomPainter {
  final List<Snowflake> flakes;
  SnowPainter(this.flakes);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.5)..style = PaintingStyle.fill;
    for (var flake in flakes) {
      canvas.drawCircle(Offset(flake.x, flake.y), flake.size, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// --- НАСТРОЙКИ ---
class SettingsTab extends StatefulWidget {
  final String currentTheme;
  final Function(String) onThemeChanged;
  final String currentFont;
  final Function(String) onFontChanged;

  const SettingsTab({
    super.key,
    required this.currentTheme,
    required this.onThemeChanged,
    required this.currentFont,
    required this.onFontChanged,
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
  bool weatherEffects = false;

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
      weatherEffects = prefs.getBool('weatherEffects') ?? false;
    });
  }

  Future<void> _saveSettings() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('subscriptionUrl', _linkController.text.trim());
    await prefs.setBool('bypassRussia', bypassRussia);
    await prefs.setBool('killSwitch', killSwitch);
    await prefs.setBool('autoStart', autoStart);
    await prefs.setBool('fragmentation', fragmentation);
    await prefs.setBool('weatherEffects', weatherEffects);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Сохранено!')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF0A0812), Color(0xFF120B1A)])),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Настройки', style: GoogleFonts.manrope(fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white)),
              const SizedBox(height: 30),

              _buildSectionTitle('Подписка'),
              TextField(
                controller: _linkController,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                maxLines: 3,
                decoration: InputDecoration(hintText: 'https://...', hintStyle: const TextStyle(color: Colors.grey), filled: true, fillColor: Colors.white.withValues(alpha: 0.05), border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none)),
              ),
              const SizedBox(height: 20),

              _buildSectionTitle('Туннель'),
              _buildSwitch('Обход РФ', 'Госуслуги и банки напрямую', bypassRussia, (v) => setState(() => bypassRussia = v)),
              const SizedBox(height: 10),
              _buildSwitch('Kill Switch', 'Блокировать интернет при обрыве VPN', killSwitch, (v) => setState(() => killSwitch = v)),
              const SizedBox(height: 10),
              _buildSwitch('Автозапуск', 'Включать VPN при старте телефона', autoStart, (v) => setState(() => autoStart = v)),
              const SizedBox(height: 10),
              _buildSwitch('Фрагментация', 'Обход DPI (если провайдер режет)', fragmentation, (v) => setState(() => fragmentation = v)),
              const SizedBox(height: 20),

              _buildSectionTitle('Внешний вид'),
              Text('Тема', style: GoogleFonts.manrope(fontSize: 14, color: Colors.grey)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(16)),
                child: DropdownButton<String>(
                  value: widget.currentTheme,
                  dropdownColor: const Color(0xFF1B1E21),
                  style: const TextStyle(color: Colors.white),
                  isExpanded: true,
                  underline: const SizedBox(),
                  items: const [
                    DropdownMenuItem(value: 'neon', child: Text('Неон')),
                    DropdownMenuItem(value: 'autumn', child: Text('Осень')),
                    DropdownMenuItem(value: 'ice', child: Text('Лёд')),
                    DropdownMenuItem(value: 'hw', child: Text('Хэллоуин')),
                  ],
                  onChanged: (val) async {
                    if (val != null) {
                      widget.onThemeChanged(val);
                      SharedPreferences prefs = await SharedPreferences.getInstance();
                      await prefs.setString('theme', val);
                    }
                  },
                ),
              ),
              const SizedBox(height: 15),
              Text('Шрифт', style: GoogleFonts.manrope(fontSize: 14, color: Colors.grey)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(16)),
                child: DropdownButton<String>(
                  value: widget.currentFont,
                  dropdownColor: const Color(0xFF1B1E21),
                  style: const TextStyle(color: Colors.white),
                  isExpanded: true,
                  underline: const SizedBox(),
                  items: const [
                    DropdownMenuItem(value: 'manrope', child: Text('Manrope (жирный)')),
                    DropdownMenuItem(value: 'oswald', child: Text('Oswald (тонкий)')),
                    DropdownMenuItem(value: 'lato', child: Text('Lato (обычный)')),
                    DropdownMenuItem(value: 'poppins', child: Text('Poppins (круглый)')),
                  ],
                  onChanged: (val) async {
                    if (val != null) {
                      widget.onFontChanged(val);
                      SharedPreferences prefs = await SharedPreferences.getInstance();
                      await prefs.setString('font', val);
                    }
                  },
                ),
              ),
              const SizedBox(height: 15),
              _buildSwitch('Погодные эффекты', 'Снег на фоне', weatherEffects, (v) => setState(() => weatherEffects = v)),

              const SizedBox(height: 40),

              ElevatedButton(
                onPressed: _saveSettings,
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF2BD6), padding: const EdgeInsets.symmetric(vertical: 18), minimumSize: const Size(double.infinity, 0), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                child: const Text('Сохранить', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Text(title, style: GoogleFonts.manrope(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFFFF2BD6))),
    );
  }

  Widget _buildSwitch(String title, String subtitle, bool value, Function(bool) onChanged) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withValues(alpha: 0.1))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)), Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey))])),
          Switch(value: value, activeColor: const Color(0xFFFF2BD6), onChanged: onChanged),
        ],
      ),
    );
  }
}
