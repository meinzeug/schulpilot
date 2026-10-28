import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// Platform failures contain a safe product message, never spoken text or audio.
class LessonVoiceFailure implements Exception {
  final String message;
  const LessonVoiceFailure(this.message);
}

/// Injectable boundary: tests exercise controls without claiming device audio.
abstract class LessonVoiceAdapter {
  Future<void> read(
    String text, {
    required bool Function() isActive,
    String locale = 'de-DE',
    bool slow = false,
  });
  Future<void> listen({
    String locale = 'de-DE',
    required bool Function() isActive,
    required VoidCallback onStarted,
    required ValueChanged<String> onText,
    required VoidCallback onDone,
    required ValueChanged<LessonVoiceFailure> onError,
  });
  Future<void> cancel();
}

enum LessonVoiceMode { idle, reading, preparing, listening }

/// One shared device session prevents playback and recording from overlapping.
/// Constructing it does not initialize a plugin, ask permission or start audio.
class LessonVoiceSession extends ChangeNotifier {
  final LessonVoiceAdapter adapter;
  LessonVoiceSession({required this.adapter});
  static final shared = LessonVoiceSession(adapter: _DeviceLessonVoice());
  Object? _owner;
  int _generation = 0;
  bool _disposed = false;
  Timer? _deadline;
  LessonVoiceMode mode = LessonVoiceMode.idle;
  String? message;
  Object? messageOwner;
  bool messageIsFailure = false;

  bool owns(Object owner) => !_disposed && identical(_owner, owner);
  bool _active(Object owner, int generation) =>
      owns(owner) && generation == _generation;

  Future<bool> read(
    Object owner,
    String text, {
    String locale = 'de-DE',
    bool slow = false,
  }) async {
    if (_disposed || text.trim().isEmpty) return false;
    final generation = ++_generation;
    _owner = owner;
    mode = LessonVoiceMode.reading;
    message = null;
    messageIsFailure = false;
    notifyListeners();
    try {
      await adapter.cancel().timeout(const Duration(seconds: 3));
      if (!_active(owner, generation)) return false;
      await adapter.read(
        text,
        locale: locale,
        slow: slow,
        isActive: () => _active(owner, generation),
      );
      if (_active(owner, generation)) {
        _finish();
        return true;
      }
    } catch (error) {
      if (_active(owner, generation)) {
        _fail(
          owner,
          error is LessonVoiceFailure
              ? error.message
              : 'Vorlesen ist auf diesem Gerät gerade nicht verfügbar.',
        );
      }
    }
    return false;
  }

  Future<void> listen(
    Object owner,
    ValueChanged<String> onText, {
    String locale = 'de-DE',
  }) async {
    if (_disposed) return;
    final generation = ++_generation;
    _owner = owner;
    mode = LessonVoiceMode.preparing;
    message = null;
    messageIsFailure = false;
    notifyListeners();
    var heard = false;
    // A hard app-side deadline complements platform-specific silence limits.
    _deadline = Timer(const Duration(seconds: 35), () {
      if (_active(owner, generation)) {
        messageOwner = owner;
        message = 'Die Aufnahme ist nach 35 Sekunden beendet. Prüfe deinen Text; du kannst weiter tippen oder erneut bewusst sprechen.';
        messageIsFailure = false;
        unawaited(stop(owner: owner));
      }
    });
    try {
      await adapter.cancel().timeout(const Duration(seconds: 3));
      if (!_active(owner, generation)) return;
      await adapter.listen(
        locale: locale,
        isActive: () => _active(owner, generation),
        onStarted: () {
          if (_active(owner, generation)) {
            mode = LessonVoiceMode.listening;
            notifyListeners();
          }
        },
        onText: (words) {
          if (_active(owner, generation) && words.trim().isNotEmpty) {
            heard = true;
            onText(words.trim());
          }
        },
        onDone: () {
          if (_active(owner, generation)) {
            if (heard) {
              messageOwner = owner;
              message = 'Prüfe den Text, bevor du ihn sendest.';
              _finish();
            } else {
              _fail(
                owner,
                'Nichts verstanden. Du kannst es erneut versuchen oder tippen.',
              );
            }
          }
        },
        onError: (error) {
          if (_active(owner, generation)) _fail(owner, error.message);
        },
      );
    } catch (error) {
      if (_active(owner, generation)) {
        _fail(
          owner,
          error is LessonVoiceFailure ? error.message : 'Spracheingabe ist hier gerade nicht verfügbar. Du kannst weiter tippen.',
        );
      }
    }
  }

