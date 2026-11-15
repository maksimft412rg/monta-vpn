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
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  final List<Widget> _pages = [
    const HomeTab(),
    const SettingsTab(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_currentIndex],
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1B1E21),
          border: Border(top: BorderSide(color: Colors.white12)),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          backgroundColor: const Color(0xFF1B1E21),
          selectedItemColor: const Color(0xFFFF2BD6),
          unselectedItemColor: Colors.grey,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Главная'),
            BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Настройки'),
          ],
        ),
      ),
    );
  }
}

// --- ВКЛАДКА ГЛАВНАЯ ---
class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  late final V2ray v2ray;
  bool isLoading = false;
  String connectionState = 'DISCONNECTED';
  String configLink = "";
  
  // Серверы (визуальный список)
  final List<Map<String, String>> servers = [
    {"name": "🇳🇱 Нидерланды · TCP", "protocol": "VLESS"},
    {"name": "🇷🇺 Россия · TCP", "protocol": "VLESS"},
    {"name": "🇹🇷 Турция · XHTTP", "protocol": "VLESS"},
    {"name": "🇵🇱 Польша · gRPC", "protocol": "VLESS"},
  ];
  int currentServer = 0;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    v2ray = V2ray(
      onStatusChanged: (status) {
        setState(() => connectionState = status.state);
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
      configLink = prefs.getString('configLink') ?? "vless://5ddb9ba9-79b9-4dc4-83e4-f4767963c229@0988b3t.nl18.h1clayd.click:443?type=tcp&security=reality&sni=0988b3t.nl18.h1clayd.click&fp=firefox&pbk=U0rnaVzuOd8A5Xt09wyYR9on1a5GLa7yo-O9hLsNI1I&sid=240f9135b8ebc770&spx=%2F&encryption=none#MONTA";
    });
  }

  void toggleVPN() async {
    if (connectionState == 'CONNECTED') {
      v2ray.stopV2Ray();
      return;
    }

    if (configLink.isEmpty) {
      _showErrorDialog('Вставьте ссылку в Настройках!');
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
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ОК'))],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isConnected = connectionState == 'CONNECTED';

    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(-0.8, -0.8),
          radius: 1.5,
          colors: [Color(0xFF0A0812), Color(0xFF1B0B3F)],
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
                    const Icon(Icons.shield, color: Color(0xFFFF2BD6), size: 40),
                    const SizedBox(width: 10),
                    const Text(
                      'Monta VPN',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ],
                ),
              ),

              // Кнопка
              Center(
                child: GestureDetector(
                  onTap: isLoading ? null : toggleVPN,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: 180,
                    height: 180,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: isConnected
                            ? [Colors.green, Colors.greenAccent]
                            : [const Color(0xFFFF2BD6), const Color(0xFF7B2CFF)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: (isConnected ? Colors.green : const Color(0xFFFF2BD6)).withValues(alpha: 0.6),
                          blurRadius: 50,
                          spreadRadius: 15,
                        ),
                      ],
                    ),
                    child: isLoading
                        ? const Center(child: CircularProgressIndicator(color: Colors.white))
                        : const Icon(Icons.power_settings_new, size: 80, color: Colors.white),
                  ),
                ),
              ),
              
              const SizedBox(height: 20),
              Text(
                isConnected ? 'VPN Включен' : 'VPN Отключен',
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 30),

              // Карточки (трафик/пинг)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildInfoCard('Трафик', '0.00 ГБ'),
                  const SizedBox(width: 15),
                  _buildInfoCard('Пинг', '— мс'),
                ],
              ),
              const SizedBox(height: 30),

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
                              color: currentServer == entry.key ? const Color(0xFFFF2BD6).withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: currentServer == entry.key ? const Color(0xFFFF2BD6) : Colors.transparent),
                            ),
                            child: Row(
                              children: [
                                Text(entry.value["name"]!, style: const TextStyle(color: Colors.white)),
                                const Spacer(),
                                Text(entry.value["protocol"]!, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard(String title, String value) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        children: [
          Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 5),
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
        ],
      ),
    );
  }
}

// --- ВКЛАДКА НАСТРОЙКИ ---
class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key});

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  final TextEditingController _linkController = TextEditingController();
  String selectedProtocol = "VLESS";

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _linkController.text = prefs.getString('configLink') ?? "";
      selectedProtocol = prefs.getString('protocol') ?? "VLESS";
    });
  }

  Future<void> _saveSettings() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('configLink', _linkController.text.trim());
    await prefs.setString('protocol', selectedProtocol);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Настройки сохранены!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0A0812),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Настройки', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 20),

              // Ссылка
              const Text('Ссылка подписки', style: TextStyle(fontSize: 16, color: Colors.white)),
              const SizedBox(height: 10),
              TextField(
                controller: _linkController,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'vless:// / vmess:// / trojan://',
                  hintStyle: const TextStyle(color: Colors.grey),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.05),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 20),

              // Протокол
              const Text('Протокол', style: TextStyle(fontSize: 16, color: Colors.white)),
              const SizedBox(height: 10),
              DropdownButton<String>(
                value: selectedProtocol,
                dropdownColor: const Color(0xFF1B1E21),
                style: const TextStyle(color: Colors.white),
                isExpanded: true,
                items: const [
                  DropdownMenuItem(value: 'VLESS', child: Text('VLESS')),
                  DropdownMenuItem(value: 'VMess', child: Text('VMess')),
                  DropdownMenuItem(value: 'Trojan', child: Text('Trojan')),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => selectedProtocol = val);
                },
              ),
              const SizedBox(height: 30),

              // Сохранить
              ElevatedButton(
                onPressed: _saveSettings,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF2BD6),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Сохранить настройки', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
