import 'dart:convert';

import 'package:eventify/eventify.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:video_conferening_mobile/sdk/connection.dart';
import 'package:video_conferening_mobile/sdk/message_format.dart';
import 'package:video_conferening_mobile/sdk/message_payload.dart';
import 'package:video_conferening_mobile/sdk/payload_data.dart';
import 'package:video_conferening_mobile/sdk/transport.dart';

class MeetingTest extends EventEmitter {
  // final String url ='wss://connect.websocket.in/v3/1?api_key=oCdCMcMPQpbvNjUIzqtvF1d2X2okWpDQj4AwARJuAgtjhzKxVEjQU6IdCjwm&notify_self';
  final String url ='wss://elevate.elsner.com/wss/';

  // final String url = 'ws://10.0.2.2:8081/websocket/meeting';
  Transport transport;
  String meetingId;
  List<Connection> connections = new List();
  bool connected = false;
  MediaStream stream;
  String userId;
  String name;
  List<MessageFormat> messages = new List();
  bool videoEnabled = true;
  bool audioEnabled = true;

  MeetingTest(
      {this.meetingId, this.userId, this.name, this.stream, bool isHost}) {
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

  Connection getConnection(String userId) {
    return connections.firstWhere((connection) => connection.userId == userId,
        orElse: () => null);
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

  Future<void> joinedMeeting(UserJoinedData data) async {
    final connection = await createConnection(data);
    if (connection != null) {
      sendOfferSdp(data.userId);
      /*this.sendMessage('join-meeting', {
          'name': name,
          'userId': userId,
          'config': {
            'audioEnabled': audioEnabled,
            'videoEnabled': videoEnabled,
          },
        });*/
    }
  }

  logPrint(data) {
    print("========= Start ==========");
    print(data);
    print("========= End ==========");
  }

  void sendOfferSdp(userId) async {
    final connection = getConnection(userId);
    if (connection != null) {
      final sdp = await connection.createOffer();
      logPrint("Offer Send");
      sendMessage('offer-sdp', {
        'userId': this.userId,
        'otherUserId': userId,
        'sdp': sdp.toMap(),
      });
    } else {}
  }

  Future<Connection> createConnection(UserJoinedData data) async {
    if (stream != null) {
      if (connections.indexWhere((element) => element.userId == data.userId) ==
              -1 &&
          data.userId != userId) {
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
          // sendIceCandidate(connection.userId, ev.eventData);
        });
        connection.on('stream-changed', null, (ev, context) {
          this.emit('stream-changed');
        });
        connections.add(connection);

        print("createConnection  $data  ${connections}");

        await connection.start();
        this.emit('connection', null, connection);
        return connection;
      } else {
        /*var connection = getConnection(data.userId);
        if (connection != null) {
          await connection.start();
          this.emit('connection', null, connection);
          return connection;
        }*/
      }
    }
    return null;
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
  }

  stopStream() {
    if (stream != null) {
      stream.dispose();
    }
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

  void sendUserMessage(String text) {
    sendMessage('message', {
      'userId': this.userId,
      'message': {
        'userId': this.userId,
        'text': text,
      },
    });
  }

  void handleMessage(MessagePayload payload) {
    print("handleMessage ${payload.type}");
    switch (payload.type) {
      case 'join-meeting':
        joinedMeeting(UserJoinedData.fromJson(payload.data));
        break;
      case 'offer-sdp':
        receivedOfferSdp(OfferSdpData.fromJson(payload.data));
        break;
      case 'answer-sdp':
        receivedAnswerSdp(AnswerSdpData.fromJson(payload.data));
        break;
      case 'icecandidate':
        setIceCandidate(IceCandidateData.fromJson(payload.data));
        break;
      case 'leave-meeting':
        leaveMetting(LeaveCandidateData.fromJson(payload.data));
        break;
      case 'video-toggle':
        listenVideoToggle(VideoToggleData.fromJson(payload.data));
        break;
      case 'audio-toggle':
        listenAudioToggle(AudioToggleData.fromJson(payload.data));
        break;
      /*case 'message':
        handleUserMessage(MessageData.fromJson(payload.data));
        break;
      case 'not-found':
        handleNotFound();
        break;*/
      default:
        break;
    }
  }

  void setIceCandidate(IceCandidateData data) async {
    if (data.userId == this.userId) {
      return;
    }
    logPrint("setIceCandidate");
    final connection = getConnection(data.userId);
    if (connection != null) {
      await connection.setCandidate(data.candidate);
    }
  }

  void leaveMetting(LeaveCandidateData data) async {
    var index =
        connections.indexWhere((element) => element.userId == data.userId);
    if (index != -1) {
      connections[index].close();
      connections.removeAt(index);
      this.emit('connection-setting-changed');
    }
  }

  void receivedAnswerSdp(AnswerSdpData data) async {
    if (data.userId == this.userId || data.otherUserId != this.userId) {
      return;
    }
    logPrint("received Answer");
    final connection = getConnection(data.userId);
    if (connection != null) {
      await connection.setAnswerSdp(data.sdp);
      connection.on('candidate', null, (ev, context) {
        sendIceCandidate(connection.userId, ev.eventData);
      });
    } else {
      await createConnection(UserJoinedData(
          name: "${data.userId}",
          userId: "${data.userId}",
          config: Config(
            audioEnabled: true,
            videoEnabled: true,
          )));
      receivedAnswerSdp(data);
    }
  }

  void sendIceCandidate(String otherUserId, RTCIceCandidate candidate) {
    if (otherUserId == this.userId) {
      return;
    }
    logPrint("sendIceCandidate");
    sendMessage('icecandidate', {
      'userId': userId,
      'otherUserId': otherUserId,
      'candidate': candidate.toMap(),
    });
  }

  void receivedOfferSdp(OfferSdpData data) {
    if (this.userId == data.otherUserId && this.userId != data.userId) {
      logPrint("Offer receive");
      this.sendAnswerSdp(data.userId, data.sdp);
    }
  }

  void sendAnswerSdp(String otherUserId, RTCSessionDescription sdp) async {
    final connection = getConnection(otherUserId);
    if (connection != null) {
      await connection.setOfferSdp(sdp);
      final answerSdp = await connection.createAnswer();
      logPrint("sendAnswerSdp");
      sendMessage('answer-sdp', {
        'userId': this.userId,
        'otherUserId': otherUserId,
        'sdp': answerSdp.toMap(),
      });
      connection.on('candidate', null, (ev, context) {
        sendIceCandidate(connection.userId, ev.eventData);
      });
    } else {
      await createConnection(UserJoinedData(
          name: "${otherUserId}",
          userId: "${otherUserId}",
          config: Config(
            audioEnabled: true,
            videoEnabled: true,
          )));
      sendAnswerSdp(otherUserId, sdp);
    }
  }

  void reset() {
    this.connections = new List();
    this.connected = false;
  }

  void reconnect() {
    if (transport != null) {
      transport.reconnect();
    }
  }
}
