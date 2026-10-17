import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import 'api.dart';
import 'account_deletion_screen.dart';
import 'auth_screens.dart';
import 'dashboard.dart';
import 'collection_screen.dart';
import 'material_screen.dart';
import 'settings_screen.dart';
import 'installation_screen.dart';
import 'school_day_screen.dart';
import 'school_day_history.dart';
import 'ui.dart';
import 'unit_screen.dart';
import 'store_screens.dart';
import 'notification_panel.dart';
import 'google_login.dart';
import 'learning_preparation_screen.dart';
import 'progress_screen.dart';
import 'grades_screen.dart';
import 'vocabulary_screen.dart';
import 'language_workshop.dart';

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
  runApp(
    SchulpilotApp(
      state,
      initialLocation: kIsWeb
          ? null
          : nativeInitialLocation(
              WidgetsBinding.instance.platformDispatcher.defaultRouteName,
            ),
    ),
  );
}

class SchulpilotApp extends StatefulWidget {
  final AppState state;
  final String? initialLocation;
  const SchulpilotApp(this.state, {super.key, this.initialLocation});
  @override
  State<SchulpilotApp> createState() => _SchulpilotAppState();
}

class _SchulpilotAppState extends State<SchulpilotApp>
    with WidgetsBindingObserver {
  final messenger = GlobalKey<ScaffoldMessengerState>();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.state.addListener(_syncInbox);
    _syncInbox();
    widget.state.push.onOpen = () {
      widget.state.push.openPending = false;
      router.go('/notifications');
    };
    widget.state.push.onForeground = () {
      if (!mounted || widget.state.user == null) return;
      messenger.currentState?.showSnackBar(
        SnackBar(
          content: const Text('Es gibt Neuigkeiten in SCHULPILOT.'),
          action: SnackBarAction(
            label: 'Öffnen',
            onPressed: () => router.go('/notifications'),
          ),
        ),
      );
    };
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.state.push.openPending) {
        widget.state.push.openPending = false;
        router.go('/notifications');
      }
    });
  }

  void _syncInbox() => widget.state.inbox.activate(
    (widget.state.isChild || widget.state.isParent)
        ? (widget.state.user?['id'])
        : null,
  );

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    widget.state.inbox.foreground(state == AppLifecycleState.resumed);
  }

  late final GoRouter router = GoRouter(
    initialLocation: widget.initialLocation,
    refreshListenable: widget.state,
    redirect: (context, route) {
      if (!kIsWeb && route.uri.scheme == 'schulpilot') {
        return nativeInitialLocation(route.uri.toString());
      }
      final path = route.uri.path;
      if (widget.state.needsSetup && path != '/setup') return '/setup';
      if (!widget.state.needsSetup && path == '/setup') {
        return widget.state.isAdmin ? '/admin' : '/login';
      }
      final protected =
          path == '/app' ||
          path == '/settings' ||
          path == '/notifications' ||
          path == '/bestellungen' ||
          path.startsWith('/bestellen/') ||
          path.startsWith('/admin') ||
          path.startsWith('/child/') ||
          path.startsWith('/after-school/') ||
          path.startsWith('/material/') ||
          path.startsWith('/library/') ||
          path.startsWith('/learn/') ||
          path.startsWith('/learning-preparation/') ||
          path.startsWith('/progress/') ||
          path.startsWith('/grades/') ||
          path.startsWith('/unit/');
      if (protected && widget.state.user == null) {
        return path.startsWith('/bestell')
            ? '/login?next=${Uri.encodeComponent(path)}'
            : '/login';
      }
      if ((path.startsWith('/bestell') || path == '/angebote') &&
          (!kIsWeb || widget.state.isChild)) {
        return '/app';
      }
      if (path == '/' && widget.state.user != null) return '/app';
      if (path.startsWith('/admin') && !widget.state.isAdmin) return '/app';
      if (path == '/notifications' && widget.state.isAdmin) {
        return '/admin/push';
      }
      if (path.startsWith('/grades/') && !widget.state.isParent) return '/app';
      return null;
    },
    routes: [
      GoRoute(
        path: '/auth/google/start',
        builder: (context, s) =>
            GoogleCompletionScreen(widget.state, uri: s.uri, start: true),
      ),
      GoRoute(
        path: '/auth/google/complete',
        builder: (context, s) =>
            GoogleCompletionScreen(widget.state, uri: s.uri),
      ),
      GoRoute(
        path: '/setup',
        builder: (context, s) => InstallationScreen(widget.state),
      ),
      GoRoute(
        path: '/admin/settings',
        builder: (context, s) =>
            InstallationScreen(widget.state, initial: false),
      ),
      GoRoute(path: '/', builder: (context, s) => LandingScreen(widget.state)),
      GoRoute(
        path: '/angebote',
        builder: (context, s) => OffersScreen(widget.state),
      ),
      GoRoute(
        path: '/bedingungen',
        builder: (context, s) => OffersScreen(widget.state, terms: true),
      ),
      GoRoute(
        path: '/bestellen/:id',
        builder: (context, s) =>
            CheckoutScreen(widget.state, planId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/bestellungen',
        builder: (context, s) => OrdersScreen(widget.state),
      ),
      GoRoute(
        path: '/admin/verkauf',
        builder: (context, s) => StoreAdminScreen(widget.state),
      ),
      GoRoute(
        path: '/admin/push',
        builder: (context, s) => PushAdminScreen(widget.state),
      ),
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
          key: ValueKey(
            '${s.pathParameters['id']}:${s.uri.queryParameters['day'] ?? 'today'}',
          ),
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
        path: '/library/:id',
        builder: (context, s) =>
            CollectionScreen(widget.state, childId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/learn/:id',
        builder: (context, s) => CollectionScreen(
          widget.state,
          childId: s.pathParameters['id']!,
          learning: true,
        ),
      ),
      GoRoute(
        path: '/material/:id',
        builder: (context, s) =>
            MaterialScreen(widget.state, materialId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/progress/:id',
        builder: (context, s) => ProgressScreen(
          widget.state,
          key: ValueKey(
            'progress:${s.pathParameters['id']}:${widget.state.user?['id']}',
          ),
          childId: s.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/grades/:id',
        builder: (context, s) => GradesScreen(
          widget.state,
          key: ValueKey(
            'grades:${s.pathParameters['id']}:${widget.state.user?['id']}',
          ),
          childId: s.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/unit/:id',
        builder: (context, s) =>
            UnitScreen(widget.state, unitId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/vocabulary/:id',
        builder: (context, s) => VocabularyScreen(
          widget.state,
          key: ValueKey(
            'words:${s.pathParameters['id']}:${widget.state.user?['id']}:${s.uri.queryParameters['material']}:${s.uri.queryParameters['locale']}',
          ),
          childId: s.pathParameters['id']!,
          materialId: s.uri.queryParameters['material'],
          initialLocale: s.uri.queryParameters['locale'] ?? 'en-GB',
        ),
      ),
      GoRoute(
        path: '/language-projects/:id',
        builder: (context, s) => LanguageWorkshop(
          widget.state,
          key: ValueKey(
            'language:${s.pathParameters['id']}:${s.uri.queryParameters['project']}:${widget.state.user?['id']}',
          ),
          childId: s.pathParameters['id']!,
          materialId: s.uri.queryParameters['material'],
          projectId: s.uri.queryParameters['project'],
        ),
      ),
      GoRoute(
        path: '/learning-preparation/:childId/:jobId',
        builder: (context, s) => LearningPreparationScreen(
          widget.state,
          childId: s.pathParameters['childId']!,
          jobId: s.pathParameters['jobId']!,
        ),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, s) => SettingsScreen(widget.state),
      ),
      GoRoute(
        path: '/notifications',
        builder: (context, s) => NotificationsScreen(widget.state),
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
    WidgetsBinding.instance.removeObserver(this);
    widget.state.removeListener(_syncInbox);
    widget.state.inbox.clear();
    widget.state.push.onOpen = null;
    widget.state.push.onForeground = null;
    router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    scaffoldMessengerKey: messenger,
    title: 'SCHULPILOT',
    debugShowCheckedModeBanner: false,
    theme: appTheme(),
    routerConfig: router,
  );
}