  void _finish() {
    _deadline?.cancel();
    _owner = null;
    _generation++;
    mode = LessonVoiceMode.idle;
    notifyListeners();
  }

  void _fail(Object owner, String text) {
    messageOwner = owner;
    message = text;
    messageIsFailure = true;
    _finish();
    unawaited(adapter.cancel().catchError((Object _) {}));
  }

  Future<void> stop({Object? owner}) async {
    if (_disposed || (owner != null && !owns(owner))) return;
    final active = _owner != null;
    _deadline?.cancel();
    _generation++;
    _owner = null;
    mode = LessonVoiceMode.idle;
    if (active) notifyListeners();
    try {
      await adapter.cancel().timeout(const Duration(seconds: 3));
    } catch (_) {
      // Stopping never logs provider callbacks, audio or recognized words.
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _deadline?.cancel();
    _owner = null;
    _generation++;
    _disposed = true;
    unawaited(adapter.cancel().catchError((Object _) {}));
    super.dispose();
  }
}

class _DeviceLessonVoice implements LessonVoiceAdapter {
  FlutterTts? _tts;
  stt.SpeechToText? _speech;
  bool _speechReady = false;
  VoidCallback? _listeningDone, _listeningStarted;
  ValueChanged<LessonVoiceFailure>? _listeningError;
  Completer<void>? _readingCancelled;

  @override
  Future<void> read(
    String text, {
    required bool Function() isActive,
    String locale = 'de-DE',
    bool slow = false,
  }) async {
    final tts = _tts ??= FlutterTts();
    if (!isActive()) return;
    final available = await tts.isLanguageAvailable(locale);
    if (!isActive()) return;
    if (available != true && available != 1) {
      throw LessonVoiceFailure(
        'Eine Vorlesestimme für $locale fehlt. Prüfe die Spracheinstellungen deines Geräts.',
      );
    }
    final selected = await tts.setLanguage(locale);
    if (selected == 0 || selected == false) {
      throw LessonVoiceFailure(
        'Die Vorlesestimme für $locale konnte nicht gewählt werden.',
      );
    }
    // Never silently substitute a different language/variant. Device voices
    // may use a network service; we do not claim offline processing.
    final voices = await tts.getVoices;
    if (!isActive()) return;
    if (voices is List) {
      final matches = voices
          .whereType<Map>()
          .where(
            (voice) =>
                voice['locale'].toString().replaceAll('_', '-').toLowerCase() ==
                locale.toLowerCase(),
          )
          .toList();
      final local =
          matches
              .where(
                (voice) => [
                  '0',
                  'false',
                ].contains(voice['network_required'].toString()),
              )
              .firstOrNull ??
          matches.firstOrNull;
      if (local != null && local['name'] is String) {
        await tts.setVoice({
          'name': local['name'] as String,
          'locale': local['locale'].toString(),
        });
      } else {
        throw LessonVoiceFailure(
          'Eine passende Vorlesestimme für $locale fehlt. Du kannst weiter lesen und tippen.',
        );
      }
    } else {
      throw LessonVoiceFailure(
        'Die Vorlesestimme für $locale konnte nicht geprüft werden.',
      );
    }
    await tts.setSpeechRate(slow ? .28 : .43);
    await tts.awaitSpeakCompletion(true);
    final cancelled = Completer<void>();
    _readingCancelled = cancelled;
    for (final chunk in _readingChunks(text)) {
      if (!isActive()) return;
      final failed = Completer<void>();
      tts.setErrorHandler((_) {
        if (!failed.isCompleted) {
          failed.completeError(
            const LessonVoiceFailure(
              'Die Vorlesestimme ist gerade nicht verfügbar.',
            ),
          );
        }
      });
      final result = tts.speak(chunk, focus: true);
      await Future.any<void>([
        result.then((value) {
          if (value == 0 || value == false) {
            throw const LessonVoiceFailure(
              'Die Vorlesestimme konnte nicht starten.',
            );
          }
        }),
        failed.future,
        cancelled.future,
      ]).timeout(const Duration(minutes: 3));
    }
  }

