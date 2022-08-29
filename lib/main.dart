import 'package:flutter/material.dart';
import 'package:flutter_blue/flutter_blue.dart';

void main() => runApp(const BlueWeightScannerApp());

class BlueWeightScannerApp extends StatelessWidget {
  const BlueWeightScannerApp({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      color: Colors.lightBlue,
      home: StreamBuilder<BluetoothState>(
          stream: FlutterBlue.instance.state,
          initialData: BluetoothState.unknown,
          builder: (_, snapshot) {
            final state = snapshot.data;
            return state == BluetoothState.on
                ? FindDeviceScreen()
                : BluetoothOffScreen(state: state);
          }),
    );
  }
}

class BluetoothOffScreen extends StatelessWidget {
  const BluetoothOffScreen({Key? key, this.state}) : super(key: key);

  final BluetoothState? state;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.lightBlue,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.bluetooth_disabled,
              size: 200.0,
              color: Colors.white54,
            ),
            Text(
              'Bluetooth Adapter is ${state != null ? state.toString().substring(15) : 'not available'}.',
              style: Theme.of(context)
                  .primaryTextTheme
                  .subtitle1
                  ?.copyWith(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}

class FindDeviceScreen extends StatelessWidget {
  FindDeviceScreen({Key? key}) : super(key: key);

  final GlobalKey<RefreshIndicatorState> _refreshIndicatorKey =
      GlobalKey<RefreshIndicatorState>();

  @override
  Widget build(BuildContext context) {
    double height =
        MediaQuery.of(context).size.height; // Full screen width and height
    EdgeInsets padding =
        MediaQuery.of(context).padding; // Height (without SafeArea)
    double netHeight = height -
        padding.top -
        kToolbarHeight; // Height (without status and toolbar)
    return Scaffold(
      appBar: AppBar(
        title: const Text('BlueWeight Scanner'),
      ),
      body: RefreshIndicator(
        key: _refreshIndicatorKey,
        color: Colors.white,
        backgroundColor: Colors.lightBlue,
        strokeWidth: 4.0,
        onRefresh: () async =>
            FlutterBlue.instance.startScan(timeout: const Duration(seconds: 4)),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: StreamBuilder<List<ScanResult>>(
              stream: FlutterBlue.instance.scanResults,
              initialData: const [],
              builder: (c, snapshot) {
                if (snapshot.hasData) {
                  return snapshot.data!.isEmpty
                      ? Container(
                          child: const ListTile(title: Text('waiting')),
                          height: netHeight,
                        )
                      : Container(
                          height: netHeight,
                          child: Column(
                              children: snapshot.data!
                                  .map((r) => ListTile(
                                        title: Text(r.device.name),
                                        trailing: ElevatedButton(
                                          child: const Text('CONNECT'),
                                          onPressed: (r.advertisementData
                                                  .connectable)
                                              ? () => Navigator.of(context)
                                                      .push(MaterialPageRoute(
                                                          builder: (context) {
                                                    return DeviceScreen(
                                                        device: r.device);
                                                  }))
                                              : null,
                                        ),
                                      ))
                                  .toList()),
                        );
                }
                return Container(
                    width: double.infinity,
                    height: double.infinity,
                    alignment: Alignment.center,
                    child: const Text(
                      'Wait',
                      textAlign: TextAlign.center,
                    ));
              }),
        ),
      ),
    );
  }
}

class DeviceScreen extends StatefulWidget {
  const DeviceScreen({Key? key, required this.device}) : super(key: key);
  final BluetoothDevice device;

  @override
  DeviceScreenState createState() => DeviceScreenState();
}

class DeviceScreenState extends State<DeviceScreen> {
  bool isConnected = false;
  bool isDiscoveredValue = false;
  List<BluetoothService>? services;
  late BluetoothDevice device;
  String? weightValue;
  late BluetoothCharacteristic char;

  @override
  void initState() {
    super.initState();
    device = widget.device;
    connectToDevice();
  }

  @override
  void dispose() {
    super.dispose();
    disconnectFromDevice();
  }

  connectToDevice() async {
    device.state.listen((state) async {
      if (state == BluetoothDeviceState.disconnected) {
        await device.connect();
        setState(() => isConnected = true);
      }
    });
  }

  void disconnectFromDevice() {
    device.state.listen((state) {
      if (state == BluetoothDeviceState.connected) {
        device.disconnect();
      }
    });
  }

  discoverServices() async {
    if (services == null) {
      services = await device.discoverServices();
      for (BluetoothService service in services!) {
        if (service.uuid.toString().toUpperCase().substring(4, 8) == 'FEE7') {
          for (BluetoothCharacteristic characteristic
              in service.characteristics) {
            if (characteristic.uuid.toString().toUpperCase().substring(4, 8) ==
                'FEC8') {
              char = characteristic;
              break;
            }
          }
          break;
        }
      }
    }
    await char.setNotifyValue(true);
  }

  measureValue() {
    char.value.listen((c) async {
      weightValue = String.fromCharCodes(c);
      if (weightValue?.contains('ST') ?? false) {
        isDiscoveredValue = true;
        await char.setNotifyValue(false);
        setState(() {
          Navigator.of(context).pop();
          isDiscoveredValue = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
            '${device.name}: ${isConnected ? "connected" : "disconnected"}'),
      ),
      body: Column(children: <Widget>[
        Container(
          alignment: Alignment.center,
          child: Text(
            weightValue ?? 'Scan to obtain value',
            textAlign: TextAlign.center,
          ),
        ),
      ]),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.search),
        onPressed: () async {
          if (isConnected) {
            showDialog(
              barrierDismissible: false,
              context: context,
              builder: (BuildContext context) {
                return AlertDialog(
                  backgroundColor: Colors.transparent,
                  content: Row(children: const [
                    Center(child: CircularProgressIndicator())
                  ]),
                );
              },
            );
            await discoverServices();
            measureValue();
          }
        },
      ),
    );
  }
}
