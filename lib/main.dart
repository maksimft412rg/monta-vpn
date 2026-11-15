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
  
  String configLink = "";
  String selectedProtocol = "VLESS";
  
  // Список серверов (для визуала, можно менять)
  final List<Map<String, String>> servers = [
    {"name": "🇳🇱 Нидерланды · TCP", "protocol": "VLESS"},
    {"name": "🇷🇺 Россия · TCP", "protocol": "VLESS"},
    {"name": "🇹🇷 Турция · TCP", "protocol": "VLESS"},
    {"name": "🇵🇱 Польша · XHTTP", "protocol": "VLESS"},
  ];
  int currentServer = 0;

  final TextEditingController _linkController = TextEditingController();

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
      configLink = prefs.getString('configLink') ?? "vless://5ddb9ba9-79b9-4dc4-83e4-f4767963c229@0988b3t.nl18.h1clayd.click:443?type=tcp&security=reality&sni=0988b3t.nl18.h1clayd.click&fp=firefox&pbk=U0rnaVzuOd8A5Xt09wyYR9on1a5GLa7yo-O9hLsNI1I&sid=240f9135b8ebc770&spx=%2F&encryption=none#MONTA";
      _linkController.text = configLink;
    });
  }

  Future<void> _saveSettings() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
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

  void _showSettingsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) {
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
                  hintText: 'Вставьте vless:// / vmess:// / trojan://',
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
                  const Text('Протокол:', style: TextStyle(color: Colors.white)),
                  DropdownButton<String>(
                    value: selectedProtocol,
                    dropdownColor: const Color(0xFF1B1E21),
                    style: const TextStyle(color: Colors.white),
                    items: const [
                      DropdownMenuItem(value: 'VLESS', child: Text('VLESS')),
                      DropdownMenuItem(value: 'VMess', child: Text('VMess')),
                      DropdownMenuItem(value: 'Trojan', child: Text('Trojan')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => selectedProtocol = val);
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
                setState(() => configLink = _linkController.text.trim());
                _saveSettings();
                Navigator.pop(ctx);
              },
              child: const Text('Сохранить', style: TextStyle(color: Color(0xFFFF2BD6))),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isConnected = connectionState == 'CONNECTED';

    return Scaffold(
      body: Container(
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
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.settings, color: Color(0xFFFF2BD6)),
                        onPressed: () => _showSettingsDialog(context),
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

                // Выбор сервера
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
      ),
    );
  }
}