  @override
  Future<void> listen({
    String locale = 'de-DE',
    required bool Function() isActive,
    required VoidCallback onStarted,
    required ValueChanged<String> onText,
    required VoidCallback onDone,
    required ValueChanged<LessonVoiceFailure> onError,
  }) async {
    final speech = _speech ??= stt.SpeechToText();
    _listeningDone = onDone;
    _listeningStarted = onStarted;
    _listeningError = onError;
    if (!_speechReady) {
      _speechReady = await speech.initialize(
        debugLogging: false,
        options: [stt.SpeechToText.androidNoBluetooth],
        onStatus: (status) {
          if (status == 'listening') _listeningStarted?.call();
          if (status == 'done') _listeningDone?.call();
        },
        onError: (error) => _listeningError?.call(
          LessonVoiceFailure(
            error.errorMsg.contains('permission')
                ? 'Das Mikrofon ist nicht freigegeben. Du kannst weiter tippen.'
                : 'Die Spracheingabe wurde beendet. Prüfe den Text oder tippe weiter.',
          ),
        ),
      );
    }
    if (!isActive()) return;
    if (!_speechReady) {
      throw const LessonVoiceFailure(
        'Mikrofon oder Spracheingabe ist hier nicht verfügbar. Du kannst weiter tippen.',
      );
    }
    var deviceLocale = locale;
    if (!kIsWeb) {
      final locales = await speech.locales();
      if (!isActive()) return;
      final german = locales
          .where(
            (value) =>
                value.localeId.replaceAll('_', '-').toLowerCase() ==
                locale.toLowerCase(),
          )
          .firstOrNull;
      if (german == null) {
        throw LessonVoiceFailure(
          'Spracheingabe für $locale fehlt auf diesem Gerät. Du kannst weiter tippen.',
        );
      }
      deviceLocale = german.localeId;
    }
    if (!isActive()) return;
    await speech.listen(
      onResult: (result) {
        if (isActive()) onText(result.recognizedWords);
      },
      listenOptions: stt.SpeechListenOptions(
        localeId: deviceLocale,
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 4),
        partialResults: true,
        cancelOnError: true,
        listenMode: stt.ListenMode.dictation,
      ),
    );
  }

  @override
  Future<void> cancel() async {
    _listeningDone = _listeningStarted = null;
    _listeningError = null;
    final cancelled = _readingCancelled;
    if (cancelled != null && !cancelled.isCompleted) cancelled.complete();
    await Future.wait([
      if (_tts != null) _tts!.stop().then<void>((_) {}),
      if (_speechReady) _speech!.cancel(),
    ]);
  }
}

Iterable<String> _readingChunks(String text) sync* {
  var remaining = text.trim();
  while (remaining.length > 1800) {
    var end = remaining.lastIndexOf(RegExp(r'[.!?]\s|\n'), 1800);
    if (end < 900) end = remaining.lastIndexOf(' ', 1800);
    if (end < 1) end = 1800;
    if (remaining.codeUnitAt(end - 1) >= 0xD800 &&
        remaining.codeUnitAt(end - 1) <= 0xDBFF) {
      end--;
    }
    yield remaining.substring(0, end).trim();
    remaining = remaining.substring(end).trim();
  }
  if (remaining.isNotEmpty) yield remaining;
}

mixin _VoiceLifecycle<T extends StatefulWidget>
    on State<T>, WidgetsBindingObserver {
  final Object owner = Object();
  LessonVoiceSession get voice;
  void voiceChanged();

  void attachVoice() {
    WidgetsBinding.instance.addObserver(this);
    voice.addListener(voiceChanged);
  }

  void detachVoice() {
    WidgetsBinding.instance.removeObserver(this);
    voice.removeListener(voiceChanged);
    unawaited(voice.stop(owner: owner));
  }

  void checkRoute() {
    if (ModalRoute.of(context)?.isCurrent == false) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && ModalRoute.of(context)?.isCurrent == false) {
          unawaited(voice.stop(owner: owner));
        }
      });
    }
  }

  void presentVoiceMessage(String text, {bool failure = false}) {
    // The page's SnackBar sits behind a dialog/bottom sheet. Keep actual
    // failures accessible above the currently open explanation or input.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || ModalRoute.of(context)?.isCurrent == false) return;
      if (failure && ModalRoute.of(context) is PopupRoute) {
        unawaited(
          showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Sprachfunktion nicht verfügbar'),
              content: Text(text),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Weiter lesen und tippen'),
                ),
              ],
            ),
          ),
        );
      } else {
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(SnackBar(content: Text(text)));
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A permission dialog may briefly make the app inactive while no recording
    // has started. Actual backgrounding always cancels even a pending request.
    if (state != AppLifecycleState.resumed &&
        !(state == AppLifecycleState.inactive &&
            voice.mode == LessonVoiceMode.preparing)) {
      unawaited(voice.stop(owner: owner));
    }
  }
}

