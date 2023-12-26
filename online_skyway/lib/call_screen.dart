import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:io' show Platform;
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:location/location.dart';
import 'package:permission_handler/permission_handler.dart' as permission;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'skyway.dart';
import 'login_screen.dart';
import 'skyway_canvas_view.dart';

String? dropdownValue;

String? selectedRoomCd; 

String? loginKengenKbn;
int? loginUserNo;

String _roomName = '';

List roomDataList = [];

class Room {
  final String roomId;
  final String roomName;
  final String roomCD;

  Room({required this.roomId, required this.roomName, required this.roomCD});

  factory Room.fromJson(Map<String, dynamic> json) {
    return Room(
      roomId: json['roomId'],
      roomName: json['roomName'],
      roomCD: json['roomCD'],
    );
  }
}
class SkywayRoom {
  final List<Room> roomList;
  SkywayRoom({required this.roomList});

  factory SkywayRoom.fromJson(Map<String, dynamic> json) {
    var roomListJson = json['roomList'] as List;
     List<Room> rooms = roomListJson.map((roomJson) {
      return Room.fromJson(roomJson);
    }).toList();
    
    if (roomListJson.length == 1) {
      _roomName = roomListJson[0]['roomId'];
      dropdownValue = roomListJson[0]['roomId'];
    }
    roomDataList = rooms;
    return SkywayRoom(roomList: rooms);
  }
}

class User {
  final int userNo;
  final String userName;

  User({
    required this.userNo,
    required this.userName,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      userNo: json['userNo'],
      userName: json['userName'],
    );
  }
}

class RemotePeer {
  bool _hasRemoteStream = false;
}

class CallP2pMeshScreen extends StatefulWidget {
  const CallP2pMeshScreen(this.loginToken, {required this.title});

  final String title;
  final String loginToken;

  @override
  _CallP2pMeshScreenState createState() => _CallP2pMeshScreenState();
}

class _CallP2pMeshScreenState extends State<CallP2pMeshScreen> {

  // static const String baseUrl = "http://192.168.5.152/TelemedicineSystemAPI";
  static const String baseUrl = "https://smartmedical-tm.jp/TELEMEDICINE_API";
  // static const String baseUrl = "https://demo.smartmedical-tm.jp/TELEMEDICINE_API_DEMO"; 
  // static const String baseUrl = "https://10.100.9.7:6443/OnlineCommunicationAPI";

  static const String _skyWaydomain = 'localhost';
  String _skyWayapiKey = '9a0d441d-c3a5-4f03-a8e8-89a644e84b85';
    
  final GlobalKey _popupMenuKey = GlobalKey();
  final ValueKey _localVideoKey = const ValueKey('localVideo');

  int? myUserNo;
  String? machineId;
  int? tantoNo;

  int? newConnectionNo;
  int? waitUserNo;
  int? secondUserNo;
  int? selectUserNo;
  bool _endFlg = false, isLandscape = false;
  bool cameraMicGranted = false;

  bool _isConnecting = false;
  bool _hasLocalStream = false;
  bool _isJoined = false;
  bool isCallButtonEnabled = true; // Initially enabled
  bool _hideRemoteVideo = false;
  String _systemName = "", _googleMapConfig = '';

  // 接続ボタン
  int callButtonState = 1;
  String callButtonText = '接続開始';
  Color callButtonBackgroundColor = const Color(0xFF00698D);
  //画面共有ボタン
  int shareScreenButtonState = 1;
  String shareScreenButtonText = '画面共有';
  Color screenShareBackgroundColor = const Color(0xFF00698D);
  
  late Future<SkywayRoom> futureSkywayRoom;
  final List<User> userList = [];
    
  DateTime? startTime;
  DateTime? examStartTime;
  DateTime? examEndTime;

 
  int? localVideoId;
  

  SkywayPeer? _peer;
  final Map<String, RemotePeer> _remotePeers = {};

  bool get isConnected {
    return _peer != null;
  }

  bool get isTalking {
    return (_peer != null) && _remotePeers.isNotEmpty;
  }

  //Google Mapボタン
  int mapButtonState = 1;
  String mapButtonText = 'マップ表示';
  Color mapButtonBackgroundColor = const Color(0xFF00698D);

  // Location
  final Location location = Location();
  late LocationData _locationData;
  late bool _serviceEnabled;
  late PermissionStatus _permissionGranted;
  double ownLat = 0;
  double ownLng = 0;
  StreamSubscription<LocationData>? locationSubscription;


  //Google Map
  late GoogleMapController mapController;
  late final Uint8List customMarker;
  double userLat = 0;
  double userLng = 0;

  double screenSizeWidth = 0;

  //Partner Info
  int? partnerUserNo, updateLogNo;
  String? partnerMachineId;

  @override
  void initState() {
    super.initState();
    init();
  }

  init() async{
    loadSkywayAPIKey(loginToken);
    _loadPrefs();
    futureSkywayRoom  = fetchRoom(widget.loginToken);
    loadMyInfo(widget.loginToken);
    _initCustomMarkerIcon();
    }

  Future<void> _checkLocationPermission() async {
    // 位置情報をリクエストするには、常に位置情報サービスのステータスと許可ステータスを手動で確認する必要
    _serviceEnabled = await location.serviceEnabled();
    if (!_serviceEnabled) {
      _serviceEnabled = await location.requestService();
      if (!_serviceEnabled) {
        return;
      }
    }
    _permissionGranted = await location.hasPermission();
    if (_permissionGranted == PermissionStatus.denied) {
      _permissionGranted = await location.requestPermission();
      if (_permissionGranted != PermissionStatus.granted) {
        return;
      }
    }
    _locationData = await location.getLocation();
        setState(() {
          ownLat = _locationData.latitude!;
          ownLng = _locationData.longitude!;
          if(_remotePeers.isNotEmpty){
            // 位置情報を送信する
            _sendRealTimeMapInfo();
          }
        });
    location.onLocationChanged.listen((LocationData currentLocation) {
      setState(() {
        ownLat = currentLocation.latitude!;
        ownLng = currentLocation.longitude!;
        if(_remotePeers.isNotEmpty){
          // 位置情報を送信する
          _sendRealTimeMapInfo();
        }
      });
    });
  }

