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
  // ССЫЛКА НА ТВОЙ СЕРВЕР
  final String configLink = "vless://5ddb9ba9-79b9-4dc4-83e4-f4767963c229@0988b3t.nl18.h1clayd.click:443?type=tcp&security=reality&sni=0988b3t.nl18.h1clayd.click&fp=firefox&pbk=U0rnaVzuOd8A5Xt09wyYR9on1a5GLa7yo-O9hLsNI1I&sid=240f9135b8ebc770&spx=%2F&encryption=none#MONTA";

  late final V2ray v2ray;
  bool isLoading = false;
  String connectionState = 'DISCONNECTED';
  bool isDarkTheme = true; // Флаг для переключения тем

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

  void toggleTheme() {
    setState(() {
      isDarkTheme = !isDarkTheme;
    });
  }

  @override
  Widget build(BuildContext context) {
    bool isConnected = connectionState == 'CONNECTED';

    // Цвета для тем
    Color bgColor = isDarkTheme ? const Color(0xFF0A0812) : const Color(0xFF120B07);
    Color accentColor = isDarkTheme ? const Color(0xFFFF2BD6) : const Color(0xFFFF8A1F);
    Color accentColor2 = isDarkTheme ? const Color(0xFF7B2CFF) : const Color(0xFFC2391B);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(-0.8, -0.8),
            radius: 1.5,
            colors: [
              bgColor,
              isDarkTheme ? const Color(0xFF1B0B3F) : const Color(0xFF3F1B0B),
            ],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              // Кнопка переключения темы
              Positioned(
                top: 10,
                right: 20,
                child: IconButton(
                  icon: Icon(Icons.color_lens, color: accentColor),
                  onPressed: toggleTheme,
                ),
              ),
              
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Заголовок
                    const Text(
                      'MONTA VPN',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 10),
                    
                    // Чип статуса
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        color: isConnected ? Colors.green.withValues(alpha: 0.2) : Colors.grey.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isConnected ? Colors.green : Colors.grey,
                        ),
                      ),
                      child: Text(
                        isConnected ? 'ЗАЩИЩЕНО' : 'ОТКЛЮЧЕНО',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isConnected ? Colors.green : Colors.grey,
                        ),
                      ),
                    ),
                    const SizedBox(height: 40),

                    // Большая кнопка подключения
                    GestureDetector(
                      onTap: isLoading ? null : toggleVPN,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: 160,
                        height: 160,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: isConnected
                                ? [Colors.redAccent, Colors.red]
                                : [accentColor, accentColor2],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: (isConnected ? Colors.redAccent : accentColor).withValues(alpha: 0.5),
                              blurRadius: 40,
                              spreadRadius: 10,
                            ),
                          ],
                        ),
                        child: isLoading
                            ? const Center(child: CircularProgressIndicator(color: Colors.white))
                            : Icon(
                                Icons.power_settings_new,
                                size: 80,
                                color: Colors.white,
                              ),
                      ),
                    ),
                    const SizedBox(height: 30),

                    // Текст под кнопкой
                    Text(
                      isConnected ? 'VPN Включен' : 'Нажмите кнопку, чтобы подключиться',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[400],
                      ),
                    ),
                    const SizedBox(height: 50),

                    // Карточки (Трафик и Пинг)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildInfoCard('Трафик', '0.00 ГБ', 'использовано'),
                        const SizedBox(width: 15),
                        _buildInfoCard('Пинг', '— мс', 'задержка'),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Виджет карточки
  Widget _buildInfoCard(String title, String value, String subtitle) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(fontSize: 12, color: Colors.grey[400]),
          ),
          const SizedBox(height: 5),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(fontSize: 11, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }
}
