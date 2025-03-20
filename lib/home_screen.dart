import 'dart:io';
import 'dart:math';
import 'package:camera/camera.dart';
import 'torch_helper.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:ocr_canner/recognizer_cin.dart';
import 'package:ocr_canner/recognizer_passport.dart';
import 'package:image/image.dart' as image_package;
import 'package:sensors_plus/sensors_plus.dart';





class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}



class _HomeScreenState extends State<HomeScreen>  {
  CameraController? _controller;
  List<CameraDescription>? cameras;
  late ImagePicker imagePicker;
  int _selectedCameraIndex = 0;
  int _selectedCameraIndexi = 1;
  bool _isPassportSelected = true;
  bool _isCINSelected = false;
  bool _isFlashOn = false;



  @override
  void initState() {
    super.initState();
    debugImport();
    imagePicker = ImagePicker();
    _initializeCamera();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showSelectionDialog();
    });

  }

  void _showSelectionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false, // Prevent user from dismissing dialog
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), // Rounded corners
          title: Column(
            children: [
              Icon(Icons.document_scanner, size: 50, color: Colors.blueAccent),
              SizedBox(height: 10),
              Text(
                "Choose Document Type",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Text(
            "Which document do you want to scan?",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16),
          ),
          actionsAlignment: MainAxisAlignment.center, // Center buttons
          actions: [
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: Icon(Icons.airplane_ticket, color: Colors.white),
              label: Text("Passport", style: TextStyle(color: Colors.white)),
              onPressed: () {
                setState(() {
                  _isPassportSelected = true;
                  _isCINSelected = false;
                });
                Navigator.pop(context);
              },
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: Icon(Icons.credit_card, color: Colors.white),
              label: Text("CIN", style: TextStyle(color: Colors.white)),
              onPressed: () {
                setState(() {
                  _isCINSelected = true;
                  _isPassportSelected = false;
                });
                Navigator.pop(context);
              },
            ),
          ],
        );
      },
    );
  }





  Future<void> _initializeCamera() async {
    cameras = await availableCameras();
    if (cameras!.isNotEmpty) {
      if (kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS )) {
        _controller = CameraController(
          cameras![_selectedCameraIndexi],
          ResolutionPreset.high,);
      }
      else {
        _controller = CameraController(
          cameras![_selectedCameraIndex],
          ResolutionPreset.high,

        ); }
      await _controller!.initialize();
      if (mounted) {
        setState(() {});
      }
    }
  }





  Future<void> _captureAndNavigate() async {
    if (_controller != null && _controller!.value.isInitialized) {
      XFile? xfile = await _controller!.takePicture();
      if (!mounted) return;

      File image = File(xfile.path);
      Uint8List webImage = await xfile.readAsBytes();

      // Ajouter cette partie pour éteindre le flash
      if (_isFlashOn) {
        await _controller!.setFlashMode(FlashMode.off);
        setState(() {
          _isFlashOn = false;
        });
      }

      // Nouvelle logique de rotation
      image_package.Image originalImage = image_package.decodeImage(await image.readAsBytes())!;
      int angle = 0;

      // Utilisation des capteurs d'accélération pour détecter l'orientation
      final accelerometerEvent = await accelerometerEvents.first;

      if (accelerometerEvent.x > 7) { // Téléphone incliné à droite
        angle = -90; // Rotation +π/2
      } else if (accelerometerEvent.x < -7) { // Téléphone incliné à gauche
        angle = 90; // Rotation -π/2
      }

      // Application de la rotation
      image_package.Image rotatedImage = image_package.copyRotate(originalImage,angle: angle);
      File rotatedFile = File(image.path)..writeAsBytesSync(image_package.encodeJpg(rotatedImage));

      // Effet miroir pour le web
      if (kIsWeb && (defaultTargetPlatform == TargetPlatform.windows || defaultTargetPlatform == TargetPlatform.macOS)) {
        webImage = _mirrorImage(webImage);
      }

      Navigator.push(context, MaterialPageRoute(builder: (ctx) {
        return _isPassportSelected
            ? Recognizerscreen(image: rotatedFile, webImage: webImage)
            : RecognizerCinScreen(image: rotatedFile, webImage: webImage);
      }));
    }
  }


  // Fonction pour appliquer l'effet miroir à une image
  Uint8List _mirrorImage(Uint8List imageBytes) {
    // Décoder l'image en utilisant le package `image`
    image_package.Image? img = image_package.decodeImage(imageBytes);

    if (img == null) {
      return imageBytes; // Retourner l'image originale si le décodage échoue
    }

    // Appliquer l'effet miroir horizontalement
    image_package.Image? mirroredImage = image_package.copyRotate(img,angle: 0); // Pas de rotation
    mirroredImage = image_package.flipHorizontal(mirroredImage); // Effet miroir horizontal

    // Encoder l'image modifiée en Uint8List
    return Uint8List.fromList(image_package.encodePng(mirroredImage));
  }



  Future<void> _captureAndNavigatepc() async {

    if (_controller != null && _controller!.value.isInitialized) {
      XFile? xfile = await _controller!.takePicture();


      if (!mounted) return;

      File image = File(xfile.path);
      Uint8List webImage = await xfile.readAsBytes();

      if(kIsWeb && (defaultTargetPlatform==TargetPlatform.windows || defaultTargetPlatform==TargetPlatform.macOS)){
        webImage = _mirrorImage(webImage); // Appliquer l'effet miroir
      }

      Navigator.push(context, MaterialPageRoute(builder: (ctx) {
        if (_isPassportSelected) {
          return Recognizerscreen(image: image, webImage: webImage);
        } else {
          return RecognizerCinScreen (image: image, webImage: webImage);
        }
      }));
    }
  }


  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {

    if(!kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS ))  {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox.expand(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 5, vertical: 10),
            child: Stack(
              children: [
                // Camera Card - keeping it as is
                Align(
                  alignment: Alignment.topCenter,
                  child: Card(
                    color: Colors.black,
                    child: Container(
                      width: double.infinity,
                      height: double.infinity,
                      padding: EdgeInsets.only(top: 20),
                      child: _controller != null && _controller!.value.isInitialized
                          ? ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: AspectRatio(
                          aspectRatio: MediaQuery.of(context).orientation == Orientation.portrait
                              ? 9 / 16
                              : 16 / 9,
                          child: FittedBox(
                            fit: BoxFit.cover,
                            child: Transform.rotate(
                              angle: (_selectedCameraIndex == 0)
                                  ? 0 + pi / 2
                                  : pi / 2 + ((_selectedCameraIndex == 1) ? pi : pi),
                              child: Transform(
                                alignment: Alignment.center,
                                transform: Matrix4.identity()
                                  ..scale(
                                    // Changed scale factor from 1.0/-1.0 to 0.5/-0.5 for dezoom
                                    _selectedCameraIndex == 1 ? -0.5 : 0.5,
                                    _selectedCameraIndex == 1 ? -0.5 : 0.5,
                                    1.0,
                                  ),
                                child: SizedBox(
                                  width: MediaQuery.of(context).orientation == Orientation.portrait
                                      ? _controller!.value.previewSize!.width
                                      : _controller!.value.previewSize!.height,
                                  height: MediaQuery.of(context).orientation == Orientation.portrait
                                      ? _controller!.value.previewSize!.height
                                      : _controller!.value.previewSize!.width,
                                  child: CameraPreview(_controller!),
                                ),
                              ),
                            ),
                          ),
                        ),
                      )
                          : Center(child: CircularProgressIndicator()),
                    ),
                  ),
                ),




                // Floating Passport and CIN Buttons at the top center
                // Floating Passport and CIN Buttons at the mid-top
                Positioned(
                  top: 40,
                  left: 0,
                  right: 0,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center, // Centered in the middle
                      children: [
                        // Passport Mode Button
                        InkWell(
                          onTap: () {
                            setState(() {
                              _isPassportSelected = true;
                              _isCINSelected = false;
                            });
                          },
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8.0),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.airplane_ticket,
                                  color: _isPassportSelected ? Colors.blue : Colors.white,
                                ),
                                SizedBox(width: 5),
                                Text(
                                  'Passport',
                                  style: TextStyle(
                                    color: _isPassportSelected ? Colors.blue : Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // CIN Mode Button
                        InkWell(
                          onTap: () {
                            setState(() {
                              _isCINSelected = true;
                              _isPassportSelected = false;
                            });
                          },
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8.0),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.credit_card,
                                  color: _isCINSelected ? Colors.blue : Colors.white,
                                ),
                                SizedBox(width: 5),
                                Text(
                                  'CIN',
                                  style: TextStyle(
                                    color: _isCINSelected ? Colors.blue : Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),


                // Floating Bottom Buttons at the bottom center
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 15),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(1), // Semi-transparent black background
                      borderRadius: BorderRadius.circular(0), // Rounded corners
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Flash icon aligned to the left
                        Positioned(
                          left: 40,
                          child: InkWell(
                            onTap: () async {
                              if (_controller != null) {
                                await _controller!.setFlashMode(
                                    _isFlashOn ? FlashMode.off : FlashMode.torch);
                                setState(() {
                                  _isFlashOn = !_isFlashOn;
                                });
                                // Éteindre automatiquement après 30 secondes
                                Future.delayed(Duration(seconds: 30), () {
                                  if (_isFlashOn && mounted) {
                                    _controller?.setFlashMode(FlashMode.off);
                                    setState(() =>
                                    _isFlashOn = false);
                                  }
                                });
                              }
                            },
                            child: Icon(
                              Icons.flash_on,
                              size: 45,
                              color: _isFlashOn ? Colors.blue : Colors.white,
                            ),
                          ),
                        ),

                        // Camera icon centered
                        InkWell(
                          onTap: _captureAndNavigate,
                          child: Icon(
                            Icons.camera,
                            size: 60,
                            color: Colors.white,
                          ),
                        ),

                        // Gallery icon aligned to the right
                        Positioned(
                          right: 40,
                          child: InkWell(
                            onTap: () async {
                              XFile? xfile =
                              await imagePicker.pickImage(source: ImageSource.gallery);
                              if (xfile != null) {
                                File image = File(xfile.path);
                                Uint8List webImage = await xfile.readAsBytes();
                                Navigator.push(context, MaterialPageRoute(builder: (ctx) {
                                  return _isPassportSelected
                                      ? Recognizerscreen(image: image, webImage: webImage)
                                      : RecognizerCinScreen(image: image, webImage: webImage);
                                }));
                              }
                            },
                            child: Icon(
                              Icons.image_outlined,
                              size: 45,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              ],
            ),
          ),
        ),
      );

    }
    else if (kIsWeb &&(defaultTargetPlatform==TargetPlatform.windows || defaultTargetPlatform==TargetPlatform.macOS)) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: SizedBox.expand(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 5, vertical: 10),
            child: Stack(
              children: [
                // Camera Card - keeping it as is
                Align(
                  alignment: Alignment.topCenter,
                  child: Card(
                    color: Colors.white,
                    child: Container(
                      width: double.infinity,
                      height: double.infinity,
                      padding: EdgeInsets.only(top: 20),
                      child: _controller != null && _controller!.value.isInitialized
                          ? ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: AspectRatio(
                          aspectRatio: MediaQuery.of(context).orientation == Orientation.portrait
                              ? 9 / 16
                              : 16 / 9,
                          child: FittedBox(
                            fit: BoxFit.contain,
                            child: Transform.rotate(
                              angle: 0,
                              child: Transform(
                                alignment: Alignment.center,
                                transform: Matrix4.identity()..scale(-1.0, 1.0, 1.0)
                                  ..scale(
                                    _selectedCameraIndex == 1 ? -1.0 : 1.0,
                                    _selectedCameraIndex == 1 ? -1.0 : 1.0,
                                    1.0,
                                  ),
                                child: SizedBox(
                                  width: MediaQuery.of(context).orientation == Orientation.portrait
                                      ? _controller!.value.previewSize!.width
                                      : _controller!.value.previewSize!.height,
                                  height: MediaQuery.of(context).orientation == Orientation.portrait
                                      ? _controller!.value.previewSize!.height
                                      : _controller!.value.previewSize!.width,
                                  child: CameraPreview(_controller!),
                                ),
                              ),
                            ),
                          ),
                        ),
                      )
                          : Center(child: CircularProgressIndicator()),
                    ),
                  ),
                ),

                // Floating Passport and CIN Buttons at the top center
                // Floating Passport and CIN Buttons at the mid-top
                Positioned(
                  top: 40,
                  left: 0,
                  right: 0,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center, // Centered in the middle
                      children: [
                        // Passport Mode Button with Shadow
                        InkWell(
                          onTap: () {
                            setState(() {
                              _isPassportSelected = true;
                              _isCINSelected = false;
                            });
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.5), // Shadow color with opacity
                                  blurRadius: 8, // Blur radius
                                  offset: Offset(0, 2), // Shadow position (x, y)
                                ),
                              ],
                            ),
                            child: Padding(
                              padding: EdgeInsets.symmetric(horizontal: 8.0),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.airplane_ticket,
                                    color: _isPassportSelected ? Colors.white : Colors.grey[300],
                                  ),
                                  SizedBox(width: 5),
                                  Text(
                                    'Passport',
                                    style: TextStyle(
                                      color: _isPassportSelected ? Colors.white : Colors.grey[300],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        SizedBox(width: 20), // Adds space between the buttons

                        // CIN Mode Button with Shadow
                        InkWell(
                          onTap: () {
                            setState(() {
                              _isCINSelected = true;
                              _isPassportSelected = false;
                            });
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.5), // Shadow color with opacity
                                  blurRadius: 8, // Blur radius
                                  offset: Offset(0, 2), // Shadow position (x, y)
                                ),
                              ],
                            ),
                            child: Padding(
                              padding: EdgeInsets.symmetric(horizontal: 8.0),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.credit_card,
                                    color: _isCINSelected ? Colors.white : Colors.grey[300],
                                  ),
                                  SizedBox(width: 5),
                                  Text(
                                    'CIN',
                                    style: TextStyle(
                                      color: _isCINSelected ? Colors.white : Colors.grey[300],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),



                // Floating Bottom Buttons at the bottom center
                Positioned(
                  bottom: 30,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 10), // Ensures the buttons are centered
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center, // Centers the buttons
                      children: [


                        Row(
                          mainAxisAlignment: MainAxisAlignment.center, // Keeps buttons centered
                          children: [
                            // Passport button with shadow
                            InkWell(
                              onTap: _captureAndNavigatepc,
                              child: Container(
                                decoration: BoxDecoration(
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.5), // Shadow color with opacity
                                      blurRadius: 8, // Blur radius
                                      offset: Offset(0, 2), // Shadow position (x, y)
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.camera,
                                  size: 50,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            SizedBox(width: 20), // Adds 20 pixels of space between buttons
                            // Image button with shadow
                            InkWell(
                              child: Container(
                                decoration: BoxDecoration(
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.5), // Shadow color with opacity
                                      blurRadius: 8, // Blur radius
                                      offset: Offset(0, 2), // Shadow position (x, y)
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.image_outlined,
                                  size: 35,
                                  color: Colors.white,
                                ),
                              ),
                              onTap: () async {
                                XFile? xfile = await imagePicker.pickImage(source: ImageSource.gallery);
                                if (xfile != null) {
                                  File image = File(xfile.path);
                                  Uint8List webImage = await xfile.readAsBytes();
                                  Navigator.push(context, MaterialPageRoute(builder: (ctx) {
                                    if (_isPassportSelected) {
                                      return Recognizerscreen(image: image, webImage: webImage);
                                    } else {
                                      return RecognizerCinScreen(image: image, webImage: webImage);
                                    }
                                  }));
                                }
                              },
                            ),
                          ],
                        ),


                      ],
                    ),
                  ),
                ),


              ],
            ),
          ),
        ),
      );
    }
    else {
      return Scaffold(
        backgroundColor: Colors.black,
        body: OrientationBuilder(
          builder: (context, orientation) {
            return SizedBox.expand(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 10),
                child: Stack(
                  children: [
                    // Preview caméra
                    Align(
                      alignment: Alignment.topCenter,
                      child: Card(
                        color: Colors.black,
                        child: Container(
                          width: double.infinity,
                          height: double.infinity,
                          padding: const EdgeInsets.only(top: 20),
                          child: _controller != null && _controller!.value.isInitialized
                              ? ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: AspectRatio(
                              aspectRatio: _controller!.value.aspectRatio,
                              child: CameraPreview(_controller!),
                            ),
                          )
                              : const Center(child: CircularProgressIndicator()),
                        ),
                      ),
                    ),
                    // Sélection du mode
                    Positioned(
                      top: 40,
                      left: 0,
                      right: 0,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            InkWell(
                              onTap: () => setState(() {
                                _isPassportSelected = true;
                                _isCINSelected = false;
                              }),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.airplane_ticket,
                                      color: _isPassportSelected ? Colors.blue : Colors.white,
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      'Passport',
                                      style: TextStyle(
                                        color: _isPassportSelected ? Colors.blue : Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            InkWell(
                              onTap: () => setState(() {
                                _isCINSelected = true;
                                _isPassportSelected = false;
                              }),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.credit_card,
                                      color: _isCINSelected ? Colors.blue : Colors.white,
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      'CIN',
                                      style: TextStyle(
                                        color: _isCINSelected ? Colors.blue : Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Contrôles : affichage différent selon l'orientation
                    if (orientation == Orientation.portrait)
                    // Portrait : Boutons en bas, sans fond (transparents)
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 15),
                          // Pas de decoration = fond transparent
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Positioned(
                                left: 40,
                                child: InkWell(
                                  onTap: () async {
                                    if (kIsWeb) {
                                      await toggleTorchWeb(!_isFlashOn);
                                      setState(() => _isFlashOn = !_isFlashOn);
                                    } else {
                                      if (_controller != null && _controller!.value.isInitialized) {
                                        try {
                                          await _controller!.setFlashMode(
                                              _isFlashOn ? FlashMode.off : FlashMode.torch);
                                          setState(() => _isFlashOn = !_isFlashOn);
                                        } catch (e) {
                                          debugPrint("Erreur toggling flash: $e");
                                        }
                                      } else {
                                        debugPrint("CameraController is not initialized.");
                                      }
                                    }
                                  },
                                  child: Icon(
                                    _isFlashOn ? Icons.flash_on : Icons.flash_off,
                                    color: Colors.white,
                                    size: 30,
                                  ),
                                ),
                              ),
                              InkWell(
                                onTap: _captureAndNavigatepc,
                                child: const Icon(
                                  Icons.camera,
                                  size: 60,
                                  color: Colors.white,
                                ),
                              ),
                              Positioned(
                                right: 40,
                                child: InkWell(
                                  onTap: () async {
                                    final xfile = await imagePicker.pickImage(source: ImageSource.gallery);
                                    if (xfile != null) {
                                      final image = File(xfile.path);
                                      final webImage = await xfile.readAsBytes();
                                      Navigator.push(context, MaterialPageRoute(builder: (ctx) {
                                        return _isPassportSelected
                                            ? Recognizerscreen(image: image, webImage: webImage)
                                            : RecognizerCinScreen(image: image, webImage: webImage);
                                      }));
                                    }
                                  },
                                  child: const Icon(
                                    Icons.image_outlined,
                                    size: 45,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                    // Landscape : Boutons disposés verticalement à droite, sans fond
                      Positioned(
                        top: 0,
                        bottom: 0,
                        right: 0,
                        child: Container(
                          width: 80,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          // Pas de decoration = fond transparent
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              InkWell(
                                onTap: () async {
                                  if (kIsWeb) {
                                    await toggleTorchWeb(!_isFlashOn);
                                    setState(() => _isFlashOn = !_isFlashOn);
                                  } else {
                                    if (_controller != null && _controller!.value.isInitialized) {
                                      try {
                                        await _controller!.setFlashMode(
                                            _isFlashOn ? FlashMode.off : FlashMode.torch);
                                        setState(() => _isFlashOn = !_isFlashOn);
                                      } catch (e) {
                                        debugPrint("Erreur toggling flash: $e");
                                      }
                                    } else {
                                      debugPrint("CameraController is not initialized.");
                                    }
                                  }
                                },
                                child: Icon(
                                  _isFlashOn ? Icons.flash_on : Icons.flash_off,
                                  color: Colors.white,
                                  size: 30,
                                ),
                              ),
                              const SizedBox(height: 20),
                              InkWell(
                                onTap: _captureAndNavigatepc,
                                child: const Icon(
                                  Icons.camera,
                                  size: 60,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 20),
                              InkWell(
                                onTap: () async {
                                  final xfile = await imagePicker.pickImage(source: ImageSource.gallery);
                                  if (xfile != null) {
                                    final image = File(xfile.path);
                                    final webImage = await xfile.readAsBytes();
                                    Navigator.push(context, MaterialPageRoute(builder: (ctx) {
                                      return _isPassportSelected
                                          ? Recognizerscreen(image: image, webImage: webImage)
                                          : RecognizerCinScreen(image: image, webImage: webImage);
                                    }));
                                  }
                                },
                                child: const Icon(
                                  Icons.image_outlined,
                                  size: 45,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    }






  }


}