  void _sendRealTimeMapInfo() async {
    Map<String, dynamic> latLng = {
       "isRecievedMapData": true,
          "myUserNo": loginUserNo,
          "latLng": {
            "lat": ownLat,
            "lng": ownLng
          }
    };
    String jsonStringlatLng = jsonEncode(latLng);
    await _peer!.sendData(localVideoId!, jsonStringlatLng);
    debugPrint('send mapinfo:$jsonStringlatLng');
  }

  Future<void> _initCustomMarkerIcon() async {
    customMarker = await getBytesFromAsset(
      path:"images/custom-marker-people.png", 
      width: 100 
    );   
  }

  Future<Uint8List> getBytesFromAsset({required String path,required int width})async {
      ByteData data = await rootBundle.load(path);
      ui.Codec codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(), 
        targetWidth: width
      );
      ui.FrameInfo fi = await codec.getNextFrame();
      return (await fi.image.toByteData(
        format: ui.ImageByteFormat.png))!
      .buffer.asUint8List();
  }

  // 相手のuserLat、userLng通りMapのpositionを更新
  Future<void>  _updateCameraPosition() async{
    CameraPosition newPosition = CameraPosition(
      target: LatLng(userLat, userLng), 
      zoom: 15,
    );
    mapController.animateCamera(CameraUpdate.newCameraPosition(newPosition));
  }

  // キャメラ切り替え
  void _switchCamera() async{
    await _peer!.switchCameraStream(localVideoId!);
  }

  // 回転画面のローカルビデオが停止するとビデオを再開
  void _resumeLocalVideo() async{
    await _peer!.resumeCaptureStream(localVideoId!);
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // 戻るのを防ぐ
        return false;
      },
    child: OrientationBuilder(
      builder: (context, orientation) {
        if (orientation == Orientation.landscape) {
          isLandscape = true;
        } else {
          isLandscape = false;
        }
        return Stack(
          children: [
          Scaffold(
          appBar: AppBar(
            title: Text(_systemName, 
              style: const TextStyle(
                color: Colors.white,
              ),
            ),
            automaticallyImplyLeading: false,
            actions: <Widget>[
            // 画面共有ボタン
              if(isLandscape)
                if (_remotePeers.isNotEmpty)
                  ElevatedButton(
                    onPressed: () {
                      changeScreenShareState();
                    },
                    style: ButtonStyle(
                      backgroundColor: MaterialStateProperty.all(
                          screenShareBackgroundColor),
                    ),
                    child: Text(
                      shareScreenButtonText,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16.0,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
              if (isLandscape)
                // GoogleMapボタン
                if(_remotePeers.isNotEmpty && _googleMapConfig == '1')
                  ElevatedButton(
                    onPressed: () {
                      changeMapButtonState();
                    },
                    style: ButtonStyle(
                      backgroundColor: MaterialStateProperty.all(
                          mapButtonBackgroundColor),
                    ),
                    child: Text(
                      mapButtonText,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16.0,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
              IconButton(
                icon: const Icon(Icons.logout), 
                onPressed: () {
                    onLogout();
                }),
            ],
          ),
           body: orientation == Orientation.portrait
                    ? buildPortraitLayout()
                    : buildLandscapeLayout(),
          )
        ],
        );
      }
    ),
    );
  }


  Widget buildPortraitLayout() {
    final Size screenSz = MediaQuery.of(context).size;
    final double w = (screenSz.width - 8) / 2.0;
    final double h = w / 3.0 * 4.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      key: _popupMenuKey,
      children: [
        Container(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Expanded(
                  flex: 1,
                  child: Column(children: [
                     // Dropdown メニュー
                    Column(
                      children: [
                        FutureBuilder<SkywayRoom>(
                          future: futureSkywayRoom,
                          builder: (context, snapshot) {
                            if (snapshot.hasData) {
                              return Column(
                                children: [
                                  IntrinsicWidth(
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(maxWidth: 150), // Set your maximum width here
                                      child: DropdownButton<String>(
                                        isExpanded: true,
                                        itemHeight: null,
                                        value: dropdownValue,
                                        elevation: 8,
                                        style: const TextStyle(color: Colors.black),
                                        underline: Container(
                                          height: 2,
                                          color:
                                              const Color.fromARGB(255, 23, 22, 25),
                                        ),
                                        onChanged: (newValue) {
                                          setState(() {
                                            if (newValue != 'placeholder') {
                                              dropdownValue = newValue;
                                              _setRoomName(newValue!,
                                                  snapshot.data!.roomList);
                                            }
                                          });
                                        },
                                        items: [
                                          const DropdownMenuItem<String>(
                                            value: 'placeholder',
                                            child: Text('ルームを選択'),
                                          ),
                                          ...snapshot.data!.roomList.map((room) {
                                            return DropdownMenuItem<String>(
                                              value: room.roomId,
                                              child: Text(room.roomName),
                                            );
                                          }),
                                        ],
                                        hint: dropdownValue == null
                                            ? const Text('ルームを選択',
                                                style:
                                                    TextStyle(color: Colors.grey))
                                            : null,
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            } else if (snapshot.hasError) {
                              return Text('${snapshot.error}');
                            }
                            return const CircularProgressIndicator(
                              strokeWidth: 1,
                            );
                          },
                        ),
                      ],
                    ),
                    // GoogleMapボタン
                    if (_remotePeers.isNotEmpty && _googleMapConfig == '1')
                      Container(
                        alignment: Alignment.topCenter,
                        // padding: const EdgeInsets.only(top: 1.0),
                        child: ElevatedButton(
                          onPressed: () {
                            changeMapButtonState();
                          },
                          style: ButtonStyle(
                            padding: MaterialStateProperty.all(
                                const EdgeInsets.all(4)),
                            backgroundColor: MaterialStateProperty.all(
                                mapButtonBackgroundColor),
                          ),
                          child: Text(
                            mapButtonText,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16.0,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ])),
              // ボタン
              Expanded(
                flex: 1,
                child: Column(
                  children: [
                    // Cameraボタン
                    if (isConnected)
                      IconButton(
                        icon: const Icon(Icons.cameraswitch),
                        onPressed: _switchCamera,
                      ),
                    // 接続ボタン
                    Container(
                      alignment: Alignment.topCenter,
                      child: ElevatedButton(
                        onPressed: isCallButtonEnabled
                            ? () {
                                changeCallState();
                              }
                            : null,
                        style: ButtonStyle(
                          padding: MaterialStateProperty.all(
                              const EdgeInsets.all(4)),
                          backgroundColor: MaterialStateProperty.all(
                              callButtonBackgroundColor),
                        ),
                        child: Text(
                          callButtonText,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16.0,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                    // 画面共有ボタン
                    if (_remotePeers.isNotEmpty)
                      ElevatedButton(
                        onPressed: () {
                          changeScreenShareState();
                        },
                        style: ButtonStyle(
                          padding: MaterialStateProperty.all(
                              const EdgeInsets.all(4)),
                          backgroundColor: MaterialStateProperty.all(
                              screenShareBackgroundColor),
                        ),
                        child: Text(
                          shareScreenButtonText,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16.0,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                  ],
                ),
              ), 
              // ロカルvideo
              if (isConnected)
                Expanded(
                  flex: 1,
                  child: Container(
                    padding: const EdgeInsets.all(4.0),
                    width: w * 0.6,
                    height: h * 0.6,
                    child: _buildLocalVideo(),
                  ),
                )
              else
                Expanded(
                  flex: 1,
                  child: Container(
                      padding: const EdgeInsets.all(4.0),
                    width: w * 0.6,
                    height: h * 0.6,
                  ),
                ),
            ],
          ),
        ),
        // Google map
        if (_hideRemoteVideo && _remotePeers.isNotEmpty && _googleMapConfig == '1')
          Expanded(
            flex: 1,
            child: Container(
              padding: const EdgeInsets.all(4.0),
              width: w * 1.95,
              height: h * 1.9,
              child: GoogleMap(
                onMapCreated: (GoogleMapController controller) {
                  mapController = controller;
                },
                initialCameraPosition: CameraPosition(
                  target: LatLng(userLat, userLng),
                  zoom: 15,
                ),
                markers: {
                  Marker(
                    markerId: const MarkerId('userMarker'),
                    position: LatLng(ownLat, ownLng),
                    infoWindow: const InfoWindow(title: '現在位置'),
                  ),
                  Marker(
                      markerId: const MarkerId('customUserMarker'),
                      position: LatLng(userLat, userLng),
                      infoWindow: const InfoWindow(title: '相手の現在位置'),
                      icon: BitmapDescriptor.fromBytes(customMarker)),
                },
              ),
            ),
          )
        else
          // リモートVideo
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(8.0),
              width: w * 1.95,
              height: h * 1.9,
              child: Row(
                children: _buildRemoteVideos(w * 1.95, h * 1.9),
              ),
            ),
          ),
      ],
    );
  }

  Widget buildLandscapeLayout() {
    final Size screenSz = MediaQuery.of(context).size;
    screenSizeWidth = screenSz.width;

    final double w = (screenSz.width - 8) / 2.0;
    final double h = w / 3.0 * 4.0;
  
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      key: _popupMenuKey,
      children: [
        Container(
          padding: const EdgeInsets.all(4.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              // ボタン
              Expanded(
                flex: 1,
                child: Column(
                  children: [
                    FutureBuilder<SkywayRoom>(
                      future: futureSkywayRoom,
                      builder: (context, snapshot) {
                        if (snapshot.hasData) {
                          return Column(
                            children: [
                              IntrinsicWidth(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 150), 
                                  child: DropdownButton<String>(
                                    isExpanded: true, //fix RenderFlex overflowed
                                    itemHeight: null, //fit both lines of text
                                    value: dropdownValue,
                                    elevation: 8,
                                    style: const TextStyle(color: Colors.black),
                                    underline: Container(
                                      height: 2,
                                      color: const Color.fromARGB(255, 23, 22, 25),
                                    ),
                                    onChanged: (newValue) {
                                      setState(() {
                                        if (newValue != 'placeholder') {
                                          dropdownValue = newValue;
                                          _setRoomName(
                                              newValue!, snapshot.data!.roomList);
                                        }
                                      });
                                    },
                                    items: [
                                      const DropdownMenuItem<String>(
                                        value: 'placeholder',
                                        child: Text('ルームを選択'),
                                      ),
                                      ...snapshot.data!.roomList.map((room) {
                                        return DropdownMenuItem<String>(
                                          value: room.roomId,
                                          child: Text(room.roomName),
                                        );
                                      }),
                                    ],
                                    hint: dropdownValue == null
                                        ? const Text('ルームを選択',
                                            style: TextStyle(color: Colors.grey))
                                        : null,
                                  ),
                                ),
                              ),
                            ],
                          );
                        } else if (snapshot.hasError) {
                          return Text('${snapshot.error}');
                        }
                        return const CircularProgressIndicator(
                          strokeWidth: 1,
                        );
                      },
                    ),
                    // Cameraボタン
                    if (isConnected)
                      IconButton(
                        icon: const Icon(Icons.cameraswitch),
                        onPressed: _switchCamera,
                      ),
                    // 接続ボタン
                    ElevatedButton(
                      onPressed: isCallButtonEnabled
                          ? () {
                              changeCallState();
                            }
                          : null,
                      style: ButtonStyle(
                        backgroundColor: MaterialStateProperty.all(
                            callButtonBackgroundColor),
                      ),
                      child: Text(
                        callButtonText,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16.0,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    // ロカルvideo
                    if (isConnected)
                      Container(
                        padding: const EdgeInsets.all(1.0),
                        width: w * 0.5,
                        // // height: h * 1.9,
                        height: h * 0.23,
                        child: _buildLocalVideo()
                      )
                    else
                      Container(),
                  ],
                ),
              ),
              // Google map
              if (_hideRemoteVideo &&
                  _remotePeers.isNotEmpty &&
                  _googleMapConfig == '1')
                Expanded(
                  flex: 2,
                  child: Container(
                    padding: const EdgeInsets.all(1.0),
                    // width: w * 1.95,
                    // height: h * 0.48,
                    width: w * 1.95,
                    // height: screenSizeWidth < 600 ? h * 0.67 : h * 0.48,
                    height: screenSizeWidth < 600
                        ? h * 0.67
                        : (screenSizeWidth < 1000 ? h * 0.48 : h * 0.76),
                    child: GoogleMap(
                      onMapCreated: (GoogleMapController controller) {
                        mapController = controller;
                      },
                      initialCameraPosition: CameraPosition(
                        target: LatLng(userLat, userLng),
                        zoom: 15,
                      ),
                      markers: {
                        Marker(
                          markerId: const MarkerId('userMarker'),
                          position: LatLng(ownLat, ownLng),
                          infoWindow: const InfoWindow(title: '現在位置'),
                        ),
                        Marker(
                            markerId: const MarkerId('customUserMarker'),
                            position: LatLng(userLat, userLng),
                            infoWindow: const InfoWindow(title: '相手の現在位置'),
                            icon: BitmapDescriptor.fromBytes(customMarker)),
                      },
                    ),
                  ),
                )
              else
                // リモートVideo
                Expanded(
                  flex: 2,
                  child: Container(
                    padding: const EdgeInsets.all(1.0),
                    // width: w * 1.95,
                    // height: h * 0.48,
                    // height: screenSizeWidth < 600 ? h * 0.67 : h * 0.48,
                    height: screenSizeWidth < 600
                        ? h * 0.67
                        : (screenSizeWidth < 1000 ? h * 0.48 : h * 0.76),
                    child: Row(
                        children: _buildRemoteVideos(w * 1.3, screenSizeWidth < 600
                        ? h * 0.67
                        : (screenSizeWidth < 1000 ? h * 0.48 : h * 0.76),
                      ),
                    ),
                  ),
                )
            ],
          ),
        ),
      ],
    );
  }

  /// ローカル映像表示用widgetを生成
  Widget _buildLocalVideo() {
    if (Platform.isIOS) {
      return UiKitView(
        key: _localVideoKey,
        viewType: 'flutter_skyway/video_view',
        onPlatformViewCreated: _onLocalViewCreated,
      );
    } else if (Platform.isAndroid) {
      return SkywayCanvasView(
        key: _localVideoKey,
        onViewCreated: _onLocalViewCreated,
      );
    } else {
      throw UnsupportedError("unsupported platform");
    }

  }

  // リモート映像のグリッド表示用widgetを生成
  List<Widget> _buildRemoteVideos(double w, double h) {
    if (_remotePeers.isNotEmpty) {
      List<Widget> result = [];
      _remotePeers.forEach((key, value) {
        result.add(
          SizedBox(
            // height: h * 1.9,
            width: w,
            height: h,
            child: Column(
              children: [
                Expanded(
                  child: _createRemoteView(key),
                ),
              ],
            ),
          ),
        );
      });
      return result;
    } else {
      return [];
    }
  }

  /// リモート映像表示用widgetを生成
  Widget _createRemoteView(String remotePeerId) {
    if (Platform.isIOS) {
      return UiKitView(
        key: ValueKey('remoteVideo$remotePeerId'),
        viewType: 'flutter_skyway/video_view',
        onPlatformViewCreated: (id) {
          _onRemoteViewCreated(remotePeerId, id);
        },
      );
    } else if (Platform.isAndroid) {
      return SkywayCanvasView(
        key: ValueKey('remoteVideo$remotePeerId'),
        onViewCreated: (id) {
          _onRemoteViewCreated(remotePeerId, id);
        },
      );
    } else {
      throw UnsupportedError("unsupported platform");
    }
  }

//--------------------------------------------------------------------------------
  /// SharedPreferencesから前回の設定を読み込む
  void _loadPrefs() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    loginKengenKbn = prefs.getString('KENGEN') ?? '';
    loginUserNo = prefs.getInt('USERNO');
    _systemName = prefs.getString('SYSTEM-NAME') ?? '';
    _googleMapConfig = prefs.getString('MAP-CONFIG') ?? '';
    if(loginKengenKbn != '3'){  
        fetchAndSetUsers(widget.loginToken);
    }
  }

  Future<void> _showCallLog() async {
    DateTime endTime = DateTime.now();
    Duration timeDifference = endTime.difference(startTime!);
    String hour = timeDifference.inHours.toString().padLeft(2, "0");
    String inMinutes = timeDifference.inMinutes.toString().padLeft(2, "0");
    String inSeconds = timeDifference.inSeconds.toString().padLeft(2, "0");
    String totalCallDuration = '$hour:$inMinutes:$inSeconds';
    //診療時間
    Duration timeDifferenceDiagnosis = examEndTime!.difference(examStartTime!);
    String diagnosisHour =
        timeDifferenceDiagnosis.inHours.toString().padLeft(2, "0");
    String diagnosisMinutes =
        timeDifferenceDiagnosis.inMinutes.toString().padLeft(2, "0");
    String diagnosisSeconds =
        timeDifferenceDiagnosis.inSeconds.toString().padLeft(2, "0");
    String totalDiagnosisDuration =
        '$diagnosisHour:$diagnosisMinutes:$diagnosisSeconds';

    String formattedStartTime =
        DateFormat('yyyy/MM/dd HH:mm:ss').format(startTime!);
    String formattedDiagnosisStartTime =
        DateFormat('yyyy/MM/dd HH:mm:ss').format(examStartTime!);
    String formattedDiagnosisEndTime =
        DateFormat('yyyy/MM/dd HH:mm:ss').format(examEndTime!);
    String formattedEndTime = DateFormat('yyyy/MM/dd HH:mm:ss').format(endTime);

    String message = "接続開始時刻：$formattedStartTime";
    message += "\n診察開始時刻： $formattedDiagnosisStartTime";
    message += "\n診察終了時刻： $formattedDiagnosisEndTime";
    message += "\n診察時間： $totalDiagnosisDuration";
    message += "\n接続終了時刻： $formattedEndTime";
    message += "\n通話時間： $totalCallDuration";

    if(partnerUserNo != null || partnerMachineId != null){
      message += partnerUserNo != null ? ("\n対応端末ID：${partnerMachineId != "" ? partnerMachineId : "登録なし"}") : "";
    }
    // ログを追加
    await messageLog(endTime, widget.loginToken);
    setState(() {
      partnerUserNo = null;
      partnerMachineId = null;
      updateLogNo = null;
    });
    // ignore: use_build_context_synchronously
    showCustomAlertDialog(context, '情報', message);
  }


  /// 必要なパーミッション(CAMERA, RECORD_AUDIO)を保持しているかを
  /// 確認し保持していない場合にはパーミッションを要求する
  Future<void> checkPermission() async {
    // Request permissions
    Map<permission.Permission, permission.PermissionStatus> statuses = await [
      permission.Permission.camera,
      permission.Permission.microphone,
    ].request();
    // Now, check the permission status and set the state accordingly.
    if (statuses[permission.Permission.camera]!.isGranted && 
        statuses[permission.Permission.microphone]!.isGranted) {
      setState(() {
        cameraMicGranted = true;
      });
    }
  }

  Future<void> _connect() async {
    debugPrint("_connect:");
    await checkPermission();
    if(cameraMicGranted){
      if (_isConnecting) {
        return;
      }
      setState(() {
        _isConnecting = true;
      });

      SkywayPeer? peer;

      try {
        peer = await SkywayPeer.connect(
            _skyWayapiKey, _skyWaydomain, cameraMicGranted, _onSkywayEvent);
      } on PlatformException catch (e) {
        debugPrint('PlatformException error: $e');
      }

      setState(() {
        _isConnecting = false;
        _peer = peer;
      });
      // 接続開始時間
      startTime = DateTime.now();
      if(_googleMapConfig == '1'){
        await _checkLocationPermission();
      }
    }
    else{
      setState(() {
        callButtonBackgroundColor = const Color(0xFF00698D);
        callButtonText = '接続開始';
        callButtonState = 1;
      });
      endFlgUpdate(widget.loginToken, selectedRoomCd!);
      // ignore: use_build_context_synchronously
      showCustomAlertDialog(context, 'エラー', 'カメラ・マイクアクセスが禁止されています。カメラ・マイクを許可してください。');
    }
  }

  Future<void> _disconnect() async {
    debugPrint("_disconnect:");
    if (_peer != null) {
      await _peer!.disconnect();
    }
    setState(() {
      _peer = null;
      _hasLocalStream = false;
      _remotePeers.clear();
    });
  }

  // [OK]ボタンがあるAlertダイアログ
  void showCustomAlertDialog(BuildContext context, String title, String message) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close the dialog
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    ).then((value) {
    });
  }

  // [OK、Cancel]ボタンがあるAlertダイアログ
  void showCancelAlertDialog(BuildContext context, String title, String message) {
    showDialog(
      context: context,
      barrierDismissible: false, // 外部からの盗聴で解雇を阻止
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                setState(() {
                  _resetState();
                  _leaveRoom();
                  _disconnect();
                  endFlgUpdate(widget.loginToken, selectedRoomCd!);
                  Navigator.of(context).pop();
                  _showCallLog();
                 });
              },
              child: const Text('OK'),
            ),
             TextButton(
              onPressed: () {
                setState(() {
                  callButtonBackgroundColor = Colors.red;
                  callButtonText = '接続終了';
                  callButtonState = 4;
                  Navigator.of(context).pop(); 
                });
              },
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  // 最初の状況に戻る
  void _resetState() {
    setState(() {
      callButtonBackgroundColor = const Color(0xFF00698D);
      callButtonText = '接続開始';
      callButtonState = 1;
      shareScreenButtonText = '画面共有';
      screenShareBackgroundColor = const Color(0xFF00698D);
      shareScreenButtonState = 1;
      mapButtonState = 1;
      mapButtonText = 'マップ表示';
      mapButtonBackgroundColor = const Color(0xFF00698D);
      _hideRemoteVideo = false;
    });
  }

   // [Logout]ボタンAlertダイアログ
  void showLogoutAlertDialog(BuildContext context, String title, String message) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: <Widget>[
            TextButton(
              onPressed: () async {
                // Handle the "OK" button click as before
                _leaveRoom();
                _disconnect();
                endFlgUpdate(widget.loginToken, selectedRoomCd!);
                Navigator.of(context).pop();
                SharedPreferences pref = await SharedPreferences.getInstance();
                pref.remove('TOKEN');
                pref.remove('KENGEN');
                pref.remove('SYSTEM-NAME');
                pref.remove('MAP-CONFIG');
                dropdownValue = null;
                // ignore: use_build_context_synchronously
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const SelectorScreen(),
                  ),
                );
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    ).then((value) {
      //「OK」をクリックせずにダイアログが閉じられると
    });
  }

  // 選択したルームを設定
  Future<void> _setRoomName(String roomName, roomList) async {
    for (var room in roomList) {
      if (room.roomId == roomName) {
        selectedRoomCd = room.roomCD;
        break;
      }
    }
    setState(() {
      _roomName = roomName;
    });
  }

  // ルームに参加
  Future<void> _enter(String roomName) async {
    if (isConnected &&
        !isTalking &&
        !_isJoined &&
        (roomName.isNotEmpty)) {
      await _peer!.join(roomName, SkywayRoomMode.Mesh);
      setState(() {
        _isJoined = true;
      });
    }
  }

  Future<void> _leaveRoom() async {
    debugPrint("_leaveRoom:");
    if (_peer != null) {
      await _peer!.leave(_roomName);
    }
    setState(() {
      _remotePeers.clear();
      _isJoined = false;
    });
  }

  Future<void> _onLocalViewCreated(int id) async {
    localVideoId = id;
    if (isConnected && !_hasLocalStream) {
      await _peer!.startLocalStream(id);
    }
    setState(() {
      _hasLocalStream = true;
    });
    // ルーム名が既にセットされていれば入室する
    _enter(_roomName);
    // 回転画面のローカルビデオが停止するとビデオを再開
    if(isConnected && shareScreenButtonState != 2 ) _resumeLocalVideo();
    // // 回転画面のローカル画面キャプチャーが停止すると再開
    // if(isConnected && shareScreenButtonState == 2 ) {
    //   _stopScreenShare();
    //   _startScreenShare();
    // }
  }

  Future<void> _onRemoteViewCreated(String remotePeerId, int id) async {
    if (isTalking && _remotePeers.containsKey(remotePeerId)) {
      await _peer!.startRemoteStream(id, remotePeerId);
    }
    setState(() {
      _remotePeers[remotePeerId]!._hasRemoteStream = true;
    });
  }

//------------------------Skyway関係のイベントハンドラ----------------------------------
  void _onSkywayEvent(SkywayEvent event, Map<dynamic, dynamic> args) {
    switch (event) {
      case SkywayEvent.OnConnect:
        _onConnect(args['peerId']);
        break;
      case SkywayEvent.OnDisconnect:
        _onDisconnect(args['peerId']);
        break;
      case SkywayEvent.OnAddRemoteStream:
        _onAddRemoteStream(args['remotePeerId']);
        break;
      case SkywayEvent.OnRemoveRemoteStream:
        _onRemoveRemoteStream(args['remotePeerId']);
        break;
      case SkywayEvent.OnOpenRoom:
        _onOpenRoom(args['room']);
        break;
      case SkywayEvent.OnCloseRoom:
        _onCloseRoom(args['room']);
        break;
      case SkywayEvent.OnJoin:
        _onJoin(args['remotePeerId']);
        break;
      case SkywayEvent.OnData:
        _onData(args['data']);
        break;
      case SkywayEvent.OnLeave:
        _onLeave(args['remotePeerId']);
        break;
      case SkywayEvent.OnCall:
        // do nothing, never comes for p2p
        break;
    }
  }

  void _onConnect(String peerId) {
    debugPrint('_onConnect:peerId=$peerId');
  }

  void _onDisconnect(String peerId) {
    debugPrint('_onDisconnect:peerId=$peerId');
    setState(() {
      _isJoined = false;
    });
  }

  void _onAddRemoteStream(String remotePeerId) {
    debugPrint('_onAddRemoteStream:remotePeerId=$remotePeerId');
    setState(() {
      _remotePeers[remotePeerId] = RemotePeer();
    });
    _sendPartnerInfo();
  }

  void _onRemoveRemoteStream(String remotePeerId) {
    debugPrint('_onRemoveRemoteStream:remotePeerId=$remotePeerId');
    setState(() {
      _remotePeers.remove(remotePeerId);
      _resetState();
      _leaveRoom();
      _disconnect();
      _showCallLog();
      endFlgUpdate(widget.loginToken, selectedRoomCd!);
    });
  }

  void _onOpenRoom(String room) {
    debugPrint('_onOpenRoom:room=$room');
    setState(() {
      _isJoined = true;
    });
  }

  void _onCloseRoom(String room) {
    debugPrint('_onCloseRoom:room=$room');
    setState(() {
      _isJoined = false;
    });
  }

  void _onJoin(String remotePeerId) {
    debugPrint('_onJoin:remotePeerId=$remotePeerId');
  }

  void _onData(String data) async{
    debugPrint('_onData:msg=$data');
    // JSON Stringを解析してマップに変換する
    Map<String, dynamic> obj = json.decode(data);
    if(obj['startExam'] != null){
       setState(() {
        callButtonBackgroundColor = const Color(0xFF6c757d);
        callButtonText = '診察終了';
        callButtonState = 3;
        examStartTime = DateTime.now();
      });      
    }
    else if (obj['latLng'] != null) {
      debugPrint('latLng mapData: $data');
      setState(() {
        userLat = obj['latLng']['lat'];
        userLng = obj['latLng']['lng'];
      });
      // マップ作成後に初期化する
      if (mapButtonState == 2) {
        await _updateCameraPosition();
      }
    }
    else if(obj['endExam'] != null){
       setState(() {
        isCallButtonEnabled = true;
        callButtonBackgroundColor = Colors.red;
        callButtonText = '接続終了';
        callButtonState = 4;
        examEndTime = DateTime.now();
       });
    }
    else if (obj['sendPartnerInfo'] != null) {
      debugPrint('sendPartnerInfo: $data');
      setState(() {
        partnerUserNo =  obj['userData']['userNo'];
        partnerMachineId = obj['userData']['machineId'];
      });
    }
    
  }

  void _onLeave(String remotePeerId) {
    debugPrint('_onLeave:remotePeerId=$remotePeerId');
  }

//--------------------------------CALL API-----------------------------------------------
  // loadSkywayAPIKey
  Future<void> loadSkywayAPIKey(String loginToken) async {
    Map<String, String> headers = {
      "Content-Type": "application/json",
      'Accept': 'application/json',
      "Authorization": "Bearer $loginToken"
    };

    var response = await http.get(Uri.parse("$baseUrl/User/SkywayAPIKey/"), headers: headers);
    if (response.statusCode == 200) {
      var decodedData = jsonDecode(response.body);
      var key = decodedData['key'];
      debugPrint('loadSkywayAPIKey : $key');
      setState(() {
        _skyWayapiKey = key;
      });
    } else {
      debugPrint('Failed to loadSkywayAPIKey');
    }
  }

  // 使用可能なルームのリストを取得
  Future<SkywayRoom> fetchRoom(String loginToken) async {
    Map<String, String> headers = {
      "Content-Type": "application/json",
      'Accept': 'application/json',
      "Authorization": "Bearer $loginToken"
    };
    var response = await http.get(Uri.parse("$baseUrl/Room/CanUseList/"), headers: headers);
    if (response.statusCode == 200) {
      var decodedData = jsonDecode(response.body);
      if(loginKengenKbn == '3'){
        selectedRoomCd = decodedData['roomList'][0]['roomCD'];
        getRoomConnectionStatus(widget.loginToken, selectedRoomCd!);
      }
      else{
        if(decodedData['roomList'].length == 1){
           selectedRoomCd = decodedData['roomList'][0]['roomCD'];
        }
        else{
          loadMyRoom(loginToken);
        }
      }
      return SkywayRoom.fromJson(decodedData);
    } else {
      // then throw an exception.
      throw Exception('Failed to load SkywayRoom');
    }
  }

  // 自分のルームを取得
  Future<void> loadMyRoom(String loginToken) async {
    Map<String, String> headers = {
      "Content-Type": "application/json",
      'Accept': 'application/json',
      "Authorization": "Bearer $loginToken"
    };

    var response = await http.get(Uri.parse("$baseUrl/User/MyRoomNo/"), headers: headers);
    if (response.statusCode == 200) {
      debugPrint('My Room No : $response.body');
      var decodedData = jsonDecode(response.body);
        selectedRoomCd = decodedData['myRoomNo'];
        for (var room in roomDataList) {
          if (room.roomCD == selectedRoomCd) {
            dropdownValue = room.roomId;
            setState(() {
              _roomName = room.roomId;
            });
            break;
          }
        }
    } else {
      debugPrint('Failed to loadMyRoom');
    }
  }

  // ルーム作成・接続を作成
  Future<void> createConnection(String loginToken, String roomNo, int waitUser) async {
    final response = await http.post(
      Uri.parse("$baseUrl/Room/CreateConnection"),
      headers: <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $loginToken',
      },
      body: jsonEncode(<String, dynamic>{
        'roomNo': roomNo,
        'waitUserNo': waitUser,
      }),
    );
    if (response.statusCode == 200) {
      debugPrint("sucess: $response");
       setState(() {
        newConnectionNo = newConnectionNo! + 1;
      });
    // ルーム作成後に接続する
    _connect();
    } else {
      debugPrint('createConnection failed');
    }
  }

  // 自分の情報を取得
  Future<void> loadMyInfo(String loginToken) async {
    Map<String, String> headers = {
      "Content-Type": "application/json",
      'Accept': 'application/json',
      "Authorization": "Bearer $loginToken"
    };
    var response = await http.get(
        Uri.parse('$baseUrl/User/MyInfo/'),
        headers: headers);
    if (response.statusCode == 200) {
      var list = response.body;
      debugPrint('loadMyInfo: $list');
      var decodedData = jsonDecode(response.body);
      setState(() {
        myUserNo = decodedData['userNo'];
        machineId = decodedData['machineId'];
        tantoNo = decodedData['tantoNo'];
      });
    } else {
      debugPrint('loadMyInfo failed');
    }
  }

  // 接続したいルームの状況を取得
  Future<void> getRoomConnectionStatus(String loginToken, String roomNo) async {
    Map<String, String> headers = {
      "Content-Type": "application/json",
      'Accept': 'application/json',
      "Authorization": "Bearer $loginToken"
    };
    var response = await http.get(
        Uri.parse('$baseUrl/Room/SetRoomConnection?roomNo=$roomNo'),
        headers: headers);
    if (response.statusCode == 200) {
      var list = response.body;
      debugPrint(list);
      var decodedData = jsonDecode(response.body);
      setState(() {
        newConnectionNo = decodedData['roomList'][0]['connectionNo'];
        waitUserNo = decodedData['roomList'][0]['waitUserNo'];
        secondUserNo = decodedData['roomList'][0]['secondUserNo'];
        _endFlg = decodedData['roomList'][0]['endFlg'];
      });

      if (loginKengenKbn == '3') {
        if (_endFlg == true) {
          // ignore: use_build_context_synchronously
          showCustomAlertDialog(
              context, '情報', 'このルームは現在使用できません。医師からの連絡をお待ちください。');
        } else if (secondUserNo != null) {
          // ignore: use_build_context_synchronously
          showCustomAlertDialog(
              context, 'エラー', 'すでに二人がこのルームを利用しています。別のルームを選択するか、担当者に連絡してください。');
        } else {
          // 接続状況を更新
          connectionUpdate(widget.loginToken, selectedRoomCd!, loginUserNo!);
          _connect();
          setState(() {
            isCallButtonEnabled = false;
            callButtonBackgroundColor = const Color(0xFF28a745);
            callButtonText = '診察開始';
            callButtonState = 2;
          });
        }
      } else {
        if (_endFlg == false) {
          if(loginUserNo == waitUserNo){
             callCreateConnection(waitUserNo);
              setState(() {
                callButtonBackgroundColor = const Color(0xFF28a745);
                callButtonText = '診察開始';
                callButtonState = 2;
              });
          }
          else{
            // ignore: use_build_context_synchronously
            showCustomAlertDialog(context, 'エラー', '現在このルームは使用しています。');
          }
        } else {
          if (dropdownValue == null) {
            // ignore: use_build_context_synchronously
            showCustomAlertDialog(context, 'エラー', 'ルームを選択してください。');
          } else {
            if (userList.isNotEmpty) {
              showButtonMenu();
            }
          }
        }
      }
    } else {
      debugPrint('getRoomConnectionStatus failed');
    }
  }

  // 接続を閉じる時endFlgはFalse更新
  Future<void> connectionUpdate(
      String loginToken, String roomCd, int userId) async {
    final response = await http.post(
      Uri.parse("$baseUrl/Room/ConnectionSecondUserUpdate"),
      headers: <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $loginToken',
      },
      body: jsonEncode(<dynamic, dynamic>{
        'connectionNo': newConnectionNo,
        'roomNo': roomCd,
        'secondUserNo': userId,
        'endFlg': false,
      }),
    );

    if (response.statusCode == 200) {
      debugPrint('connectionUpdate sucess: $response');
    } else {
      debugPrint('getRoomConnectionStatus failed');
    }
  }

  // データベースのconnectionテーブルの完了フラグを更新する
  Future<void> endFlgUpdate(
      String loginToken, String roomCd) async {
    final response = await http.post(
      Uri.parse("$baseUrl/Room/ConnectionEndFlgUpdate"),
      headers: <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $loginToken',
      },
      body: jsonEncode(<dynamic, dynamic>{
        'connectionNo': newConnectionNo,
        'roomNo': roomCd,
        'endFlg': true,
      }),
    );
    if (response.statusCode == 200) {
      debugPrint("endFlgUpdate: true");
    } else {
      debugPrint("failed to endFlgUpdate");
    }
  }

  // ユーザーのリストを取得する
  Future<List<User>> fetchUsers(String loginToken) async {
    Map<String, String> headers = {
      "Content-Type": "application/json",
      'Accept': 'application/json',
      "Authorization": "Bearer $loginToken"
    };
    var response =
        await http.get(Uri.parse('$baseUrl/User/List/'), headers: headers);

    if (response.statusCode == 200) {
      var decodedData = json.decode(response.body);
      final List<dynamic> data = decodedData['userList'];
      // delFlg・loginUserNo を使用してユーザーをfilterする
      final List<User> users = data
          .where((userJson) => userJson['delFlg'] == false &&  userJson['userNo'] != loginUserNo)
          .map((userJson) => User.fromJson(userJson))
          .toList();
      return users;
    } else {
      throw Exception('Failed to load users');
    }
  }

  // ログを追加
  Future<void> messageLog(DateTime endTime, String loginToken) async {
    // DateTime UTC タイムゾーンに変換
    DateTime examStartTimeInUtc = examStartTime!.toUtc();
    DateTime examEndTimeInUtc = examEndTime!.toUtc();
    DateTime startTimeInUtc = startTime!.toUtc();
    DateTime endTimeInUtc = endTime.toUtc();

    final response = await http.post(
      Uri.parse("$baseUrl/User/MeLog"),
      headers: <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $loginToken',
      },
      body: jsonEncode(<String, dynamic>{
      'logNo': updateLogNo,
      'partnerUserNo': partnerUserNo,
      'examinationStartTime': DateFormat('yyyy-MM-ddTHH:mm:ss').format(examStartTimeInUtc),
      'examinationEndTime': DateFormat('yyyy-MM-ddTHH:mm:ss').format(examEndTimeInUtc),
      'startTime': DateFormat('yyyy-MM-ddTHH:mm:ss').format(startTimeInUtc),
      'endTime': DateFormat('yyyy-MM-ddTHH:mm:ss').format(endTimeInUtc),
    }),
    );
    if (response.statusCode == 200) {
      debugPrint("sucess: $response");
      var decodedData = json.decode(response.body);
      setState(() {
        updateLogNo = decodedData['logNo'];
      });
     
    } else {
      debugPrint('messageLog save failed');
    }
  }

  // ユーザーをリストに追加
  Future<void> fetchAndSetUsers(String loginToken) async {
    try {
      final users = await fetchUsers(loginToken);
      setState(() {
        userList.clear();
        userList.addAll(users);
      });
    } catch (error) {
      debugPrint('Error fetching users: $error');
    }
  }


