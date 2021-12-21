import 'dart:convert';

import 'package:eventify/eventify.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:video_conferening_mobile/sdk/connection.dart';
import 'package:video_conferening_mobile/sdk/message_format.dart';
import 'package:video_conferening_mobile/sdk/message_payload.dart';
import 'package:video_conferening_mobile/sdk/payload_data.dart';
import 'package:video_conferening_mobile/sdk/transport.dart';

class Meeting extends EventEmitter {
  final String url =
      'wss://connect.websocket.in/v3/1?api_key=oCdCMcMPQpbvNjUIzqtvF1d2X2okWpDQj4AwARJuAgtjhzKxVEjQU6IdCjwm&notify_self';

  // final String url = 'ws://10.0.2.2:8081/websocket/meeting';
  Transport transport;
  String meetingId;
  List<Connection> connections = new List();
  bool joined = false;
  bool connected = false;
  bool isHost = false;
  MediaStream stream;
  String userId;
  String name;
  List<MessageFormat> messages = new List();
  bool videoEnabled = true;
  bool audioEnabled = true;

  Meeting({this.meetingId, this.userId, this.name, this.stream, this.isHost}) {
    this.transport = new Transport(
      url: formatUrl(this.meetingId),
      maxRetryCount: 3,
      canReconnect: true,
    );
    this.listenMessage();
  }

  String formatUrl(String id) {
    return '$url';
  }

  MessagePayload parseMessage(dynamic data) {
    try {
      return MessagePayload.fromJson(json.decode(data));
    } catch (error) {
      return MessagePayload(type: 'unknown');
    }
  }

  void sendMessage(String type, dynamic data) {
    try {
      final String payload = json.encode({'type': type, 'data': data});
      if (transport != null) {
        transport.send(payload);
      }
    } catch (error) {
      print(error);
    }
  }

  void listenMessage() {
    if (transport != null) {
      transport.on('open', null, (ev, context) {
        this.emit('open');
        connected = true;
        print(ev.eventName);
        join();
      });
      transport.on('message', null, (ev, context) {
        print(ev.eventData);
        final payload = parseMessage(ev.eventData);
        handleMessage(payload);
      });
      transport.on('closed', null, (ev, context) {
        connected = false;
      });
      transport.on('failed', null, (ev, context) {
        this.reset();
        this.emit('failed');
      });
      transport.connect();
    }
  }

  Connection getConnection(String userId) {
    return connections.firstWhere((connection) => connection.userId == userId,
        orElse: () => null);
  }

  Future<Connection> createConnection(UserJoinedData data) async {
    if (stream != null) {
      final connection = new Connection(
        connectionType: 'incoming',
        userId: data.userId,
        name: data.name,
        stream: stream,
        audioEnabled: data.config.audioEnabled,
        videoEnabled: data.config.videoEnabled,
      );
      connection.on('connected', null, (ev, context) {
        print('rtp connected');
      });
      connection.on('candidate', null, (ev, context) {
        if (!isHost) sendIceCandidate(connection.userId, ev.eventData);
      });
      connection.on('stream-changed', null, (ev, context) {
        this.emit('stream-changed');
      });
      if (connections.indexWhere(
                  (element) => element.userId == connection.userId) ==
              -1 &&
          connection.userId != userId) connections.add(connection);

      print("createConnection  $data  ${connections}");

      await connection.start();
      this.emit('connection', null, connection);
      return connection;
    }
    return null;
  }

  void join() {
    this.sendMessage('join-meeting', {
      'name': name,
      'userId': userId,
      'config': {
        'audioEnabled': audioEnabled,
        'videoEnabled': videoEnabled,
      },
    });
  }

  void userJoin() {
    this.sendMessage('user-joined', {
      'name': name,
      'userId': userId,
      'config': {
        'audioEnabled': audioEnabled,
        'videoEnabled': videoEnabled,
      },
    });
  }

  void joinedMeeting(JoinedMeetingData data) {
    joined = true;
    // userId = data.userId;
    userJoin();
  }

  void userJoined(UserJoinedData data) async {
    final connection = await createConnection(data);
    if (connection != null) {
      if (!isHost) sendConnectionRequest(connection.userId);
    }
  }

  void sendIceCandidate(String otherUserId, RTCIceCandidate candidate) {
    sendMessage('icecandidate', {
      'userId': userId,
      'otherUserId': otherUserId,
      'candidate': candidate.toMap(),
    });
  }

  void sendConnectionRequest(String otherUserId) {
    sendMessage('connection-request', {
      'name': name,
      'userId': userId,
      'otherUserId': otherUserId,
      'config': {
        'audioEnabled': audioEnabled,
        'videoEnabled': videoEnabled,
      },
    });
  }

  void receivedConnectionRequest(UserJoinedData data) async {
    final connection = await createConnection(data);
    if (connection != null) {
      if (isHost) sendOfferSdp(data.userId);
    }
  }

  void sendOfferSdp(String otherUserId) async {
    final connection = getConnection(otherUserId);
    if (connection != null) {
      final sdp = await connection.createOffer();
      sendMessage('offer-sdp', {
        'userId': userId,
        'otherUserId': otherUserId,
        'sdp': sdp.toMap(),
      });
    }
  }

