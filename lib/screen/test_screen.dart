import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:sdp_transform/sdp_transform.dart';
import 'package:video_conferening_mobile/pojo/meeting_detail.dart';
import 'package:video_conferening_mobile/sdk/transport.dart';

class TestScreen extends StatefulWidget {
  final String meetingId;
  final String name;
  final bool isHost;
  final MeetingDetail meetingDetail;

  const TestScreen(
      {Key key, this.meetingId, this.name, this.meetingDetail, this.isHost})
      : super(key: key);

  @override
  _TestScreenState createState() => _TestScreenState();
}

class _TestScreenState extends State<TestScreen> {
  RTCPeerConnection _peerConnection;
  MediaStream _localStream;
  RTCVideoRenderer _localRenderer = new RTCVideoRenderer();
  RTCVideoRenderer _remoteRenderer = new RTCVideoRenderer();
  final sdpController = TextEditingController();
  Transport transport;
  final Map<String, dynamic> mediaConstraints = {
    "audio": true,
    "video": true,
//    {
//      "mandatory": {
//        "minWidth":
//            '1280', // Provide your own width, height and frame rate here
//        "minHeight": '720',
//        "minFrameRate": '30',
//      },
//      "facingMode": "user",
//      "optional": [],
//    }
  };

  @override
  dispose() {
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  @override
  void initState() {
    initRenderer();
    _createPeerConnecion().then((pc) {
      _peerConnection = pc;
    });
    this.transport = new Transport(
      url:
          "wss://connect.websocket.in/v3/1?api_key=oCdCMcMPQpbvNjUIzqtvF1d2X2okWpDQj4AwARJuAgtjhzKxVEjQU6IdCjwm&notify_self",
      maxRetryCount: 3,
      canReconnect: true,
    );
    this.listenMessage();
    // _getUserMedia();
    super.initState();
  }

  void listenMessage() {
    if (transport != null) {
      transport.on('open', null, (ev, context) {
        print("ev.open  ${(ev.eventData)}");
      });
      transport.on('message', null, (ev, context) {
        print("ev.message  ${(ev.eventData)}");
        var data = json.decode(ev.eventData);
        if (data['type'] == "offer") {
          if (!widget.isHost) {
            _setRemoteDescription(data['data']);
            _createAnswer();
          }
          ;
        }
        if (data['type'] == "answer") {
          if (widget.isHost) _setRemoteDescription(data['data']);
        }
        if (data['type'] == "onIceCandidate") {
          if (widget.isHost) _addCandidate(data['data']);
        }
        print("ev.eventData  ${json.decode(ev.eventData)['data']}");
        print("ev.eventData  ${json.decode(ev.eventData)['type']}");
      });
      transport.on('closed', null, (ev, context) {
        print("ev.closed  ${(ev.eventData)}");
      });
      transport.on('failed', null, (ev, context) {
        print("ev.failed  ${(ev.toString())}");
      });
      transport.connect();
    }
  }

  void sendMessage(String type, dynamic data) {
    try {
      final String payload = json.encode({'type': type, 'data': data});
      if (transport != null) {
        transport.send(payload);
      }
    } catch (error) {
      print("sendMessage $error");
    }
  }

  initRenderer() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
  }

  _createPeerConnecion() async {
    Map<String, dynamic> configuration = {
      "iceServers": [
        {"url": "stun:stun.l.google.com:19302"},
      ]
    };

    final Map<String, dynamic> offerSdpConstraints = {
      "mandatory": {
        "OfferToReceiveAudio": true,
        "OfferToReceiveVideo": true,
      },
      "optional": [],
    };

    _localStream = await _getUserMedia();

    RTCPeerConnection pc =
        await createPeerConnection(configuration, offerSdpConstraints);

    pc.addStream(_localStream);

    pc.onIceCandidate = (e) {
      if (e.candidate != null) {
        print("Start onIceCandidate");
        if (!widget.isHost)
          sendMessage(
              "onIceCandidate",
              json.encode({
                'candidate': e.candidate.toString(),
                'sdpMid': e.sdpMid.toString(),
                'sdpMlineIndex': e.sdpMlineIndex,
              }));
        print(json.encode({
          'candidate': e.candidate.toString(),
          'sdpMid': e.sdpMid.toString(),
          'sdpMlineIndex': e.sdpMlineIndex,
        }));
        print("End onIceCandidate");
      }
    };

    pc.onIceConnectionState = (e) {
      print(e);
    };

    pc.onAddStream = (stream) {
      print('addStream: ' + stream.id);
      _remoteRenderer.srcObject = stream;
    };

    return pc;
  }

