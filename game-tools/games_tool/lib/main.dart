import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'app_data.dart';
import 'app.dart';
import 'perf_probe.dart';

const _windowTitle = 'Games Tool';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  PerfProbe.startIfEnabled();
  runApp(const _BootstrapApp());
}

class _BootstrapApp extends StatefulWidget {
  const _BootstrapApp();

  @override
  State<_BootstrapApp> createState() => _BootstrapAppState();
}

class _BootstrapAppState extends State<_BootstrapApp> {
  AppData? _appData;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      await _configureDesktopWindow();
      final AppData appData = AppData();
      await appData.initializeStorage();
      if (!mounted) {
        return;
      }
      setState(() {
        _appData = appData;
      });
    } catch (error) {
      debugPrint('Bootstrap failed: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppData? appData = _appData;
    final Widget child;
    if (appData != null) {
      child = ChangeNotifierProvider.value(
        value: appData,
        child: const App(),
      );
    } else {
      child = const _LoadingScreen();
    }

    return SystemAwareCDKApp(child: child);
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = MediaQuery.platformBrightnessOf(context);
    return Container(
      color: brightness == Brightness.dark
          ? CupertinoColors.black
          : CupertinoColors.white,
    );
  }
}

Future<void> _configureDesktopWindow() async {
  if (kIsWeb) return;

  final isDesktop = defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux;

  if (!isDesktop) return;

  try {
    await windowManager.ensureInitialized();

    const windowOptions = WindowOptions(
      title: _windowTitle,
      size: Size(1280, 700),
      minimumSize: Size(1100, 700),
      center: true,
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
    await windowManager.setTitle(_windowTitle);
  } catch (_) {
    // Ignore when desktop window APIs are unavailable at runtime.
  }
}
