import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../models/communication_models.dart';
import '../../services/communication_service.dart';
import 'call_screen.dart';

class IncomingCallNotification extends StatefulWidget {
  final CallNotification call;
  final CommunicationService communicationService;

  const IncomingCallNotification({
    required this.call,
    required this.communicationService,
  });

  @override
  State<IncomingCallNotification> createState() =>
      _IncomingCallNotificationState();
}

class _IncomingCallNotificationState extends State<IncomingCallNotification> {
  late AudioPlayer _audioPlayer;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    _playRingtone();
  }

  Future<void> _playRingtone() async {
    try {
      await _audioPlayer.loop(AssetSource('sounds/ringtone.mp3'));
    } catch (e) {
      print('Erreur lecture sonnerie: $e');
    }
  }

  void _acceptCall() {
    _audioPlayer.stop();
    widget.communicationService.acceptCall(widget.call.callId);

    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CallScreen(
          callId: widget.call.callId,
          currentUserId: widget.call.receiverId,
          currentUserName: 'Vous',
          otherUserId: widget.call.callerId,
          otherUserName: widget.call.callerName,
          isVideoCall: widget.call.callType == CallType.video,
        ),
      ),
    );
  }

  void _rejectCall() {
    _audioPlayer.stop();
    widget.communicationService.rejectCall(widget.call.callId);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black87,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 60,
              backgroundColor: Colors.blue,
              child: Text(
                widget.call.callerName[0],
                style: const TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 30),
            Text(
              widget.call.callerName,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  widget.call.callType == CallType.voice
                      ? Icons.call
                      : Icons.videocam,
                  color: Colors.blue,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  widget.call.callType == CallType.voice
                      ? 'Appel vocal entrant'
                      : 'Appel vidéo entrant',
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 60),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: _rejectCall,
                  child: Container(
                    width: 70,
                    height: 70,
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.call_end,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                ),
                const SizedBox(width: 40),
                GestureDetector(
                  onTap: _acceptCall,
                  child: Container(
                    width: 70,
                    height: 70,
                    decoration: const BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.call,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }
}