class ReadAloudButton extends StatefulWidget {
  final String text;
  final String locale;
  final bool slow;
  final Future<void> Function()? beforeRead;
  final Future<void> Function()? onReadCompleted;
  final bool enabled, iconOnly;
  final LessonVoiceSession? voice;
  const ReadAloudButton({
    super.key,
    required this.text,
    this.locale = 'de-DE',
    this.slow = false,
    this.beforeRead,
    this.onReadCompleted,
    this.enabled = true,
    this.iconOnly = false,
    this.voice,
  });
  @override
  State<ReadAloudButton> createState() => _ReadAloudButtonState();
}

class _ReadAloudButtonState extends State<ReadAloudButton>
    with WidgetsBindingObserver, _VoiceLifecycle<ReadAloudButton> {
  bool preparing = false;
  int preparation = 0;
  @override
  LessonVoiceSession get voice => widget.voice ?? LessonVoiceSession.shared;
  @override
  void initState() {
    super.initState();
    attachVoice();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    checkRoute();
  }

  @override
  void didUpdateWidget(covariant ReadAloudButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.voice != widget.voice) {
      (oldWidget.voice ?? LessonVoiceSession.shared).removeListener(
        voiceChanged,
      );
      unawaited(
        (oldWidget.voice ?? LessonVoiceSession.shared).stop(owner: owner),
      );
      voice.addListener(voiceChanged);
    }
    if (!widget.enabled ||
        oldWidget.text != widget.text ||
        oldWidget.locale != widget.locale ||
        oldWidget.slow != widget.slow) {
      preparation++;
      preparing = false;
      unawaited(voice.stop(owner: owner));
    }
  }

  @override
  void voiceChanged() {
    if (!mounted) return;
    setState(() {});
    if (identical(voice.messageOwner, owner) && voice.message != null) {
      presentVoiceMessage(voice.message!, failure: voice.messageIsFailure);
      voice.message = null;
    }
  }

  @override
  void dispose() {
    detachVoice();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = voice.owns(owner);
    final label = active
        ? 'Vorlesen stoppen'
        : preparing
        ? 'Vorlesen wird vorbereitet …'
        : widget.slow
        ? 'Langsam vorlesen'
        : 'Vorlesen';
    Future<void> pressed() async {
      if (active) {
        unawaited(voice.stop(owner: owner));
      } else {
        if (preparing || !mounted || !widget.enabled) return;
        final ticket = ++preparation;
        setState(() => preparing = true);
        try {
          await widget.beforeRead?.call();
          if (!mounted || ticket != preparation) return;
          setState(() => preparing = false);
          if (!widget.enabled ||
              ModalRoute.of(this.context)?.isCurrent == false) {
            return;
          }
          final completed = await voice.read(
            owner,
            widget.text,
            locale: widget.locale,
            slow: widget.slow,
          );
          if (completed && mounted) await widget.onReadCompleted?.call();
        } catch (_) {
          if (mounted && ticket == preparation) {
            presentVoiceMessage(
              'Die Sprachhilfe konnte nicht gespeichert werden. Bitte erneut versuchen.',
              failure: true,
            );
          }
        } finally {
          if (mounted && ticket == preparation) {
            setState(() => preparing = false);
          }
        }
      }
    }

    return widget.iconOnly
        ? IconButton(
            tooltip: label,
            onPressed:
                widget.enabled && !preparing && widget.text.trim().isNotEmpty
                ? pressed
                : null,
            icon: Icon(
              active ? Icons.stop_circle_outlined : Icons.volume_up_outlined,
            ),
          )
        : TextButton.icon(
            onPressed:
                widget.enabled && !preparing && widget.text.trim().isNotEmpty
                ? pressed
                : null,
            icon: Icon(
              active ? Icons.stop_circle_outlined : Icons.volume_up_outlined,
            ),
            label: Text(label),
          );
  }
}

class VoiceInputButton extends StatefulWidget {
  final TextEditingController controller;
  final String locale;
  final VoidCallback? onRecognized;
  final bool enabled, iconOnly;
  final int maxLength;
  final LessonVoiceSession? voice;
  const VoiceInputButton({
    super.key,
    required this.controller,
    this.locale = 'de-DE',
    this.onRecognized,
    this.enabled = true,
    this.iconOnly = false,
    this.maxLength = 500,
    this.voice,
  }) : assert(maxLength > 0);
  @override
  State<VoiceInputButton> createState() => _VoiceInputButtonState();
}

