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
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF0A0812),
      ),
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
  // ТВОЯ ССЫЛКА (Нидерланды TCP)
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
      appBar: AppBar(
        title: const Text('MONTA VPN', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isConnected ? Colors.green.withValues(alpha: 0.2) : Colors.grey.withValues(alpha: 0.1),
                border: Border.all(
                  color: isConnected ? Colors.green : Colors.grey,
                  width: 3,
                ),
                boxShadow: isConnected
                    ? [
                  BoxShadow(
                    color: Colors.green.withValues(alpha: 0.5),
                    blurRadius: 30,
                    spreadRadius: 5,
                  )
                ]
                    : [],
              ),
              child: Icon(
                isConnected ? Icons.lock : Icons.lock_open,
                size: 70,
                color: isConnected ? Colors.green : Colors.grey,
              ),
            ),
            const SizedBox(height: 40),
            Text(
              isConnected ? 'VPN Включен' : 'VPN Отключен',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: isConnected ? Colors.green : Colors.white,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              isConnected ? 'Ваш трафик защищен' : 'Нажмите кнопку ниже',
              style: const TextStyle(fontSize: 15, color: Colors.grey),
            ),
            const SizedBox(height: 50),
            SizedBox(
              width: 250,
              height: 60,
              child: ElevatedButton(
                onPressed: isLoading ? null : toggleVPN,
                style: ElevatedButton.styleFrom(
                  backgroundColor: isConnected ? Colors.redAccent : const Color(0xFF00C853),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                  elevation: 5,
                ),
                child: isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(
                  isConnected ? 'ОТКЛЮЧИТЬ' : 'ПОДКЛЮЧИТЬ',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}