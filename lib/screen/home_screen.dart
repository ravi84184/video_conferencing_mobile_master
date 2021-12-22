import 'package:flutter/material.dart';
import 'package:video_conferening_mobile/pojo/meeting_detail.dart';
import 'package:video_conferening_mobile/screen/meeting_screen.dart';
import 'package:video_conferening_mobile/screen/test_screen.dart';
import 'package:video_conferening_mobile/util/user.util.dart';

import '../widget/button.dart';

class HomeScreen extends StatefulWidget {
  HomeScreen({Key key, this.title}) : super(key: key);

  final String title;

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController controller =
      new TextEditingController(text: "123456789");
  final TextEditingController userIdcontroller =
      new TextEditingController(text: "123");
  final scaffoldKey = GlobalKey<ScaffoldState>();

  Future<void> goToJoinScreen(meetingId, userId) async {
    await setUserId(userId);
    /*Navigator.push(context,
        MaterialPageRoute(builder: (BuildContext context) {
      return TestScreen(
        meetingId: meetingId,
        name: userId,
        isHost: userId == "123",
        meetingDetail: MeetingDetail(
            hostId: "123", hostName: "$meetingId", id: "$meetingId"),
      );
    }));*/
    Navigator.push(context,
        MaterialPageRoute(builder: (BuildContext context) {
      return MeetingScreen(
        meetingId: meetingId,
        name: userId,
        isHost: userId == "123",
        meetingDetail: MeetingDetail(
            hostId: "123", hostName: "$meetingId", id: "$meetingId"),
      );
    }));
    /*Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => JoinScreen(
          meetingId: "$meetingId",
          meetingDetail: MeetingDetail(
              hostId: "123", hostName: "$meetingId", id: "$meetingId"),
        ),
      ),
    );*/
  }

  void joinMeetingClick() async {
    final meetingId = controller.text;
    final userId = userIdcontroller.text;
    print('Joined meeting $meetingId');
    goToJoinScreen(meetingId, userId);
  }

  void startMeetingClick() async {
    final meetingId = controller.text;
    final userId = userIdcontroller.text;
    print('Joined meeting $meetingId');
    goToJoinScreen(meetingId, userId);
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: scaffoldKey,
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Container(
                margin: EdgeInsets.only(bottom: 40.0),
                child: Text(
                  "Welcome to Meet X",
                  style: TextStyle(
                    color: Colors.green,
                    fontSize: 32.0,
                  ),
                ),
              ),
              Container(
                margin: EdgeInsets.only(bottom: 20.0),
                child: TextFormField(
                  controller: controller,
                  style: TextStyle(
                    fontSize: 20,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Enter the Meeting Id',
                    hintStyle: TextStyle(
                      fontSize: 20,
                    ),
                  ),
                ),
              ),
              Container(
                margin: EdgeInsets.only(bottom: 20.0),
                child: TextFormField(
                  controller: userIdcontroller,
                  style: TextStyle(
                    fontSize: 20,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Enter the User Id',
                    hintStyle: TextStyle(
                      fontSize: 20,
                    ),
                  ),
                ),
              ),
              Button(
                text: "Join Meeting",
                onPressed: joinMeetingClick,
              ),
              Button(
                text: "Start Meeting",
                onPressed: startMeetingClick,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
