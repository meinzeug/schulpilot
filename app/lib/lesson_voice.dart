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
  Future<void> read(String text, {required bool Function() isActive});
  Future<void> listen({
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

  bool owns(Object owner) => !_disposed && identical(_owner, owner);
  bool _active(Object owner, int generation) =>
      owns(owner) && generation == _generation;

  Future<void> read(Object owner, String text) async {
    if (_disposed || text.trim().isEmpty) return;
    final generation = ++_generation;
    _owner = owner;
    mode = LessonVoiceMode.reading;
    message = null;
    notifyListeners();
    try {
      await adapter.cancel();
      if (!_active(owner, generation)) return;
      await adapter.read(text, isActive: () => _active(owner, generation));
      if (_active(owner, generation)) _finish();
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
  }

  Future<void> listen(Object owner, ValueChanged<String> onText) async {
    if (_disposed) return;
    final generation = ++_generation;
    _owner = owner;
    mode = LessonVoiceMode.preparing;
    message = null;
    notifyListeners();
    var heard = false;
    // A hard app-side deadline complements platform-specific silence limits.
    _deadline = Timer(const Duration(seconds: 35), () {
      if (_active(owner, generation)) unawaited(stop(owner: owner));
    });
    try {
      await adapter.cancel();
      if (!_active(owner, generation)) return;
      await adapter.listen(
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
      await adapter.cancel();
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
  Future<void> read(String text, {required bool Function() isActive}) async {
    final tts = _tts ??= FlutterTts();
    if (!isActive()) return;
    final available = await tts.isLanguageAvailable('de-DE');
    if (!isActive()) return;
    if (available != true && available != 1) {
      throw const LessonVoiceFailure(
        'Eine deutsche Vorlesestimme fehlt. Prüfe die Spracheinstellungen deines Geräts.',
      );
    }
    await tts.setLanguage('de-DE');
    // Prefer a known offline German voice; do not claim that other voices are
    // offline. Engine/voice processing remains controlled by the device.
    final voices = await tts.getVoices;
    if (!isActive()) return;
    if (voices is List) {
      final local = voices
          .whereType<Map>()
          .where(
            (voice) =>
                voice['locale'].toString().replaceAll('_', '-').toLowerCase() ==
                    'de-de' &&
                ['0', 'false'].contains(voice['network_required'].toString()),
          )
          .firstOrNull;
      if (local != null && local['name'] is String) {
        await tts.setVoice({
          'name': local['name'] as String,
          'locale': local['locale'].toString(),
        });
      }
    }
    await tts.setSpeechRate(.43);
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
    var locale = 'de-DE';
    if (!kIsWeb) {
      final locales = await speech.locales();
      if (!isActive()) return;
      final german = locales
          .where(
            (value) =>
                value.localeId.replaceAll('_', '-').toLowerCase() == 'de-de',
          )
          .firstOrNull;
      if (german == null) {
        throw const LessonVoiceFailure(
          'Deutsche Spracheingabe fehlt auf diesem Gerät. Du kannst weiter tippen.',
        );
      }
      locale = german.localeId;
    }
    if (!isActive()) return;
    await speech.listen(
      onResult: (result) {
        if (isActive()) onText(result.recognizedWords);
      },
      listenOptions: stt.SpeechListenOptions(
        localeId: locale,
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
  final bool enabled, iconOnly;
  final LessonVoiceSession? voice;
  const ReadAloudButton({
    super.key,
    required this.text,
    this.enabled = true,
    this.iconOnly = false,
    this.voice,
  });
  @override
  State<ReadAloudButton> createState() => _ReadAloudButtonState();
}

class _ReadAloudButtonState extends State<ReadAloudButton>
    with WidgetsBindingObserver, _VoiceLifecycle<ReadAloudButton> {
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
    if (!widget.enabled || oldWidget.text != widget.text) {
      unawaited(voice.stop(owner: owner));
    }
  }

  @override
  void voiceChanged() {
    if (!mounted) return;
    setState(() {});
    if (identical(voice.messageOwner, owner) && voice.message != null) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(voice.message!)));
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
    final label = active ? 'Vorlesen stoppen' : 'Vorlesen';
    void pressed() {
      if (active) {
        unawaited(voice.stop(owner: owner));
      } else {
        unawaited(voice.read(owner, widget.text));
      }
    }

    return widget.iconOnly
        ? IconButton(
            tooltip: label,
            onPressed: widget.enabled && widget.text.trim().isNotEmpty
                ? pressed
                : null,
            icon: Icon(
              active ? Icons.stop_circle_outlined : Icons.volume_up_outlined,
            ),
          )
        : TextButton.icon(
            onPressed: widget.enabled && widget.text.trim().isNotEmpty
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
  final bool enabled, iconOnly;
  final int maxLength;
  final LessonVoiceSession? voice;
  const VoiceInputButton({
    super.key,
    required this.controller,
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
      oldWidget.controller.removeListener(textChanged);
      widget.controller.addListener(textChanged);
      unawaited(voice.stop(owner: owner));
    }
    if (!widget.enabled) unawaited(voice.stop(owner: owner));
  }

  @override
  void voiceChanged() {
    if (!mounted) return;
    setState(() {});
    if (identical(voice.messageOwner, owner) && voice.message != null) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(voice.message!)));
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
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mit dem Mikrofon schreiben?'),
        content: const Text(
          'Dein Gerät oder Browser kann deine Stimme an seinen Sprachdienst senden. Schulpilot speichert keine Audiodatei. Prüfe danach den Text.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Lieber tippen'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.mic_none_rounded),
            label: const Text('Sprechen'),
          ),
        ],
      ),
    );
    confirming = false;
    if (!mounted ||
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
      if (initial.length >= widget.maxLength) return;
      final limited = combined.length > widget.maxLength
          ? combined.substring(0, widget.maxLength)
          : combined;
      writing = true;
      widget.controller.value = TextEditingValue(
        text: limited,
        selection: TextSelection.collapsed(offset: limited.length),
      );
      writing = false;
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(textChanged);
    detachVoice();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = voice.owns(owner);
    final label = active ? 'Aufnahme stoppen' : 'Sprechen';
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
