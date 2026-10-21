import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:schulpilot/family_call_media.dart';

class TestTrack extends MediaStreamTrack {
  @override
  final String id;
  @override
  final String kind;
  @override
  String get label => 'Artificial $kind';
  @override
  bool enabled = true;
  bool stopped = false;
  TestTrack(this.id, this.kind);
  @override
  bool get muted => false;
  @override
  Future<void> stop() async {
    stopped = true;
  }

  @override
  Future<void> dispose() async {}
}

class TestStream extends MediaStream {
  final List<MediaStreamTrack> tracks;
  TestStream(super.id, super.ownerTag, this.tracks);
  @override
  bool get active => true;
  @override
  List<MediaStreamTrack> getTracks() => tracks;
  @override
  List<MediaStreamTrack> getVideoTracks() =>
      tracks.where((track) => track.kind == 'video').toList();
  @override
  List<MediaStreamTrack> getAudioTracks() =>
      tracks.where((track) => track.kind == 'audio').toList();
  @override
  Future<void> getMediaTracks() async {}
  @override
  Future<void> addTrack(
    MediaStreamTrack track, {
    bool addToNative = true,
  }) async {
    tracks.add(track);
  }

  @override
  Future<void> removeTrack(
    MediaStreamTrack track, {
    bool removeFromNative = true,
  }) async {
    tracks.remove(track);
  }

  @override
  Future<void> dispose() async {}
}

/// Models the documented platform difference: native renderer.muted changes a
/// microphone track and rejects remote streams; the web setter only mutes output.
class TestRenderer extends RTCVideoRenderer {
  final bool native;
  TestRenderer({required this.native});
  MediaStream? stream;
  final mutedCalls = <bool>[];
  final trackBindings = <String?>[];
  @override
  Future<void> initialize() async {}
  @override
  MediaStream? get srcObject => stream;
  @override
  set srcObject(MediaStream? value) {
    stream = value;
  }

  @override
  set muted(bool value) {
    mutedCalls.add(value);
    if (native) {
      if (stream?.ownerTag != 'local') {
        throw StateError('Native remote muting is forbidden.');
      }
      stream!.getAudioTracks().first.enabled = !value;
    }
  }

  @override
  Future<void> setSrcObject({MediaStream? stream, String? trackId}) async {
    this.stream = stream;
    trackBindings.add(trackId);
  }

  @override
  Future<void> dispose() async {
    await super.dispose();
  }
}

class TestSender extends Fake implements RTCRtpSender {}

class TestPeer extends RTCPeerConnection {
  @override
  Future<RTCRtpSender> addTrack(
    MediaStreamTrack track, [
    MediaStream? stream,
  ]) async => TestSender();
  @override
  Future<void> setRemoteDescription(RTCSessionDescription description) async {}
  @override
  Future<void> setLocalDescription(RTCSessionDescription description) async {}
  @override
  Future<RTCSessionDescription> createAnswer([
    Map<String, dynamic>? constraints,
  ]) async => RTCSessionDescription('artificial answer', 'answer');
  @override
  Future<void> close() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final web in [false, true]) {
    testWidgets(
      '${web ? 'Web' : 'Native'} preview keeps capture audio enabled',
      (tester) async {
        final microphone = TestTrack('artificial-mic', 'audio');
        final camera = TestTrack('artificial-camera', 'video');
        final local = TestStream('local-camera', 'local', [microphone, camera]);
        final renderers = List.generate(3, (_) => TestRenderer(native: !web));
        var index = 0;
        final unmutes = <MediaStreamTrack>[];
        final media = WebRtcFamilyCallMedia(
          webPlatform: web,
          unmuteMicrophone: (track) async {
            unmutes.add(track);
          },
          rendererFactory: () => renderers[index++],
          captureUserMedia: (_) async => local,
        );
        await media.prepare(camera: true);
        expect(
          microphone.enabled,
          isTrue,
          reason: 'Preview output must never silently mute the microphone.',
        );
        expect(media.microphoneEnabled, isTrue);
        expect(unmutes, isEmpty);
        expect(renderers.first.mutedCalls, web ? [true] : isEmpty);
        await media.toggleMicrophone();
        expect(microphone.enabled, isFalse);
        expect(
          unmutes,
          isEmpty,
          reason: 'Microphone off must never globally mute the device.',
        );
        await media.toggleMicrophone();
        expect(microphone.enabled, isTrue);
        expect(unmutes, web ? isEmpty : [microphone]);
        await media.close();
        expect(
          unmutes,
          web ? isEmpty : [microphone],
          reason: 'Closing never changes device mute.',
        );
      },
    );

    testWidgets(
      '${web ? 'Web' : 'Native'} camera and screen bind explicit tracks; arrival is no frame proof',
      (tester) async {
        final local = TestStream('local-camera', 'local', [
          TestTrack('local-mic', 'audio'),
          TestTrack('local-video', 'video'),
        ]);
        final renderers = List.generate(3, (_) => TestRenderer(native: !web));
        final peer = TestPeer();
        var index = 0;
        final media = WebRtcFamilyCallMedia(
          webPlatform: web,
          rendererFactory: () => renderers[index++],
          captureUserMedia: (_) async => local,
          peerFactory: (_) async => peer,
        );
        await media.prepare(camera: true);
        await media.connect([]);
        await media.answer({
          'sdp': 'artificial offer',
          'camera_stream_id': 'child-camera',
          'screen_stream_id': 'child-screen',
        });
        final camera = TestTrack('camera-track', 'video');
        final microphone = TestTrack('microphone-track', 'audio');
        final screen = TestTrack('screen-track', 'video');
        final cameraStream = TestStream('child-camera', 'remote-peer', [
          camera,
          microphone,
        ]);
        final screenStream = TestStream('child-screen', 'remote-peer', [
          screen,
        ]);
        peer.onTrack!(RTCTrackEvent(streams: [cameraStream], track: camera));
        peer.onTrack!(RTCTrackEvent(streams: [screenStream], track: screen));
        // Unified Plan can deliver a later audio event for the same stream. It
        // must retain the camera track instead of clearing/selecting another one.
        peer.onTrack!(
          RTCTrackEvent(streams: [cameraStream], track: microphone),
        );
        await tester.pump();
        expect(renderers[1].trackBindings, ['camera-track', 'camera-track']);
        expect(renderers[2].trackBindings, ['screen-track']);
        expect(renderers[2].mutedCalls, isEmpty);
        expect(media.hasRemoteCamera, isTrue);
        expect(media.hasRemoteScreen, isTrue);
        expect(media.remoteCameraFrameSeen, isFalse);
        expect(media.remoteScreenFrameSeen, isFalse);
        renderers[1].onFirstFrameRendered!();
        expect(media.remoteCameraFrameSeen, isTrue);
        expect(media.remoteScreenFrameSeen, isFalse);
        renderers[2].onFirstFrameRendered!();
        expect(media.remoteScreenFrameSeen, isTrue);
        expect(tester.takeException(), isNull);
        await media.close();
      },
    );
  }
}