//--------------------------------------------------------------------------------
  // 接続ボタンの状態
  void changeCallState() async{
      switch (callButtonState) {
        case 1:
          await getRoomConnectionStatus(widget.loginToken, selectedRoomCd!);
          break;
        case 2:
          setState(() {
            callButtonBackgroundColor = const Color(0xFF6c757d);
            callButtonText = '診察終了';
            callButtonState = 3;
           });
          _examStart();
          break;
        case 3:
          setState(() {
            callButtonBackgroundColor = Colors.red;
            callButtonText = '接続終了';
            callButtonState = 4;
          });
          _examEnd();
          break;
        case 4:
          _endCall();
          break;
      }
  }

  // マップボタンの状態
  void changeMapButtonState() {
    setState(() {
      switch (mapButtonState) {
        case 1:
          _hideRemoteVideo = true;
          mapButtonBackgroundColor = Colors.red;
          mapButtonText = 'マップ非表示';
          mapButtonState = 2;
          break;
        case 2:
          _hideRemoteVideo = false;
          mapButtonBackgroundColor = const Color(0xFF00698D);
          mapButtonText = 'マップ表示'; 
          mapButtonState = 1;
          break;
        default:
          break;
      }
    });
  }

  // 画面共有ボタンの状態
  void changeScreenShareState() {
    setState(() {
      switch (shareScreenButtonState) {
        case 1:
          _startScreenShare();
          screenShareBackgroundColor = Colors.red;
          shareScreenButtonText = '画面共有停止';
          shareScreenButtonState = 2;
          break;
        case 2:
          _stopScreenShare();
          screenShareBackgroundColor = const Color(0xFF00698D);
          shareScreenButtonText = '画面共有'; 
          shareScreenButtonState = 1;
          break;
        default:
          break;
      }
    });
  }

  void _startScreenShare() async{
    await _peer!.startForegroundService(localVideoId!);
    // Foreground サービスを開始ために3秒待つ
    Future.delayed(const Duration(seconds: 3), () async{
        debugPrint('_startScreenShare  function called.');
        bool isStartCapture = await _peer!.startCaptureStream(localVideoId!);
        if(!isStartCapture){
          setState(() {
            screenShareBackgroundColor = const Color(0xFF00698D);
            shareScreenButtonText = '画面共有'; 
            shareScreenButtonState = 1;
          });
          // ignore: use_build_context_synchronously
          showCustomAlertDialog(context, 'エラー', 'コンテンツのキャプチャーを許可してください。');
        }
    });
  
  }

  void _stopScreenShare() async{
    debugPrint('_stopScreenShare  function called.');
    await _peer!.stopCaptureStream(localVideoId!);
  }

  void _examStart() {
    setState(() {
      examStartTime = DateTime.now();
    });
    _sendExamStartData();
  }

  void _examEnd() {
    setState(() {
      examEndTime = DateTime.now();
    });
    _sendExamEndData();
  }

  void _endCall() async{
    showCancelAlertDialog(context, '確認', '接続を終了します。よろしいですか？');
  }

  // ポップアップメニューを表示する
  void showButtonMenu() {
    final RenderBox button =
        _popupMenuKey.currentContext!.findRenderObject() as RenderBox;
    final RenderBox overlay =
        Overlay.of(context)?.context.findRenderObject() as RenderBox;
    
    // Position the top-left corner of the menu at the top-left corner of the button
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(const Offset(0, 0), ancestor: overlay),
        button.localToGlobal(button.size.bottomRight(const Offset(0, 0)), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );

    showMenu<User>(
      context: context,
      position: position,
      items: userList.map((User user) {
        return PopupMenuItem<User>(
          value: User(
              userName: user.userName,
              userNo: user.userNo),
          child: Text(user.userName),
        );
      }).toList(),
    ).then<void>((User? newValue) async {
      if (newValue != null) {
        callCreateConnection(newValue.userNo);
        setState(() {
          callButtonBackgroundColor = const Color(0xFF28a745);
          callButtonText = '診察開始';
          callButtonState = 2;
        });
      }
    });
  }

  void _sendExamStartData() async{
    Map<String, dynamic> examFlg = {
      "exam": true,
      "startExam": true,
    };
    String jsonStringExamFlg = jsonEncode(examFlg);
    if(_hasLocalStream){
      await _peer!.sendData(localVideoId!, jsonStringExamFlg);
    }
  }

  void _sendPartnerInfo() async{
    Map<String, dynamic> partnerInfo = {
      "sendPartnerInfo": true,
      "userData": {
        "userNo": myUserNo,
        "machineId": machineId
      },
      "roomData": {
        "isExaminationStarted": false
      }
    };
    String jsonStringPartnerInfo = jsonEncode(partnerInfo);
    if(_peer != null){
      await _peer!.sendData(localVideoId!, jsonStringPartnerInfo);
      debugPrint("_sendPartnerInfo:$jsonStringPartnerInfo");
    }
  }

  void _sendExamEndData() async{
    Map<String, dynamic> examFlg = {
      "exam": true,
      "endExam": true,
    };
    String jsonStringExamFlg = jsonEncode(examFlg);
    if(_hasLocalStream){
      await _peer!.sendData(localVideoId!, jsonStringExamFlg);
    }
  }

  void callCreateConnection(userNo){
    if(loginKengenKbn != '3' && userNo != null){
      createConnection(widget.loginToken, selectedRoomCd!, userNo);
    }
  }

  /// Logoutボタン
  void onLogout() async {
    if(_hasLocalStream){
      // ignore: use_build_context_synchronously
      showLogoutAlertDialog(context, '確認', '診察を停止します。よろしいでしょうか？');
    }
    else{
      SharedPreferences pref = await SharedPreferences.getInstance();
      pref.remove('TOKEN');
      pref.remove('KENGEN');
      pref.remove('SYSTEM-NAME');
      pref.remove('MAP-CONFIG');
      dropdownValue = null;
      // ignore: use_build_context_synchronously
      Navigator.push(
        context,
        MaterialPageRoute(
            builder: (context) => const SelectorScreen()),
      );
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  void didUpdateWidget(CallP2pMeshScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
  }

}