  _getUserMedia() async {
    final Map<String, dynamic> constraints = {
      'audio': false,
      'video': {
        'facingMode': 'user',
      },
    };

    MediaStream stream = await navigator.mediaDevices.getUserMedia(constraints);

    _localRenderer.srcObject = stream;

    return stream;
  }

  void _createOffer() async {
    RTCSessionDescription description =
        await _peerConnection.createOffer({'offerToReceiveVideo': 1});
    var session = parse(description.sdp.toString());
    print("Start _createOffer");
    print(json.encode(session));
    sendMessage("offer", json.encode(session));
    print("End _createOffer");
    _peerConnection.setLocalDescription(description);
  }

  void _createAnswer() async {
    RTCSessionDescription description =
        await _peerConnection.createAnswer({'offerToReceiveVideo': 1});

    var session = parse(description.sdp.toString());
    print("Start _createAnswer");
    sendMessage("answer", json.encode(session));
    print(json.encode(session));
    print("End _createAnswer");
    _peerConnection.setLocalDescription(description);
  }

  void _setRemoteDescription(jsonString) async {
    // String jsonString = sdpController.text;
    dynamic session = await jsonDecode('$jsonString');

    String sdp = write(session, null);
    RTCSessionDescription description =
        new RTCSessionDescription(sdp, widget.isHost ? 'answer' : 'offer');
    print(description.toMap());

    await _peerConnection.setRemoteDescription(description);
    setState(() {});
  }

  void _addCandidate(jsonString) async {
    // String jsonString = sdpController.text;
    dynamic session = await jsonDecode('$jsonString');
    print(session['candidate']);
    dynamic candidate = new RTCIceCandidate(
        session['candidate'], session['sdpMid'], session['sdpMlineIndex']);
    await _peerConnection.addCandidate(candidate);
    setState(() {});
  }

  SizedBox videoRenderers() => SizedBox(
      height: 210,
      child: Row(children: [
        Flexible(
          child: new Container(
              key: new Key("local"),
              margin: new EdgeInsets.fromLTRB(5.0, 5.0, 5.0, 5.0),
              decoration: new BoxDecoration(color: Colors.black),
              child: new RTCVideoView(
                _localRenderer,
                mirror: true,
              )),
        ),
        Flexible(
          child: new Container(
              key: new Key("remote"),
              margin: new EdgeInsets.fromLTRB(5.0, 5.0, 5.0, 5.0),
              decoration: new BoxDecoration(color: Colors.black),
              child: new RTCVideoView(_remoteRenderer)),
        )
      ]));

  Row offerAndAnswerButtons() =>
      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: <Widget>[
        widget.isHost
            ? ElevatedButton(
                onPressed: _createOffer,
                child: Text('Call Offer'),
                // color: Colors.amber,
              )
            : ElevatedButton(
                onPressed: _createAnswer,
                child: Text('Answer'),
                style: ElevatedButton.styleFrom(primary: Colors.amber),
              ),
      ]);

  Row sdpCandidateButtons() =>
      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: <Widget>[
        /*ElevatedButton(
          onPressed: _setRemoteDescription,
          child: Text('Set Remote Desc'),
          // color: Colors.amber,
        ),
        ElevatedButton(
          onPressed: _addCandidate,
          child: Text('Add Candidate'),
          // color: Colors.amber,
        )*/
      ]);

  Padding sdpCandidatesTF() => Padding(
        padding: const EdgeInsets.all(16.0),
        child: TextField(
          controller: sdpController,
          keyboardType: TextInputType.multiline,
          maxLines: 4,
          maxLength: TextField.noMaxLength,
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: Text("Video Calling"),
        ),
        body: Container(
            child: Container(
                child: Column(
          children: [
            videoRenderers(),
            offerAndAnswerButtons(),
            sdpCandidatesTF(),
            sdpCandidateButtons(),
          ],
        ))));
  }
}
