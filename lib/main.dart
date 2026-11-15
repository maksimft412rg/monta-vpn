import 'package:flutter/material.dart';
import 'package:flutter_v2ray_client/flutter_v2ray.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Monta VPN',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const VPNPage(),
    );
  }
}

class VPNPage extends StatefulWidget {
  const VPNPage({super.key});

  @override
  State<VPNPage> createState() => _VPNPageState();
}

class _VPNPageState extends State<VPNPage> {
  late final V2ray v2ray;
  bool isLoading = false;
  String connectionState = 'DISCONNECTED';
  
  // Настройки
  bool bypassRussia = true; 
  String currentTheme = 'neon'; 
  String configLink = "";
  int currentServer = 0;
  
  final TextEditingController _linkController = TextEditingController();
  
  // Серверы (заглушка, так как нет API для парсинга. Если есть ссылка на подписку, тут будет список)
  List<String> servers = ["🇳🇱 Нидерланды · TCP", "🇷🇺 Россия · TCP", "🇹🇷 Турция · TCP", "🇵🇱 Польша · TCP"];

  @override
  void initState() {
    super.initState();
    _loadSettings();
    v2ray = V2ray(
      onStatusChanged: (status) {
        setState(() {
          connectionState = status.state;
        });
      },
    );
    v2ray.initialize(
      notificationIconResourceType: "mipmap",
      notificationIconResourceName: "ic_launcher",
    );
  }

  Future<void> _loadSettings() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      bypassRussia = prefs.getBool('bypassRussia') ?? true;
      currentTheme = prefs.getString('theme') ?? 'neon';
      configLink = prefs.getString('configLink') ?? "vless://5ddb9ba9-79b9-4dc4-83e4-f4767963c229@0988b3t.nl18.h1clayd.click:443?type=tcp&security=reality&sni=0988b3t.nl18.h1clayd.click&fp=firefox&pbk=U0rnaVzuOd8A5Xt09wyYR9on1a5GLa7yo-O9hLsNI1I&sid=240f9135b8ebc770&spx=%2F&encryption=none#MONTA";
      _linkController.text = configLink;
    });
  }

  Future<void> _saveSettings() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('bypassRussia', bypassRussia);
    await prefs.setString('theme', currentTheme);
    await prefs.setString('configLink', configLink);
  }

  void toggleVPN() async {
    if (connectionState == 'CONNECTED') {
      v2ray.stopV2Ray();
      return;
    }

    if (configLink.isEmpty) {
      _showErrorDialog('Сначала вставьте ссылку в Настройках!');
      return;
    }

    setState(() => isLoading = true);

    try {
      V2RayURL parser = V2ray.parseFromURL(configLink);
      String config = parser.getFullConfiguration();

      if (await v2ray.requestPermission()) {
        v2ray.startV2Ray(
          remark: parser.remark,
          config: config,
          proxyOnly: false,
        );
      }
    } catch (e) {
      _showErrorDialog('Не удалось подключиться: $e');
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
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ОК'))],
        ),
      );
    }
  }

  Map<String, Color> getThemeColors() {
    switch (currentTheme) {
      case 'autumn':
        return {'bg': const Color(0xFF120B07), 'accent': const Color(0xFFFF8A1F), 'accent2': const Color(0xFFC2391B)};
      case 'ice':
        return {'bg': const Color(0xFF070C16), 'accent': const Color(0xFF34B6FF), 'accent2': const Color(0xFF3D5BFF)};
      case 'hw':
        return {'bg': const Color(0xFF0D0814), 'accent': const Color(0xFFFF7A00), 'accent2': const Color(0xFF8B2CFF)};
      default:
        return {'bg': const Color(0xFF0A0812), 'accent': const Color(0xFFFF2BD6), 'accent2': const Color(0xFF7B2CFF)};
    }
  }

  void _showSettingsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) {
        final colors = getThemeColors();
        return AlertDialog(
          backgroundColor: const Color(0xFF1B1E21),
          title: const Text('Настройки', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _linkController,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Вставьте ссылку vless://...',
                  hintStyle: const TextStyle(color: Colors.grey),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.05),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 15),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Тема:', style: TextStyle(color: Colors.white)),
                  DropdownButton<String>(
                    value: currentTheme,
                    dropdownColor: const Color(0xFF1B1E21),
                    style: const TextStyle(color: Colors.white),
                    items: const [
                      DropdownMenuItem(value: 'neon', child: Text('Неон')),
                      DropdownMenuItem(value: 'autumn', child: Text('Осень')),
                      DropdownMenuItem(value: 'ice', child: Text('Лёд')),
                      DropdownMenuItem(value: 'hw', child: Text('Хэллоуин')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => currentTheme = val);
                        _saveSettings();
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                setState(() {
                  configLink = _linkController.text.trim();
                });
                _saveSettings();
                Navigator.pop(ctx);
              },
              child: Text('Сохранить', style: TextStyle(color: colors['accent'])),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isConnected = connectionState == 'CONNECTED';
    final colors = getThemeColors();

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(-0.8, -0.8),
            radius: 1.5,
            colors: [
              colors['bg']!,
              colors['accent2']!.withValues(alpha: 0.3),
            ],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Column(
              children: [
                // Шапка
                Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Row(
                    children: [
                      Icon(Icons.shield, color: colors['accent'], size: 40),
                      const SizedBox(width: 10),
                      const Text(
                        'Monta VPN',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: Icon(Icons.settings, color: colors['accent']),
                        onPressed: () => _showSettingsDialog(context),
                      ),
                    ],
                  ),
                ),

                // Кнопка
                const SizedBox(height: 20),
                Center(
                  child: GestureDetector(
                    onTap: isLoading ? null : toggleVPN,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: 200,
                      height: 200,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: isConnected
                              ? [Colors.green, Colors.greenAccent]
                              : [colors['accent']!, colors['accent2']!],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: (isConnected ? Colors.green : colors['accent']!).withValues(alpha: 0.6),
                            blurRadius: 50,
                            spreadRadius: 15,
                          ),
                        ],
                      ),
                      child: isLoading
                          ? const Center(child: CircularProgressIndicator(color: Colors.white))
                          : const Icon(Icons.power_settings_new, size: 90, color: Colors.white),
                    ),
                  ),
                ),
                
                const SizedBox(height: 20),
                Text(
                  isConnected ? 'VPN Включен' : 'VPN Отключен',
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 30),

                // Карточки
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildInfoCard('Трафик', '0.00 ГБ', 'использовано'),
                    const SizedBox(width: 15),
                    _buildInfoCard('Пинг', '— мс', 'задержка'),
                  ],
                ),
                const SizedBox(height: 20),

                // Список серверов
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Серверы', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                        const SizedBox(height: 10),
                        ...servers.asMap().entries.map((entry) {
                          return GestureDetector(
                            onTap: () => setState(() => currentServer = entry.key),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: currentServer == entry.key ? colors['accent']!.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: currentServer == entry.key ? colors['accent']! : Colors.transparent),
                              ),
                              child: Text(entry.value, style: const TextStyle(color: Colors.white)),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Переключатель
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Обход РФ', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                            Text('Госуслуги и банки напрямую', style: TextStyle(fontSize: 12, color: Colors.grey)),
                          ],
                        ),
                        Switch(
                          value: bypassRussia,
                          activeColor: colors['accent'],
                          onChanged: (val) {
                            setState(() => bypassRussia = val);
                            _saveSettings();
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard(String title, String value, String subtitle) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 5),
          Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 2),
          Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
    );
  }
}
