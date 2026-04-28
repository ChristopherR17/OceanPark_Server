import 'package:flutter/cupertino.dart';
import 'package:flutter_cupertino_desktop_kit/flutter_cupertino_desktop_kit.dart';
import 'layout.dart';

class SystemAwareCDKApp extends StatefulWidget {
  const SystemAwareCDKApp({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  State<SystemAwareCDKApp> createState() => _SystemAwareCDKAppState();
}

class _SystemAwareCDKAppState extends State<SystemAwareCDKApp>
    with WidgetsBindingObserver {
  late Brightness _platformBrightness;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _platformBrightness =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshBrightnessFromPlatform();
    });
    Future<void>.delayed(const Duration(milliseconds: 150), () {
      _refreshBrightnessFromPlatform();
    });
    Future<void>.delayed(const Duration(milliseconds: 500), () {
      _refreshBrightnessFromPlatform();
    });
  }

  void _refreshBrightnessFromPlatform() {
    if (!mounted) {
      return;
    }
    final Brightness nextBrightness =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
    if (nextBrightness == _platformBrightness) {
      return;
    }
    setState(() {
      _platformBrightness = nextBrightness;
    });
  }

  @override
  void didChangePlatformBrightness() {
    _refreshBrightnessFromPlatform();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CDKApp(
      defaultAppearance: CDKThemeAppearance.system,
      defaultColor: "systemBlue",
      child: widget.child,
    );
  }
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return const Layout(title: "Level builder");
  }
}
