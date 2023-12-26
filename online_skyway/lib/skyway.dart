import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

/// MainActivityで実装するメソッドチャネル名
const String _METHOD_CHANNEL_NAME = "com.serenegiant.flutter.skyway/method";

/// 各ピア接続毎にFlutterSkywayPeerで実装するメソッドチャネルの～ベス名(実際には_$peerIdでポストフィックス)
const String _PEER_EVENT_CHANNEL_NAME = "com.serenegiant.flutter.skyway/event";

enum SkywayEvent {
  /// ピア接続した
  OnConnect,

  /// ピア接続が切断された
  OnDisconnect,

  /// p2pで着呼した
  OnCall,

  /// リモート映像用のメディアストリームが追加された
  OnAddRemoteStream,

  /// リモート映像用のメディアストリームが削除された
  OnRemoveRemoteStream,

  /// SFUまたはMeshルームをオープンした(自分が入室した)
  OnOpenRoom,

  /// SFUまたはMeshルームをオープンした(自分が退室した)
  OnCloseRoom,

  /// SFU/Mesh接続で誰かががルームに入室した
  OnJoin,

  /// SFU/Mesh接続で誰かががルームにデータ送信
  OnData,

  /// SFU/Mesh接続で誰かががルームから退室した
  OnLeave,
}

enum SkywayRoomMode {
  Mesh
}

typedef OnSkywayEventCallback = void Function(
    SkywayEvent event, Map<dynamic, dynamic> args);

/// プラットフォーム側のskyway関係の処理へアクセスするためのメソッドチャネル
final MethodChannel _channel = const MethodChannel(_METHOD_CHANNEL_NAME);



/// Skyway関係のプラットフォーム側実装へアクセスするためのラッパークラス
class SkywayPeer {
  /// インスタンス生成のためのヘルパー関数
  /// @param apiKey
  /// @param domain
  /// @param onCall リモート側から着呼したときのコールバック
  static Future<SkywayPeer?> connect(
      String apiKey, String domain, bool cameraMicGranted, OnSkywayEventCallback onEvent) async {
    print("connect:");
    assert(onEvent != null);
    if (cameraMicGranted) {
      final String peerId = await _channel.invokeMethod('connect', {
        'apiKey': apiKey,
        'domain': domain,
      });
      print('peerId: $peerId');
      return SkywayPeer._internal(peerId: peerId, onEvent: onEvent)
        .._initialize();
    } else {
      return null;
    }
  }

//--------------------------------------------------------------------------------
  final String peerId;
  final OnSkywayEventCallback onEvent;
  StreamSubscription<dynamic> _eventSubscription;

  /// 内部使用のコンストラクタ
  // SkywayPeer._internal({required this.peerId, required this.onEvent})
  // : assert(onEvent != null);
  SkywayPeer._internal({
    required this.peerId,
    required this.onEvent,
  }) : _eventSubscription = StreamController<dynamic>().stream.listen((_) {});

  /// ピア接続を切断し関係するリソースを開放する
  Future<void> disconnect() async {
    debugPrint("destroy:");
    _eventSubscription.cancel();
    return await _channel.invokeMethod('disconnect', {
      'peerId': peerId,
    });
  }

  /// 画面共有映像停止
  Future<void> stopCaptureStream(int localVideoId) async {
    debugPrint("stopCaptureStream:");
    return await _channel.invokeMethod('stopCaptureStream', {
      'peerId': peerId,
      'localVideoId': localVideoId,
    });
  }

  /// 同じskywayのアプリケーションに接続しているピア一覧を取得する
  /// Note: skywayのアプリケーションの設定で一覧取得を有効にしている場合のみ使用可能
  Future<List<String>> listAllPeers() async {
    debugPrint("listAllPeers:");
    List<dynamic> peers = await _channel.invokeMethod('listAllPeers', {
      'peerId': peerId,
    });
    return peers.cast<String>();
  }

  /// ローカル映像の取得開始
  Future<void> startLocalStream(int localVideoId) async {
    debugPrint("startLocalStream:");
    return await _channel.invokeMethod('startLocalStream', {
      'peerId': peerId,
      'localVideoId': localVideoId,
    });
  }

  /// データ送信
  Future<bool> sendData(int localVideoId, String data) async {
    debugPrint("sendData: $data");
    bool isSendData = await _channel.invokeMethod('sendData', {
      'peerId': peerId,
      'localVideoId': localVideoId,
      "data": data,
    });
    return isSendData;
  }

  /// foreground サービス開始
  Future<void> startForegroundService(int localVideoId) async {
    debugPrint("startForegroundService:");
    return await _channel.invokeMethod('startForegroundService', {
      'peerId': peerId,
      'localVideoId': localVideoId,
    });
  }

  /// 画面共有映像の取得開始
  Future<bool> startCaptureStream(int localVideoId) async {
    debugPrint("startCaptureStream:");
    bool isStartCapture = await _channel.invokeMethod('startCaptureStream', {
      'peerId': peerId,
      'localVideoId': localVideoId,
    });
    return isStartCapture;
  }

