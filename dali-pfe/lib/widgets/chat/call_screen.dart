import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'dart:async';

class CallScreen extends StatefulWidget {
  final io.Socket socket;
  final String roomId;
  final String callType; // 'voice' or 'video'
  final String callerName;
  final String myName;
  final bool isIncoming;
  final VoidCallback onCallEnded;

  const CallScreen({
    super.key,
    required this.socket,
    required this.roomId,
    required this.callType,
    required this.callerName,
    required this.myName,
    required this.isIncoming,
    required this.onCallEnded,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> with TickerProviderStateMixin {
  RTCPeerConnection? _peerConnection;
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  MediaStream? _localStream;
  bool _isConnected = false;
  bool _isMuted = false;
  bool _isCameraOff = false;
  bool _isSpeakerOn = true;
  bool _isCallAccepted = false;
  Timer? _callTimer;
  int _callDurationSeconds = 0;
  late AnimationController _pulseController;

  static const Map<String, dynamic> _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ]
  };

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _initRenderers();
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    _setupSocketListeners();

    if (widget.isIncoming) {
      // Wait for user to accept
    } else {
      await _startCall();
    }
  }

  void _setupSocketListeners() {
    widget.socket.on('call_accepted', (data) async {
      if ((data['roomId'] ?? '').toString() == widget.roomId) {
        if (mounted) setState(() => _isCallAccepted = true);
        await _createOffer();
        _startCallTimer();
      }
    });

    widget.socket.on('call_rejected', (data) {
      if ((data['roomId'] ?? '').toString() == widget.roomId) {
        _endCall();
      }
    });

    widget.socket.on('call_ended', (data) {
      if ((data['roomId'] ?? '').toString() == widget.roomId) {
        _endCall();
      }
    });

    widget.socket.on('webrtc_offer', (data) async {
      if ((data['roomId'] ?? '').toString() == widget.roomId && data['sdp'] != null) {
        final sdp = RTCSessionDescription(data['sdp']['sdp'], data['sdp']['type']);
        await _peerConnection?.setRemoteDescription(sdp);
        final answer = await _peerConnection?.createAnswer();
        if (answer != null) {
          await _peerConnection?.setLocalDescription(answer);
          widget.socket.emit('webrtc_answer', {
            'roomId': widget.roomId,
            'sdp': {'sdp': answer.sdp, 'type': answer.type},
          });
        }
      }
    });

    widget.socket.on('webrtc_answer', (data) async {
      if ((data['roomId'] ?? '').toString() == widget.roomId && data['sdp'] != null) {
        final sdp = RTCSessionDescription(data['sdp']['sdp'], data['sdp']['type']);
        await _peerConnection?.setRemoteDescription(sdp);
      }
    });

    widget.socket.on('webrtc_ice_candidate', (data) async {
      if ((data['roomId'] ?? '').toString() == widget.roomId && data['candidate'] != null) {
        final candidate = RTCIceCandidate(
          data['candidate']['candidate'],
          data['candidate']['sdpMid'],
          data['candidate']['sdpMLineIndex'],
        );
        await _peerConnection?.addCandidate(candidate);
      }
    });
  }

  Future<void> _startCall() async {
    await _createPeerConnection();
    await _getUserMedia();

    widget.socket.emit('call_initiate', {
      'roomId': widget.roomId,
      'callerId': widget.myName,
      'callerName': widget.myName,
      'callType': widget.callType,
    });
  }

  Future<void> _acceptCall() async {
    await _createPeerConnection();
    await _getUserMedia();

    if (mounted) setState(() => _isCallAccepted = true);

    widget.socket.emit('call_accept', {
      'roomId': widget.roomId,
      'acceptorName': widget.myName,
    });
    _startCallTimer();
  }

  void _rejectCall() {
    widget.socket.emit('call_reject', {
      'roomId': widget.roomId,
    });
    _endCall();
  }

