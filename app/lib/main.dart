import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';

import 'api.dart';
import 'auth_screens.dart';
import 'dashboard.dart';
import 'material_screen.dart';
import 'settings_screen.dart';
import 'ui.dart';
import 'unit_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();
  final state = AppState();
  await state.restore();
  runApp(SchulpilotApp(state));
}

class SchulpilotApp extends StatefulWidget {
  final AppState state;
  const SchulpilotApp(this.state, {super.key});
  @override
  State<SchulpilotApp> createState() => _SchulpilotAppState();
}

class _SchulpilotAppState extends State<SchulpilotApp> {
  late final GoRouter router = GoRouter(
    refreshListenable: widget.state,
    redirect: (context, route) {
      final path = route.uri.path;
      final protected =
          path == '/app' ||
          path == '/settings' ||
          path == '/admin' ||
          path.startsWith('/child/') ||
          path.startsWith('/material/') ||
          path.startsWith('/unit/');
      if (protected && widget.state.user == null) return '/login';
      if (path == '/admin' && !widget.state.isAdmin) return '/app';
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (context, s) => LandingScreen(widget.state)),
      for (final mode in [
        'login',
        'register',
        'recovery',
        'reset',
        'verify',
        'invite',
      ])
        GoRoute(
          path: '/$mode',
          builder: (context, s) => AuthScreen(widget.state, mode: mode),
        ),
      GoRoute(
        path: '/app',
        builder: (context, s) => DashboardScreen(widget.state),
      ),
      GoRoute(
        path: '/child/:id',
        builder: (context, s) =>
            ChildDetailScreen(widget.state, childId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/material/:id',
        builder: (context, s) =>
            MaterialScreen(widget.state, materialId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/unit/:id',
        builder: (context, s) =>
            UnitScreen(widget.state, unitId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, s) => SettingsScreen(widget.state),
      ),
      GoRoute(
        path: '/admin',
        builder: (context, s) => AdminScreen(widget.state),
      ),
      GoRoute(
        path: '/privacy',
        builder: (context, s) => const InformationScreen('privacy'),
      ),
      GoRoute(
        path: '/about',
        builder: (context, s) => const InformationScreen('about'),
      ),
    ],
    errorBuilder: (context, s) => Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () => context.go('/'),
          child: const Text('Diese Seite gibt es nicht. Zur Startseite.'),
        ),
      ),
    ),
  );
  @override
  void dispose() {
    router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'SCHULPILOT',
    debugShowCheckedModeBanner: false,
    theme: appTheme(),
    routerConfig: router,
  );
}