  void receivedOfferSdp(OfferSdpData data) {
    if (!isHost) this.sendAnswerSdp(data.userId, data.sdp);
  }

  void sendAnswerSdp(String otherUserId, RTCSessionDescription sdp) async {
    final connection = getConnection(otherUserId);
    if (connection != null) {
      await connection.setOfferSdp(sdp);
      final answerSdp = await connection.createAnswer();
      sendMessage('answer-sdp', {
        'userId': this.userId,
        'otherUserId': otherUserId,
        'sdp': answerSdp.toMap(),
      });
    }
  }

  void receivedAnswerSdp(AnswerSdpData data) async {
    final connection = getConnection(data.userId);
    if (connection != null) {
      if (isHost) await connection.setAnswerSdp(data.sdp);
    }
  }

  void setIceCandidate(IceCandidateData data) async {
    final connection = getConnection(data.userId);
    if (connection != null) {
      await connection.setCandidate(data.candidate);
    }
  }

  void userLeft(UserLeftData data) {
    final connection = getConnection(data.userId);
    if (connection != null) {
      this.emit('user-left', null, connection);
      connection.close();
      connections.removeWhere((element) => element.userId == connection.userId);
    }
  }

  void meetingEnded(MeetingEndedData data) {
    this.emit('ended');
    destroy();
  }

  void end() {
    sendMessage('end-meeting', {
      'userId': this.userId,
    });
    destroy();
  }

  void leave() {
    sendMessage('leave-meeting', {
      'userId': this.userId,
    });
    destroy();
  }

  bool toggleVideo() {
    if (stream != null) {
      final videoTrack = stream.getVideoTracks()[0];
      if (videoTrack != null) {
        final bool videoEnabled = videoTrack.enabled = !videoTrack.enabled;
        this.videoEnabled = videoEnabled;
        sendMessage('video-toggle', {
          'userId': this.userId,
          'videoEnabled': videoEnabled,
        });
        return videoEnabled;
      }
    }
    return false;
  }

  bool toggleAudio() {
    if (stream != null) {
      final audioTrack = stream.getAudioTracks()[0];
      if (audioTrack != null) {
        final bool audioEnabled = audioTrack.enabled = !audioTrack.enabled;
        this.audioEnabled = audioEnabled;
        sendMessage('audio-toggle', {
          'userId': this.userId,
          'audioEnabled': audioEnabled,
        });
        return audioEnabled;
      }
    }
    return false;
  }

  void listenVideoToggle(VideoToggleData data) {
    final connection = this.getConnection(data.userId);
    if (connection != null) {
      connection?.toggleVideo(data.videoEnabled);
      this.emit('connection-setting-changed');
    }
  }

  void listenAudioToggle(AudioToggleData data) {
    final connection = this.getConnection(data.userId);
    if (connection != null) {
      connection.toggleAudio(data.audioEnabled);
      this.emit('connection-setting-changed');
    }
  }

  void handleUserMessage(MessageData data) {
    this.messages.add(data.message);
    this.emit('message', null, data.message);
  }

  void sendUserMessage(String text) {
    sendMessage('message', {
      'userId': this.userId,
      'message': {
        'userId': this.userId,
        'text': text,
      },
    });
  }

  void handleNotFound() {
    this.emit('not-found');
  }

  stopStream() {
    if (stream != null) {
      stream.dispose();
    }
  }

  void handleMessage(MessagePayload payload) {
    print("handleMessage ${payload.type}");
    switch (payload.type) {
      // case 'joined-meeting':
      case 'join-meeting':
        joinedMeeting(JoinedMeetingData.fromJson(payload.data));
        break;
      case 'user-joined':
        userJoined(UserJoinedData.fromJson(payload.data));
        break;
      case 'connection-request':
        receivedConnectionRequest(UserJoinedData.fromJson(payload.data));
        break;
      case 'offer-sdp':
        receivedOfferSdp(OfferSdpData.fromJson(payload.data));
        break;
      case 'answer-sdp':
        receivedAnswerSdp(AnswerSdpData.fromJson(payload.data));
        break;
      case 'user-left':
        userLeft(UserLeftData.fromJson(payload.data));
        break;
      case 'meeting-ended':
        meetingEnded(MeetingEndedData.fromJson(payload.data));
        break;
      case 'icecandidate':
        setIceCandidate(IceCandidateData.fromJson(payload.data));
        break;
      case 'video-toggle':
        listenVideoToggle(VideoToggleData.fromJson(payload.data));
        break;
      case 'audio-toggle':
        listenAudioToggle(AudioToggleData.fromJson(payload.data));
        break;
      case 'message':
        handleUserMessage(MessageData.fromJson(payload.data));
        break;
      case 'not-found':
        handleNotFound();
        break;
      default:
        break;
    }
  }

  void destroy() {
    if (transport != null) {
      transport.destroy();
      transport = null;
    }
    connections.forEach((connection) {
      connection.close();
    });
    stopStream();
    connections = [];
    connected = false;
    stream = null;
    joined = false;
  }

  void reset() {
    this.connections = new List();
    this.joined = false;
    this.connected = false;
  }

  void reconnect() {
    if (transport != null) {
      transport.reconnect();
    }
  }
}
