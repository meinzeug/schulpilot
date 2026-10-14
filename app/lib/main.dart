import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import 'api.dart';
import 'account_deletion_screen.dart';
import 'auth_screens.dart';
import 'dashboard.dart';
import 'material_screen.dart';
import 'settings_screen.dart';
import 'school_day_screen.dart';
import 'school_day_history.dart';
import 'ui.dart';
import 'unit_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Email links carry one-time secrets in the fragment, outside HTTP logs.
  // The default path strategy drops that fragment during initial routing.
  setUrlStrategy(PathUrlStrategy(BrowserPlatformLocation(), true));
  final state = AppState();
  await state.restore();
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    try {
      final lost = await ImagePicker().retrieveLostData();
      final owner = await state.storage.read(key: 'camera_child');
      if (state.isChild &&
          owner == state.user?['child_id'] &&
          lost.files?.isNotEmpty == true &&
          await lost.files!.first.length() <= 10 * 1024 * 1024) {
        var total = 0;
        for (final file in lost.files!.take(8)) {
          final length = await file.length();
          if (length > 10 * 1024 * 1024 || total + length > 20 * 1024 * 1024) {
            break;
          }
          state.recoveredPhotos.add(await file.readAsBytes());
          total += length;
        }
        if (state.recoveredPhotos.isNotEmpty) {
          state.recoveredPhoto = state.recoveredPhotos.removeAt(0);
        }
      }
      await state.storage.delete(key: 'camera_child');
    } catch (_) {
      // A failed camera recovery must not prevent login or opening saved pages.
    }
  }
  runApp(SchulpilotApp(state));
}

class SchulpilotApp extends StatefulWidget {
  final AppState state;
  const SchulpilotApp(this.state, {super.key});
  @override
  State<SchulpilotApp> createState() => _SchulpilotAppState();
}

class _SchulpilotAppState extends State<SchulpilotApp> {
  @override
  void initState() {
    super.initState();
    widget.state.push.onOpen = () {
      widget.state.push.openPending = false;
      router.go('/app');
    };
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.state.push.openPending) {
        widget.state.push.openPending = false;
        router.go('/app');
      }
    });
  }

  late final GoRouter router = GoRouter(
    refreshListenable: widget.state,
    redirect: (context, route) {
      final path = route.uri.path;
      final protected =
          path == '/app' ||
          path == '/settings' ||
          path == '/admin' ||
          path.startsWith('/child/') ||
          path.startsWith('/after-school/') ||
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
          builder: (context, s) =>
              AuthScreen(widget.state, mode: mode, linkUri: s.uri),
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
        path: '/after-school/:id',
        builder: (context, s) => SchoolDayScreen(
          widget.state,
          childId: s.pathParameters['id']!,
          dayId: s.uri.queryParameters['day'],
        ),
      ),
      GoRoute(
        path: '/after-school/:id/history',
        builder: (context, s) =>
            SchoolDayHistory(widget.state, childId: s.pathParameters['id']!),
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
      GoRoute(
        path: '/account-deletion',
        builder: (context, s) => AccountDeletionScreen(widget.state),
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
    widget.state.push.onOpen = null;
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
