import 'package:flutter/material.dart';
import 'package:flutter_v2ray_client/flutter_v2ray.dart';

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
  // ССЫЛКА (ВСТАВЬ СВОЮ)
  final String configLink = "vless://5ddb9ba9-79b9-4dc4-83e4-f4767963c229@0988b3t.nl18.h1clayd.click:443?type=tcp&security=reality&sni=0988b3t.nl18.h1clayd.click&fp=firefox&pbk=U0rnaVzuOd8A5Xt09wyYR9on1a5GLa7yo-O9hLsNI1I&sid=240f9135b8ebc770&spx=%2F&encryption=none#MONTA";

  late final V2ray v2ray;
  bool isLoading = false;
  String connectionState = 'DISCONNECTED';

  @override
  void initState() {
    super.initState();
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

  void toggleVPN() async {
    if (connectionState == 'CONNECTED') {
      v2ray.stopV2Ray();
      return;
    }

    setState(() => isLoading = true);

    try {
      V2RayURL parser = V2ray.parseFromURL(configLink);

      if (await v2ray.requestPermission()) {
        v2ray.startV2Ray(
          remark: parser.remark,
          config: parser.getFullConfiguration(),
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
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Логотип/Иконка
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: isConnected ? Colors.green.withValues(alpha: 0.5) : const Color(0xFFFF2BD6).withValues(alpha: 0.5),
                        blurRadius: 30,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.shield,
                    size: 50,
                    color: isConnected ? Colors.green : const Color(0xFFFF2BD6),
                  ),
                ),
                const SizedBox(height: 20),
                
                // Название
                const Text(
                  'MONTA VPN',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 10),
                
                // Статус
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  decoration: BoxDecoration(
                    color: isConnected ? Colors.green.withValues(alpha: 0.2) : Colors.grey.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                      color: isConnected ? Colors.green : Colors.grey,
                    ),
                  ),
                  child: Text(
                    isConnected ? 'ЗАЩИЩЕНО' : 'НЕ ЗАЩИЩЕНО',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: isConnected ? Colors.green : Colors.grey,
                    ),
                  ),
                ),
                const SizedBox(height: 50),

                // Кнопка подключения (Большая, с анимацией)
                GestureDetector(
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
                            ? [Colors.redAccent, Colors.red]
                            : [const Color(0xFFFF2BD6), const Color(0xFF7B2CFF)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: (isConnected ? Colors.redAccent : const Color(0xFFFF2BD6)).withValues(alpha: 0.6),
                          blurRadius: 50,
                          spreadRadius: 15,
                        ),
                      ],
                    ),
                    child: isLoading
                        ? const Center(child: CircularProgressIndicator(color: Colors.white, strokeWidth: 4))
                        : Icon(
                            Icons.power_settings_new,
                            size: 90,
                            color: Colors.white,
                          ),
                  ),
                ),
                const SizedBox(height: 40),

                // Текст-подсказка
                Text(
                  isConnected ? 'Ваш трафик зашифрован' : 'Нажмите, чтобы включить VPN',
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 80),

                // Карточки с инфо
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildCard('Трафик', '0.00 ГБ'),
                    const SizedBox(width: 20),
                    _buildCard('Пинг', '— мс'),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCard(String title, String value) {
    return Container(
      width: 140,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 5),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
