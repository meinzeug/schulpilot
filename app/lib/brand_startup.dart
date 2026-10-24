import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const brandStartupBackground = Color(0xFF101E24);

/// Android's static native launch screen hands over to this finite intro.
/// The real app is only created afterwards: no hidden learning route, activity
/// timer, notification navigation or provider request runs behind the logo.
class AndroidBrandStartup extends StatefulWidget {
  final Widget Function(String? pendingPlatformLocation) application;
  const AndroidBrandStartup({super.key, required this.application});

  @override
  State<AndroidBrandStartup> createState() => _AndroidBrandStartupState();
}

class _AndroidBrandStartupState extends State<AndroidBrandStartup>
    with WidgetsBindingObserver {
  bool _finished = false;
  bool _applicationVisible = false;
  bool _foreground = true;
  String? _pendingPlatformLocation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_applicationVisible) return;
    final foreground = state == AppLifecycleState.resumed;
    if (_foreground != foreground) setState(() => _foreground = foreground);
  }

  @override
  Future<bool> didPushRouteInformation(
    RouteInformation routeInformation,
  ) async {
    if (_applicationVisible) return false;
    // An OAuth/app link arriving during the intro must reach the real router,
    // including its fragment. Never turn this navigation into a home redirect.
    _pendingPlatformLocation = routeInformation.uri.toString();
    return true;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _finish() {
    if (mounted && !_finished) setState(() => _finished = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_finished && !_foreground) {
      // Inbox, OAuth and learning observers must first mount in the foreground,
      // so they cannot miss a pause that happened during the intro.
      return const ColoredBox(color: brandStartupBackground);
    }
    if (_finished) {
      _applicationVisible = true;
      return widget.application(_pendingPlatformLocation);
    }
    return MaterialApp(
      title: 'SCHULPILOT',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        fontFamily: 'Nunito',
        scaffoldBackgroundColor: brandStartupBackground,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF37D9EA),
          brightness: Brightness.dark,
        ),
      ),
      // Builder-only MaterialApp: no temporary Navigator consumes a cold link.
      builder: (context, _) => _BrandIntro(onFinished: _finish),
    );
  }
}

class _BrandIntro extends StatefulWidget {
  final VoidCallback onFinished;
  const _BrandIntro({required this.onFinished});

  @override
  State<_BrandIntro> createState() => _BrandIntroState();
}

class _BrandIntroState extends State<_BrandIntro>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _motion =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1450),
      )..addStatusListener((status) {
        if (status == AnimationStatus.completed) widget.onFinished();
      });
  bool _started = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
    if (reduced) {
      _motion.stop();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onFinished();
      });
    } else if (!_started) {
      _started = true;
      _motion.forward();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A resume never replays an intro, nor hides an incoming call behind it.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _motion.stop();
      widget.onFinished();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: const SystemUiOverlayStyle(
      statusBarColor: brandStartupBackground,
      systemNavigationBarColor: brandStartupBackground,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
    child: Scaffold(
      key: const ValueKey('brand-startup'),
      backgroundColor: brandStartupBackground,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = math.min(
              192.0,
              math.min(constraints.maxWidth * .58, constraints.maxHeight * .42),
            );
            return Center(
              child: AnimatedBuilder(
                animation: _motion,
                builder: (context, _) {
                  final t = _motion.value;
                  final appear = Curves.easeOutCubic.transform(
                    (t / .45).clamp(0.0, 1.0),
                  );
                  final nod = math.sin(
                    ((t - .2) / .7).clamp(0.0, 1.0) * math.pi * 2,
                  );
                  final wordmark = Curves.easeOut.transform(
                    ((t - .22) / .4).clamp(0.0, 1.0),
                  );
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Transform.translate(
                          offset: Offset(0, 8 * (1 - appear)),
                          child: Transform.rotate(
                            angle: nod * .045,
                            child: Transform.scale(
                              scale: .7 + .3 * appear,
                              child: TextButton(
                                key: const ValueKey('brand-startup-skip'),
                                onPressed: widget.onFinished,
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  fixedSize: Size.square(size),
                                ),
                                child: Semantics(
                                  label: 'SCHULPILOT öffnen',
                                  excludeSemantics: true,
                                  child: Image.asset(
                                    'assets/brand/schulpilot-mark.png',
                                    width: size,
                                    height: size,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Opacity(
                          opacity: wordmark,
                          child: Transform.translate(
                            offset: Offset(0, 8 * (1 - wordmark)),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: const Text(
                                'SCHULPILOT',
                                key: ValueKey('brand-startup-wordmark'),
                                style: TextStyle(
                                  color: Colors.white,
                                  fontFamily: 'Nunito',
                                  fontSize: 30,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 2,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        ExcludeSemantics(
                          child: SizedBox(
                            width: size * .55,
                            height: 3,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                widthFactor: 1,
                                child: FractionallySizedBox(
                                  widthFactor: Curves.easeInOut.transform(t),
                                  child: const ColoredBox(
                                    color: Color(0xFF37D9EA),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    ),
  );
}