class _VoiceInputButtonState extends State<VoiceInputButton>
    with WidgetsBindingObserver, _VoiceLifecycle<VoiceInputButton> {
  bool writing = false, confirming = false;
  DialogRoute<bool>? consentRoute;
  int consentGeneration = 0;
  void dismissConsent() {
    consentGeneration++;
    final route = consentRoute;
    consentRoute = null;
    confirming = false;
    if (route != null) {
      Future<void>.microtask(() {
        if (route.isActive) route.navigator?.removeRoute(route);
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    super.didChangeAppLifecycleState(lifecycle);
    if (lifecycle == AppLifecycleState.hidden ||
        lifecycle == AppLifecycleState.paused ||
        lifecycle == AppLifecycleState.detached) {
      dismissConsent();
    }
  }

  @override
  LessonVoiceSession get voice => widget.voice ?? LessonVoiceSession.shared;
  @override
  void initState() {
    super.initState();
    attachVoice();
    widget.controller.addListener(textChanged);
  }

  void textChanged() {
    if (!writing && voice.owns(owner)) unawaited(voice.stop(owner: owner));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    checkRoute();
  }

  @override
  void didUpdateWidget(covariant VoiceInputButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.voice != widget.voice) {
      (oldWidget.voice ?? LessonVoiceSession.shared).removeListener(
        voiceChanged,
      );
      unawaited(
        (oldWidget.voice ?? LessonVoiceSession.shared).stop(owner: owner),
      );
      voice.addListener(voiceChanged);
    }
    if (oldWidget.controller != widget.controller) {
      dismissConsent();
      oldWidget.controller.removeListener(textChanged);
      widget.controller.addListener(textChanged);
      unawaited(voice.stop(owner: owner));
    }
    if (!widget.enabled || oldWidget.locale != widget.locale) {
      dismissConsent();
      unawaited(voice.stop(owner: owner));
    }
  }

  @override
  void voiceChanged() {
    if (!mounted) return;
    setState(() {});
    if (identical(voice.messageOwner, owner) && voice.message != null) {
      presentVoiceMessage(voice.message!, failure: voice.messageIsFailure);
      voice.message = null;
    }
  }

  Future<void> pressed() async {
    if (voice.owns(owner)) {
      await voice.stop(owner: owner);
      return;
    }
    if (confirming) return;
    confirming = true;
    final ticket = ++consentGeneration;
    late final DialogRoute<bool> route;
    void finish(bool result) {
      if (mounted &&
          widget.enabled &&
          ticket == consentGeneration &&
          route.isCurrent) {
        route.navigator?.pop(result);
      }
    }

    route = DialogRoute<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mit dem Mikrofon schreiben?'),
        content: const Text(
          'Dein Gerät oder Browser kann deine Stimme an seinen Sprachdienst senden. SchuleSchlau speichert keine Audiodatei. Prüfe danach den Text.',
        ),
        actions: [
          TextButton(
            onPressed: () => finish(false),
            child: const Text('Lieber tippen'),
          ),
          FilledButton.icon(
            onPressed: () => finish(true),
            icon: const Icon(Icons.mic_none_rounded),
            label: const Text('Sprechen'),
          ),
        ],
      ),
    );
    consentRoute = route;
    final accepted = await Navigator.of(
      context,
      rootNavigator: true,
    ).push(route);
    if (identical(consentRoute, route)) consentRoute = null;
    if (ticket == consentGeneration) confirming = false;
    if (!mounted ||
        ticket != consentGeneration ||
        accepted != true ||
        !widget.enabled ||
        ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    final initial = widget.controller.text;
    await voice.listen(owner, (words) {
      if (!mounted) return;
      final combined =
          '${initial.isEmpty || initial.endsWith(' ') ? initial : '$initial '}$words';
      if (initial.characters.length >= widget.maxLength) return;
      final limited = combined.characters.take(widget.maxLength).toString();
      widget.onRecognized?.call();
      writing = true;
      widget.controller.value = TextEditingValue(
        text: limited,
        selection: TextSelection.collapsed(offset: limited.length),
      );
      writing = false;
    }, locale: widget.locale);
  }

  @override
  void dispose() {
    dismissConsent();
    widget.controller.removeListener(textChanged);
    detachVoice();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = voice.owns(owner);
    final label = active
        ? voice.mode == LessonVoiceMode.preparing
              ? 'Mikrofon wird vorbereitet · Stoppen'
              : 'Aufnahme stoppen'
        : 'Sprechen';
    return widget.iconOnly
        ? IconButton(
            tooltip: label,
            onPressed: widget.enabled ? pressed : null,
            icon: Icon(
              active ? Icons.stop_circle_outlined : Icons.mic_none_rounded,
            ),
          )
        : TextButton.icon(
            onPressed: widget.enabled ? pressed : null,
            icon: Icon(
              active ? Icons.stop_circle_outlined : Icons.mic_none_rounded,
            ),
            label: Text(label),
          );
  }
}