  /// 回転画面のローカルビデオが停止するとビデオを再開
  Future<void> resumeCaptureStream(int localVideoId) async {
    debugPrint("resumeCaptureStream:");
    await _channel.invokeMethod('resumeCaptureStream', {
      'peerId': peerId,
      'localVideoId': localVideoId,
    });
  }

  /// キャメラ切り替え
  Future<bool> switchCameraStream(int localVideoId) async {
    debugPrint("switchCameraStream:");
    bool isSwitchCamera = await _channel.invokeMethod('switchCameraStream', {
      'peerId': peerId,
      'localVideoId': localVideoId,
    });
    return isSwitchCamera;
  }

  /// リモート映像の取得開始
  Future<void> startRemoteStream(int remoteVideoId, String targetPeerId) async {
    debugPrint("startRemoteStream:");
    return await _channel.invokeMethod('startRemoteStream', {
      'peerId': peerId,
      'remoteVideoId': remoteVideoId,
      'remotePeerId': targetPeerId,
    });
  }

  /// 通話を終了(ローカル映像の取得とピア接続自体は有効なまま)
  Future<void> hangUp() async {
    debugPrint("hangUp:");
    return await _channel.invokeMethod('hangUp', {
      'peerId': peerId,
    });
  }

  /// p2p接続開始
  Future<void> call(String targetPeerId) async {
    debugPrint("call:");
    return await _channel.invokeMethod('call', {
      'peerId': peerId,
      'remotePeerId': targetPeerId,
    });
  }

  /// 接続開始
  Future<void> join(String room, SkywayRoomMode mode) async {
    debugPrint("join:room=$room,mode=$mode");
    return await _channel.invokeMethod('join', {
      'peerId': peerId,
      'room': room,
      "mode": mode.index,
    });
  }

  /// 接続開始
  Future<void> leave(String room) async {
    debugPrint("leave:");
    return await _channel.invokeMethod('leave', {
      'peerId': peerId,
      'room': room,
    });
  }

  /// 着呼したときに着信を許可するときの処理
  Future<void> accept(String remotePeerId) async {
    debugPrint("accept:");
    return await _channel.invokeMethod('accept', {
      'peerId': peerId,
      'remotePeerId': remotePeerId,
    });
  }

  /// 着袴したときに着信を拒否するときの処理
  Future<void> reject(String remotePeerId) async {
    debugPrint("reject:");
    return await _channel.invokeMethod('reject', {
      'peerId': peerId,
      'remotePeerId': remotePeerId,
    });
  }

//--------------------------------------------------------------------------------
  /// 初期化処理
  void _initialize() {
    debugPrint("initialize:peerId=$peerId");
    _eventSubscription = EventChannel(_PEER_EVENT_CHANNEL_NAME + '_$peerId')
        .receiveBroadcastStream()
        .listen(_eventListener, onError: _errorListener);
  }

  /// イベントチャネルでイベントを受信したときの処理
  void _eventListener(dynamic event) {
    debugPrint("_eventListener:$event");
    final Map<dynamic, dynamic> args = event;

    String _event = args['event'];
    if (peerId == args['peerId']) {
      switch (_event) {
        case 'OnConnect': // ピア接続した
          onEvent(SkywayEvent.OnConnect, args);
          break;
        case 'OnDisconnect': // ピア接続が切断された
          onEvent(SkywayEvent.OnDisconnect, args);
          break;
        case 'OnCall': //  p2pで着呼した
          onEvent(SkywayEvent.OnCall, args);
          break;
        case 'OnAddRemoteStream': // リモート映像のMediaStreamを受信した
          onEvent(SkywayEvent.OnAddRemoteStream, args);
          break;
        case 'OnRemoveRemoteStream': // リモート映像のMediaStreamが削除された
          onEvent(SkywayEvent.OnRemoveRemoteStream, args);
          break;
        case 'OnOpenRoom': // SFUまたはMeshルームをオープンした(自分が入室した)
          onEvent(SkywayEvent.OnOpenRoom, args);
          break;
        case 'OnCloseRoom': // SFUまたはMeshルームをオープンした(自分が退室した)
          onEvent(SkywayEvent.OnCloseRoom, args);
          break;
        case 'OnJoin': // SFU/Mesh接続で誰かががルームにデータ送信
          onEvent(SkywayEvent.OnJoin, args);
          break;
        case 'OnData': // SFU/Mesh接続で誰かががルームに入室した
          onEvent(SkywayEvent.OnData, args);
          break;
        case 'OnLeave': // SFU/Mesh接続で誰かががルームから退室した
          onEvent(SkywayEvent.OnLeave, args);
          break;
        default:
          debugPrint('unknown event($_event),args=$args');
          break;
      }
    } else {
      debugPrint('Unexpected peer id');
    }
  }

  /// イベントチャネルでエラーが発生したときの処理
  void _errorListener(Object obj) {
    debugPrint("_eventListener:$obj");
    debugPrint('onError: $obj');
  }
}
