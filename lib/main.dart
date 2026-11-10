import 'package:flutter/material.dart';
import 'license.dart';
import 'screens.dart';
import 'store.dart';
import 'util.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = Store();
  await store.init();
  await LicenseManager.I.init(store.dir);
  runApp(CertApp(store: store));
}

ThemeData _theme(Brightness b) {
  final dark = b == Brightness.dark;
  final cs = ColorScheme.fromSeed(seedColor: navy, brightness: b, primary: dark ? gold : navy, secondary: gold);
  return ThemeData(
    useMaterial3: true,
    colorScheme: cs,
    scaffoldBackgroundColor: dark ? const Color(0xFF0F1722) : paperGrey,
    appBarTheme: AppBarTheme(backgroundColor: dark ? const Color(0xFF1B2638) : navy, foregroundColor: Colors.white),
    navigationBarTheme: NavigationBarThemeData(indicatorColor: gold.withOpacity(0.35)),
  );
}

class CertApp extends StatelessWidget {
  const CertApp({super.key, required this.store});
  final Store store;
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (_, __) => MaterialApp(
        title: 'صانع الشهادات الاحترافي',
        debugShowCheckedModeBanner: false,
        locale: const Locale('ar'),
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        themeMode: store.themeMode,
        builder: (c, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
        home: Home(store: store),
      ),
    );
  }
}

class Home extends StatefulWidget {
  const Home({super.key, required this.store});
  final Store store;
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int tab = 0;
  @override
  Widget build(BuildContext context) {
    final st = widget.store;
    final pages = [
      Dashboard(store: st, go: (i) => setState(() => tab = i)),
      TemplatesScreen(store: st),
      ProjectsScreen(store: st),
      IssuedScreen(store: st),
      MoreScreen(store: st),
    ];
    const titles = ['الرئيسية', 'القوالب', 'مشاريعي', 'الشهادات الصادرة', 'المزيد'];
    return Scaffold(
      appBar: AppBar(title: Text(titles[tab])),
      body: pages[tab],
      floatingActionButton: tab == 2 ? FloatingActionButton.extended(onPressed: () => newBlank(context, st), icon: const Icon(Icons.add), label: const Text('مشروع جديد')) : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'الرئيسية'),
          NavigationDestination(icon: Icon(Icons.grid_view_outlined), selectedIcon: Icon(Icons.grid_view), label: 'القوالب'),
          NavigationDestination(icon: Icon(Icons.folder_open), selectedIcon: Icon(Icons.folder), label: 'مشاريعي'),
          NavigationDestination(icon: Icon(Icons.verified_outlined), selectedIcon: Icon(Icons.verified), label: 'الصادرة'),
          NavigationDestination(icon: Icon(Icons.more_horiz), label: 'المزيد'),
        ],
      ),
    );
  }
}