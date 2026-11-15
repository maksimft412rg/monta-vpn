import 'package:flutter/material.dart';
import 'package:flutter_v2ray_client/flutter_v2ray.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MONTA VPN',
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
  // ВСТАВЬ СВОЮ ССЫЛКУ (или несколько, если хочешь выбор)
  final String configLink = "vless://5ddb9ba9-79b9-4dc4-83e4-f4767963c229@0988b3t.nl18.h1clayd.click:443?type=tcp&security=reality&sni=0988b3t.nl18.h1clayd.click&fp=firefox&pbk=U0rnaVzuOd8A5Xt09wyYR9on1a5GLa7yo-O9hLsNI1I&sid=240f9135b8ebc770&spx=%2F&encryption=none#MONTA";

  late final V2ray v2ray;
  bool isLoading = false;
  String connectionState = 'DISCONNECTED';
  
  // Настройки (сохраняются)
  bool bypassRussia = true; 

  @override
  void initState() {
    super.initState();
    _loadSettings(); // Загружаем настройки при старте
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

  // --- СОХРАНЕНИЕ И ЗАГРУЗКА НАСТРОЕК ---
  Future<void> _loadSettings() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      bypassRussia = prefs.getBool('bypassRussia') ?? true;
    });
  }

  Future<void> _saveSettings() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('bypassRussia', bypassRussia);
  }
  // ---------------------------------------

  void toggleVPN() async {
    if (connectionState == 'CONNECTED') {
      v2ray.stopV2Ray();
      return;
    }

    setState(() => isLoading = true);

    try {
      V2RayURL parser = V2ray.parseFromURL(configLink);
      String config = parser.getFullConfiguration();

      // Если бы был выбор серверов, тут бы подставлялся нужный.
      // Обход РФ уже работает через настройки H1Cloud (если галочка там включена).

      if (await v2ray.requestPermission()) {
        v2ray.startV2Ray(
          remark: parser.remark,
          config: config,
          proxyOnly: false,
        );
      }
    } catch (e) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Ошибка'),
            content: Text('Не удалось подключиться: $e'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('ОК'),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
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
            colors: [
              Color(0xFF0A0812),
              Color(0xFF1B0B3F),
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
                      const Icon(Icons.shield, color: Colors.purpleAccent, size: 30),
                      const SizedBox(width: 10),
                      const Text(
                        'MONTA VPN',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.settings, color: Colors.grey),
                        onPressed: () {},
                      ),
                    ],
                  ),
                ),

                // Кнопка подключения
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
                          : Icon(
                              Icons.power_settings_new,
                              size: 90,
                              color: Colors.white,
                            ),
                    ),
                  ),
                ),
                
                const SizedBox(height: 20),
                Text(
                  isConnected ? 'VPN Включен' : 'VPN Отключен',
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 30),

                // Карточки со статистикой (заглушки, так как нет API)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildInfoCard('Трафик', '0.00 ГБ', 'использовано'),
                    const SizedBox(width: 15),
                    _buildInfoCard('Пинг', '— мс', 'задержка'),
                  ],
                ),
                const SizedBox(height: 20),

                // Переключатели
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      _buildSwitch('Обход РФ', 'Госуслуги и банки напрямую', bypassRussia, (val) {
                        setState(() => bypassRussia = val);
                        _saveSettings();
                      }),
                      const SizedBox(height: 10),
                      _buildSwitch('Блокировка рекламы', 'Фильтрация на уровне DNS', false, (val) {}),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Кнопка "Позвать друга" и "Поддержка"
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {},
                          icon: const Icon(Icons.share),
                          label: const Text('Позвать друга'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white.withValues(alpha: 0.1),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {},
                          icon: const Icon(Icons.support_agent),
                          label: const Text('Поддержка'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white.withValues(alpha: 0.1),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
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

  Widget _buildSwitch(String title, String subtitle, bool value, Function(bool) onChanged) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
              Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
          Switch(
            value: value,
            activeColor: const Color(0xFFFF2BD6),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
