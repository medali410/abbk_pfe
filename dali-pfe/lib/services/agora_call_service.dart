import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart';

class AgoraCallService {
  static final AgoraCallService _instance = AgoraCallService._internal();
  factory AgoraCallService() => _instance;
  AgoraCallService._internal();

  RtcEngine? _engine;
  String? _appId;
  String? _channelName;
  String? _token;
  int? _uid;
  bool _isJoined = false;
  bool _isMuted = false;
  bool _isCameraOff = false;

  // Replace with your Agora App ID
  static const String _defaultAppId = 'a302d418482b4069a7143729121902fb';

  bool get isJoined => _isJoined;
  bool get isMuted => _isMuted;
  bool get isCameraOff => _isCameraOff;

  Future<void> initialize({String? appId}) async {
    _appId = appId ?? _defaultAppId;

    if (_appId == 'YOUR_AGORA_APP_ID') {
      debugPrint('WARNING: Please set your Agora App ID in AgoraCallService');
    }

    _engine = createAgoraRtcEngine();
    await _engine!.initialize(RtcEngineContext(
      appId: _appId,
      channelProfile: ChannelProfileType.channelProfileCommunication,
    ));

    _engine!.registerEventHandler(
      RtcEngineEventHandler(
        onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
          debugPrint('Agora: onJoinChannelSuccess');
          _isJoined = true;
        },
        onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
          debugPrint('Agora: onUserJoined $remoteUid');
        },
        onUserOffline: (RtcConnection connection, int remoteUid, UserOfflineReasonType reason) {
          debugPrint('Agora: onUserOffline $remoteUid');
        },
        onLeaveChannel: (RtcConnection connection, RtcStats stats) {
          debugPrint('Agora: onLeaveChannel');
          _isJoined = false;
        },
      ),
    );
  }

  Future<void> joinChannel({
    required String channelName,
    required String token,
    required int uid,
    bool isVideo = true,
  }) async {
    if (_engine == null) {
      await initialize();
    }

    _channelName = channelName;
    _token = token;
    _uid = uid;

    await _engine!.enableVideo();
    await _engine!.startPreview();

    await _engine!.joinChannel(
      token: token,
      channelId: channelName,
      uid: uid,
      options: const ChannelMediaOptions(
        channelProfile: ChannelProfileType.channelProfileCommunication,
        clientRoleType: ClientRoleType.clientRoleBroadcaster,
      ),
    );
  }

  Future<void> leaveChannel() async {
    if (_engine != null && _isJoined) {
      await _engine!.leaveChannel();
      await _engine!.stopPreview();
      await _engine!.disableVideo();
    }
    _isJoined = false;
    _channelName = null;
    _token = null;
    _uid = null;
  }

  Future<void> toggleMute() async {
    if (_engine == null) return;
    _isMuted = !_isMuted;
    await _engine!.muteLocalAudioStream(_isMuted);
  }

  Future<void> toggleCamera() async {
    if (_engine == null) return;
    _isCameraOff = !_isCameraOff;
    await _engine!.muteLocalVideoStream(_isCameraOff);
  }

  Future<void> switchCamera() async {
    if (_engine == null) return;
    await _engine!.switchCamera();
  }

  Future<void> dispose() async {
    await leaveChannel();
    if (_engine != null) {
      await _engine!.release();
      _engine = null;
    }
  }

  RtcEngine? get engine => _engine;
}
