import 'dart:io';
import 'dart:math';
import 'package:camera/camera.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:ocr_canner/RecognizerScreen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  CameraController? _controller;
  List<CameraDescription>? cameras;
  late ImagePicker imagePicker;

  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    imagePicker = ImagePicker();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    cameras = await availableCameras();
    if (cameras!.isNotEmpty) {
      _controller = CameraController(
        cameras![0],
        ResolutionPreset.high,
      );
      await _controller!.initialize();
      await _controller!.lockCaptureOrientation(DeviceOrientation.portraitUp); // Verrouille en portrait
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _captureAndNavigate() async {
    if (_controller != null && _controller!.value.isInitialized) {
      XFile? xfile = await _controller!.takePicture();
      if (xfile != null) {
        File image = File(xfile.path);
        Navigator.push(context, MaterialPageRoute(builder: (ctx) {
          return Recognizerscreen(image);
        }));
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;
    double screenHeight = MediaQuery.of(context).size.height;
    double cameraHeight = screenHeight - 190;  // Ajuste la hauteur de la caméra pour remplir l'espace noir

    return Container(
      color: Colors.white,
      padding: EdgeInsets.only(top: 50, bottom: 15, left: 5, right: 5),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [

          Card(   // Carte contenant la caméra
            color: Colors.white,
            child: Container(
              height: cameraHeight,
              width: screenWidth,
              padding: EdgeInsets.only(top: 50, bottom: 15, left: 0, right: 0),
              child: _controller != null && _controller!.value.isInitialized
                  ? ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: AspectRatio(
                  aspectRatio: 9 / 16, // Forcer le ratio 9:16
                  child: FittedBox(
                    fit: BoxFit.cover,
                    child: Transform.rotate(
                      angle: pi /2,
                      child: SizedBox(
                        width: _controller!.value.previewSize!.width,
                        height: (_controller!.value.previewSize!.height.ceilToDouble()),
                        child: CameraPreview(_controller!),
                      ),
                    ),
                  ),
                ),
              )
                  : Center(child: CircularProgressIndicator()),
            ),
          ),
          Card(  // Carte avec les boutons pour prendre la photo ou en choisir une
            color: Colors.blueAccent,
            child: Container(
              height: 100,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  InkWell(
                    child: const Icon(
                      Icons.rotate_left,
                      size: 35,
                      color: Colors.white,
                    ),
                    onTap: () {},
                  ),
                  InkWell(
                    onTap: _captureAndNavigate,
                    child: const Icon(
                      Icons.camera,
                      size: 50,
                      color: Colors.white,
                    ),
                  ),
                  InkWell(
                    child: const Icon(
                      Icons.image_outlined,
                      size: 35,
                      color: Colors.white,
                    ),
                    onTap: () async {
                      XFile? xfile = await imagePicker.pickImage(
                          source: ImageSource.gallery);
                      if (xfile != null) {
                        File image = File(xfile.path);
                        Navigator.push(context,
                            MaterialPageRoute(builder: (ctx) {
                          return Recognizerscreen(image);
                        }));
                      }
                    },
                  )
                ],
              ),
            ),
          )
        ],
      ),
    );
  }
}
