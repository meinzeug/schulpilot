import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/foundation.dart';

import 'api.dart';
import 'schulbuddy.dart';
import 'account_deletion_screen.dart';
import 'auth_screens.dart';
import 'dashboard.dart';
import 'collection_screen.dart';
import 'notebook_screen.dart';
import 'material_screen.dart';
import 'homework_screen.dart';
import 'parent_homework_screen.dart';
import 'parent_plan_screen.dart';
import 'material_actions.dart';
import 'settings_screen.dart';
import 'operator_incidents_screen.dart';
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
import 'camera_recovery.dart';
import 'family_call_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Email links carry one-time secrets in the fragment, outside HTTP logs.
  // The default path strategy drops that fragment during initial routing.
  setUrlStrategy(PathUrlStrategy(BrowserPlatformLocation(), true));
  LicenseRegistry.addLicense(() async* {
    for (final family in ['Nunito', 'SpaceGrotesk']) {
      yield LicenseEntryWithLineBreaks([
        family,
      ], await rootBundle.loadString('assets/fonts/$family-OFL.txt'));
    }
  });
  final state = AppState();
  await state.restore();
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    await recoverCameraPhotos(state);
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
  final navigator = GlobalKey<NavigatorState>();
  bool _handlingCallIntent = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.state.addListener(_syncInbox);
    widget.state.familyCalls.onNativeIntent = _handleCallIntent;
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

  Future<void> _handleCallIntent(String id, String action) async {
    if (!mounted ||
        _handlingCallIntent ||
        !(widget.state.isChild || widget.state.isParent)) {
      return;
    }
    final account = widget.state.user;
    final calls = widget.state.familyCalls;
    _handlingCallIntent = true;
    try {
      // A notification opens the global call controls, leaving the current
      // exercise and its draft mounted. It never grants capture permission.
      await calls.open(id);
      if (!mounted ||
          !identical(widget.state.user, account) ||
          calls.callId != id) {
        return;
      }
      if (action == 'decline' && calls.incoming) {
        await calls.end(decline: true);
      } else if (action == 'answer' && calls.incoming) {
        final context = navigator.currentContext;
        if (context != null && context.mounted) {
          await confirmFamilyCallJoin(context, calls);
        }
      }
    } catch (_) {
      if (mounted && identical(widget.state.user, account)) {
        messenger.currentState?.showSnackBar(
          const SnackBar(
            content: Text('Dieser Anruf ist nicht mehr verfügbar.'),
          ),
        );
      }
    } finally {
      _handlingCallIntent = false;
    }
  }

  void _syncInbox() {
    widget.state.inbox.activate(
      (widget.state.isChild || widget.state.isParent)
          ? (widget.state.user?['id'])
          : null,
    );
    widget.state.familyCalls.activate(widget.state.user);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    widget.state.inbox.foreground(state == AppLifecycleState.resumed);
    widget.state.familyCalls.lifecycle(state);
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.state.push.refreshRegistration());
    }
  }

  late final GoRouter router = GoRouter(
    navigatorKey: navigator,
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
          path == '/words' ||
          path.startsWith('/vocabulary/') ||
          path.startsWith('/language-projects/') ||
          path.startsWith('/bestellen/') ||
          path.startsWith('/admin') ||
          path == '/operator-incidents' ||
          path.startsWith('/child/') ||
          path.startsWith('/messages/') ||
          path.startsWith('/family-call/') ||
          path.startsWith('/after-school/') ||
          path.startsWith('/material/') ||
          path.startsWith('/library/') ||
          path.startsWith('/learn/') ||
          path.startsWith('/homework/') ||
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
      if (widget.state.isAdmin && (path == '/' || path == '/app')) {
        return '/admin';
      }
      if (path == '/' && widget.state.user != null) return '/app';
      if ((path.startsWith('/admin') || path == '/operator-incidents') &&
          !widget.state.isAdmin) {
        return '/app';
      }
      if (path == '/notifications' && widget.state.isAdmin) {
        return '/admin/push';
      }
      if (path.startsWith('/family-call/') && widget.state.isAdmin) {
        return '/admin';
      }
      if (path.startsWith('/grades/') && !widget.state.isParent) return '/app';
      if ((path.startsWith('/parent-plan/') ||
              path.startsWith('/parent-homework/')) &&
          !widget.state.isParent) {
        return '/app';
      }
      if ((path == '/words' ||
              path.startsWith('/messages/') ||
              path.startsWith('/vocabulary/') ||
              path.startsWith('/homework/') ||
              path.startsWith('/language-projects/')) &&
          widget.state.isAdmin) {
        return '/admin';
      }
      if (path == '/words' && widget.state.isChild) {
        return '/vocabulary/${widget.state.user!['child_id']}';
      }
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
        builder: (context, s) => InstallationScreen(
          widget.state,
          initial: false,
          initialSection: s.uri.queryParameters['section'],
        ),
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
        'resend',
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
        path: '/messages/:id',
        builder: (context, s) =>
            MessagesScreen(widget.state, childId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/child/:id',
        builder: (context, s) => ChildDetailScreen(
          widget.state,
          childId: s.pathParameters['id']!,
          section: s.uri.queryParameters['bereich'] ?? 'overview',
        ),
      ),
      GoRoute(
        path: '/after-school/:id',
        builder: (context, s) => SchoolDayScreen(
          widget.state,
          key: ValueKey(
            '${s.pathParameters['id']}:${s.uri.queryParameters['day'] ?? 'today'}:${s.uri.queryParameters['capture'] ?? ''}',
          ),
          childId: s.pathParameters['id']!,
          dayId: s.uri.queryParameters['day'],
          startWithPhotos: s.uri.queryParameters['capture'] == '1',
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
        path: '/library/:id/subject/:subjectId',
        builder: (context, s) => NotebookScreen(
          widget.state,
          key: ValueKey(
            'notebook:${widget.state.user?['id']}:${s.pathParameters['id']}:${s.pathParameters['subjectId']}',
          ),
          childId: s.pathParameters['id']!,
          subjectId: s.pathParameters['subjectId']!,
        ),
      ),
      GoRoute(
        path: '/parent-plan/:childId',
        builder: (context, s) => ParentPlanScreen(
          widget.state,
          childId: s.pathParameters['childId']!,
          initialSection: s.uri.queryParameters['ansicht'],
          initialAssignmentId: s.uri.queryParameters['auftrag'],
          initialFilters: s.uri.queryParameters,
        ),
      ),
      GoRoute(
        path: '/parent-homework/:childId',
        builder: (context, s) => ParentHomeworkScreen(
          widget.state,
          childId: s.pathParameters['childId']!,
        ),
      ),
      GoRoute(
        path: '/homework/:childId',
        builder: (context, s) => HomeworkScreen(
          widget.state,
          key: ValueKey(s.uri.path),
          childId: s.pathParameters['childId']!,
        ),
      ),
      GoRoute(
        path: '/homework/:childId/:materialId',
        builder: (context, s) => HomeworkDetailScreen(
          widget.state,
          key: ValueKey(s.uri.path),
          childId: s.pathParameters['childId']!,
          materialId: s.pathParameters['materialId']!,
        ),
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
        path: '/material/:id/processing/:jobId',
        builder: (context, s) => MaterialProcessingScreen(
          widget.state,
          key: ValueKey(
            '${widget.state.user?["id"]}:${s.pathParameters["id"]}:${s.pathParameters["jobId"]}',
          ),
          materialId: s.pathParameters['id']!,
          jobId: s.pathParameters['jobId']!,
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
          initialSubject: s.uri.queryParameters['fach'],
          initialTopic: s.uri.queryParameters['thema'],
          initialCategory: s.uri.queryParameters['ergebnis'],
          initialPeriod: s.uri.queryParameters['zeitraum'],
          initialSort: s.uri.queryParameters['sortierung'],
          initialSearch: s.uri.queryParameters['suche'],
          initialStatus: s.uri.queryParameters['status'],
          initialRoundKind: s.uri.queryParameters['rundenart'],
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
        builder: (context, s) => UnitScreen(
          widget.state,
          unitId: s.pathParameters['id']!,
          initialQuestionId: s.uri.queryParameters['frage'],
          initialOutcome: s.uri.queryParameters['ergebnis'],
        ),
      ),
      GoRoute(
        path: '/words',
        builder: (context, s) => FamilyVocabularyScreen(widget.state),
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
        builder: (context, s) => SettingsScreen(
          widget.state,
          initialSection: s.uri.queryParameters['section'],
        ),
      ),
      GoRoute(
        path: '/family-call/:id',
        builder: (context, s) => FamilyCallScreen(
          widget.state,
          key: ValueKey(
            'call:${s.pathParameters['id']}:${widget.state.user?['id']}',
          ),
          callId: s.pathParameters['id']!,
        ),
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
        path: '/operator-incidents',
        builder: (context, s) => OperatorIncidentsScreen(widget.state),
      ),
      GoRoute(
        path: '/privacy',
        builder: (context, s) => InformationScreen(
          'privacy',
          api: widget.state.api,
          section: s.uri.queryParameters['section'],
        ),
      ),
      GoRoute(
        path: '/about',
        builder: (context, s) => InformationScreen(
          'about',
          api: widget.state.api,
          section: s.uri.queryParameters['section'],
        ),
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
    widget.state.familyCalls.onNativeIntent = null;
    widget.state.familyCalls.dispose();
    widget.state.push.onOpen = null;
    widget.state.push.onForeground = null;
    router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.state,
    builder: (context, _) => MaterialApp.router(
      scaffoldMessengerKey: messenger,
      title: 'SCHULPILOT',
      debugShowCheckedModeBanner: false,
      theme: appTheme(),
      darkTheme: appTheme(brightness: Brightness.dark),
      themeMode: widget.state.darkAppearance ? ThemeMode.dark : ThemeMode.light,
      routerConfig: router,
      builder: (context, child) => ListenableBuilder(
        listenable: router.routeInformationProvider,
        builder: (context, _) => SchulbuddyHost(
          state: widget.state,
          navigatorKey: navigator,
          location: router.routeInformationProvider.value.uri.toString(),
          child: FamilyCallHost(
            widget.state,
            navigatorKey: navigator,
            currentPath: router.routeInformationProvider.value.uri.path,
            openCall: (id) => router.push('/family-call/$id'),
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      ),
    ),
  );
}