  Future<void> _createPeerConnection() async {
    _peerConnection = await createPeerConnection(_iceServers);

    _peerConnection!.onIceCandidate = (candidate) {
      widget.socket.emit('webrtc_ice_candidate', {
        'roomId': widget.roomId,
        'candidate': {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        },
      });
    };

    _peerConnection!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        _remoteRenderer.srcObject = event.streams[0];
        if (mounted) setState(() => _isConnected = true);
      }
    };

    _peerConnection!.onConnectionState = (state) {
      debugPrint('WebRTC connection state: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _endCall();
      }
    };
  }

  Future<void> _getUserMedia() async {
    final isVideo = widget.callType == 'video';
    final constraints = <String, dynamic>{
      'audio': true,
      'video': isVideo ? {'facingMode': 'user'} : false,
    };

    _localStream = await navigator.mediaDevices.getUserMedia(constraints);
    _localRenderer.srcObject = _localStream;

    _localStream!.getTracks().forEach((track) {
      _peerConnection?.addTrack(track, _localStream!);
    });

    if (mounted) setState(() {});
  }

  Future<void> _createOffer() async {
    final offer = await _peerConnection?.createOffer();
    if (offer != null) {
      await _peerConnection?.setLocalDescription(offer);
      widget.socket.emit('webrtc_offer', {
        'roomId': widget.roomId,
        'sdp': {'sdp': offer.sdp, 'type': offer.type},
      });
    }
  }

  void _startCallTimer() {
    _callTimer?.cancel();
    _callDurationSeconds = 0;
    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _callDurationSeconds++);
    });
  }

  String get _formattedDuration {
    final m = (_callDurationSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (_callDurationSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _toggleMute() {
    _localStream?.getAudioTracks().forEach((track) {
      track.enabled = _isMuted;
    });
    if (mounted) setState(() => _isMuted = !_isMuted);
  }

  void _toggleCamera() {
    _localStream?.getVideoTracks().forEach((track) {
      track.enabled = _isCameraOff;
    });
    if (mounted) setState(() => _isCameraOff = !_isCameraOff);
  }

  void _toggleSpeaker() {
    if (mounted) setState(() => _isSpeakerOn = !_isSpeakerOn);
    // Platform-specific speaker implementation
  }

  void _endCall() {
    widget.socket.emit('call_end', {'roomId': widget.roomId});
    _cleanup();
    widget.onCallEnded();
  }

  void _hangUp() {
    _endCall();
  }

  void _cleanup() {
    _callTimer?.cancel();
    _localStream?.getTracks().forEach((track) => track.stop());
    _localStream?.dispose();
    _peerConnection?.close();
    _peerConnection?.dispose();

    // Remove socket listeners for call
    widget.socket.off('call_accepted');
    widget.socket.off('call_rejected');
    widget.socket.off('call_ended');
    widget.socket.off('webrtc_offer');
    widget.socket.off('webrtc_answer');
    widget.socket.off('webrtc_ice_candidate');
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _callTimer?.cancel();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    _localStream?.getTracks().forEach((track) => track.stop());
    _localStream?.dispose();
    _peerConnection?.close();
    _peerConnection?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = widget.callType == 'video';

    return Scaffold(
      backgroundColor: const Color(0xFF080D14),
      body: Stack(
        children: [
          // Background gradient
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF0D1526), Color(0xFF080D14), Color(0xFF0A0F1C)],
              ),
            ),
          ),

          // Animated background circles
          ...List.generate(3, (i) => Positioned(
            top: 100.0 + i * 150,
            left: MediaQuery.of(context).size.width * 0.5 - 100 + (i * 30.0 - 30),
            child: AnimatedBuilder(
              animation: _pulseController,
              builder: (_, __) => Container(
                width: 200 + _pulseController.value * 40,
                height: 200 + _pulseController.value * 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF3B82F6).withOpacity(0.03 - i * 0.008),
                ),
              ),
            ),
          )),

          // Remote video (full screen)
          if (isVideo && _isConnected)
            Positioned.fill(
              child: RTCVideoView(
                _remoteRenderer,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              ),
            ),

          // Content overlay
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 40),

                // Call info header
                Text(
                  widget.isIncoming && !_isCallAccepted
                      ? 'Appel entrant...'
                      : _isConnected ? 'En cours' : 'Appel en cours...',
                  style: GoogleFonts.inter(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),

                Text(
                  widget.callerName,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                if (_isCallAccepted || _isConnected) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF22C55E).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8, height: 8,
                          decoration: const BoxDecoration(color: Color(0xFF22C55E), shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formattedDuration,
                          style: GoogleFonts.spaceMono(
                            color: const Color(0xFF22C55E),
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const Spacer(),

                // Avatar (shown during voice call or when video is not connected)
                if (!isVideo || !_isConnected)
                  AnimatedBuilder(
                    animation: _pulseController,
                    builder: (_, __) => Container(
                      width: 140 + _pulseController.value * 10,
                      height: 140 + _pulseController.value * 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF3B82F6), Color(0xFF2563EB)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF3B82F6).withOpacity(0.3 + _pulseController.value * 0.1),
                            blurRadius: 30 + _pulseController.value * 20,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          widget.callerName.isNotEmpty ? widget.callerName[0].toUpperCase() : '?',
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 56,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),

                const Spacer(),

                // Local video preview (picture-in-picture)
                if (isVideo && _localStream != null)
                  Align(
                    alignment: Alignment.bottomRight,
                    child: Container(
                      margin: const EdgeInsets.only(right: 20, bottom: 20),
                      width: 120,
                      height: 160,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFF3B82F6).withOpacity(0.5), width: 2),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 10)],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: RTCVideoView(
                        _localRenderer,
                        mirror: true,
                        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                      ),
                    ),
                  ),

                // Call type indicator
                Text(
                  isVideo ? '📹 Appel Vidéo' : '📞 Appel Vocal',
                  style: GoogleFonts.inter(
                    color: Colors.white.withOpacity(0.4),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 24),

                // Action buttons
                if (widget.isIncoming && !_isCallAccepted)
                  _buildIncomingCallActions()
                else
                  _buildActiveCallActions(isVideo),

                const SizedBox(height: 48),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIncomingCallActions() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildCallButton(
          icon: Icons.call_end,
          label: 'Refuser',
          color: const Color(0xFFEF4444),
          onTap: _rejectCall,
        ),
        _buildCallButton(
          icon: Icons.call,
          label: 'Accepter',
          color: const Color(0xFF22C55E),
          onTap: _acceptCall,
        ),
      ],
    );
  }

  Widget _buildActiveCallActions(bool isVideo) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildActionIcon(
            icon: _isMuted ? Icons.mic_off : Icons.mic,
            label: _isMuted ? 'Unmute' : 'Mute',
            isActive: _isMuted,
            onTap: _toggleMute,
          ),
          if (isVideo)
            _buildActionIcon(
              icon: _isCameraOff ? Icons.videocam_off : Icons.videocam,
              label: _isCameraOff ? 'Caméra' : 'Caméra',
              isActive: _isCameraOff,
              onTap: _toggleCamera,
            ),
          _buildActionIcon(
            icon: _isSpeakerOn ? Icons.volume_up : Icons.volume_off,
            label: 'Haut-parleur',
            isActive: !_isSpeakerOn,
            onTap: _toggleSpeaker,
          ),
          _buildCallButton(
            icon: Icons.call_end,
            label: 'Raccrocher',
            color: const Color(0xFFEF4444),
            onTap: _hangUp,
            size: 56,
          ),
        ],
      ),
    );
  }

  Widget _buildActionIcon({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isActive = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive ? Colors.white.withOpacity(0.2) : Colors.white.withOpacity(0.08),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Icon(icon, color: isActive ? const Color(0xFFF97316) : Colors.white, size: 24),
          ),
          const SizedBox(height: 6),
          Text(label, style: GoogleFonts.inter(color: Colors.white.withOpacity(0.5), fontSize: 10)),
        ],
      ),
    );
  }

  Widget _buildCallButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    double size = 64,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [BoxShadow(color: color.withOpacity(0.4), blurRadius: 16, spreadRadius: 2)],
            ),
            child: Icon(icon, color: Colors.white, size: size * 0.45),
          ),
          const SizedBox(height: 8),
          Text(label, style: GoogleFonts.inter(color: Colors.white.withOpacity(0.7), fontSize: 12, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
