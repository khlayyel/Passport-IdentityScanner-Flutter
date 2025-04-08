import 'dart:io';
import 'dart:math';
import 'dart:math'as math;

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

class _HomeScreenState extends State<HomeScreen> {
  CameraController? _controller;
  List<CameraDescription>? cameras;
  late ImagePicker imagePicker;

  final int _selectedCameraIndex = 0;
  final int _selectedCameraIndexi = 1;
  bool _isPassportSelected = true;
  bool _isCINSelected = false;
  bool _isFlashOn = false;
  bool _showTipOverlay = true;

  // To avoid multiple simultaneous captures
  bool _isProcessingCapture = false;

  // For CIN mode: store recto image (File for mobile, bytes for web)
  File? _cinRectoImage;
  Uint8List? _cinRectoWebImage;

  @override
  void initState() {
    super.initState();
    debugImport(); // Your debug function
    imagePicker = ImagePicker();
    _initializeCamera();

    // Show the document type selection dialog after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showSelectionDialog();
    });
  }

  void _showSelectionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false, // Force a choice
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: Column(
            children: const [
              Icon(Icons.document_scanner, size: 50, color: Colors.blueAccent),
              SizedBox(height: 10),
              Text(
                "Choose Document Type",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: const Text(
            "Which document do you want to scan?",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.airplane_ticket, color: Colors.white),
              label: const Text("Passport", style: TextStyle(color: Colors.white)),
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
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.credit_card, color: Colors.white),
              label: const Text("CIN", style: TextStyle(color: Colors.white)),
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
    if (cameras != null && cameras!.isNotEmpty) {
      // For web on mobile use alternate index; otherwise use first camera.
      if (kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS)) {
        _controller = CameraController(
          cameras![_selectedCameraIndexi],
          ResolutionPreset.high,
        );
      } else {
        _controller = CameraController(
          cameras![_selectedCameraIndex],
          ResolutionPreset.high,
        );
      }
      await _controller!.initialize();
      if (mounted) setState(() {});
    }
  }

  // Merge two images from File (for mobile)
  File _mergeImagesVertically(File topFile, File bottomFile) {
    final topBytes = topFile.readAsBytesSync();
    final bottomBytes = bottomFile.readAsBytesSync();

    final topImg = image_package.decodeImage(topBytes)!;
    final bottomImg = image_package.decodeImage(bottomBytes)!;

    final mergedWidth = max(topImg.width, bottomImg.width);
    final mergedHeight = topImg.height + bottomImg.height;

    final mergedImg = image_package.Image(mergedWidth, mergedHeight);
    image_package.copyInto(mergedImg, topImg, blend: false);
    image_package.copyInto(mergedImg, bottomImg, dstY: topImg.height, blend: false);

    final mergedPath = '${topFile.path}_merged.jpg';
    final mergedFile = File(mergedPath);
    mergedFile.writeAsBytesSync(image_package.encodeJpg(mergedImg));
    return mergedFile;
  }

  // Merge two images from bytes (for web)
  Uint8List _mergeBytesVertically(Uint8List topBytes, Uint8List bottomBytes) {
    final topImg = image_package.decodeImage(topBytes)!;
    final bottomImg = image_package.decodeImage(bottomBytes)!;
    final mergedWidth = max(topImg.width, bottomImg.width);
    final mergedHeight = topImg.height + bottomImg.height;
    final mergedImg = image_package.Image(mergedWidth, mergedHeight);
    image_package.copyInto(mergedImg, topImg, blend: false);
    image_package.copyInto(mergedImg, bottomImg, dstY: topImg.height, blend: false);
    return Uint8List.fromList(image_package.encodeJpg(mergedImg));
  }

  // Mirror image bytes horizontally (for web desktop)
  Uint8List _mirrorImage(Uint8List imageBytes) {
    final decoded = image_package.decodeImage(imageBytes);
    if (decoded == null) return imageBytes;
    final flipped = image_package.flipHorizontal(decoded);
    return Uint8List.fromList(image_package.encodePng(flipped));
  }

  /// Capture and navigate for mobile (Android/iOS)
  Future<void> _captureAndNavigate() async {
    if (_isProcessingCapture) return;
    _isProcessingCapture = true;

    if (_controller == null || !_controller!.value.isInitialized) {
      _isProcessingCapture = false;
      return;
    }

    XFile? xfile = await _controller!.takePicture();
    if (!mounted || xfile == null) {
      _isProcessingCapture = false;
      return;
    }
    final file = File(xfile.path);
    Uint8List webBytes = await xfile.readAsBytes();

    // Turn off flash if needed
    if (_isFlashOn) {
      await _controller!.setFlashMode(FlashMode.off);
      setState(() {
        _isFlashOn = false;
      });
    }

    // Rotate based on accelerometer
    final originalImg = image_package.decodeImage(await file.readAsBytes())!;
    int angle = 0;
    final accel = await accelerometerEvents.first;
    if (accel.x > 7) {
      angle = -90;
    } else if (accel.x < -7) {
      angle = 90;
    }
    final rotated = image_package.copyRotate(originalImg, angle);
    file.writeAsBytesSync(image_package.encodeJpg(rotated));

    // For desktop web on mobile (rare) apply mirror if needed
    if (kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.macOS)) {
      webBytes = _mirrorImage(webBytes);
    }

    if (_isPassportSelected) {
      // Passport mode: one capture
      Navigator.push(context, MaterialPageRoute(builder: (ctx) {
        return Recognizerscreen(image: file, webImage: webBytes);
      }));
      _isProcessingCapture = false;
    } else {
      // CIN mode: double capture
      if (_cinRectoImage == null && _cinRectoWebImage == null) {
        // First capture = Recto
        _cinRectoImage = file;
        _cinRectoWebImage = webBytes;
        await showDialog(
          context: context,
          builder: (ctx) {
            return AlertDialog(
              title: const Text("Recto Capturé"),
              content: const Text(
                  "Veuillez retourner le document et appuyer sur capture pour le verso."),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text("OK"),
                ),
              ],
            );
          },
        );
        setState(() {}); // Update interface (e.g. show "Verso")
        _isProcessingCapture = false;
      } else {
        // Second capture = Verso; now merge with recto.
        if (!kIsWeb) {
          // Mobile: use File merging
          final versoFile = file;
          final mergedFile = _mergeImagesVertically(_cinRectoImage!, versoFile);
          final mergedBytes = mergedFile.readAsBytesSync();
          Navigator.push(context, MaterialPageRoute(builder: (ctx) {
            return RecognizerCinScreen(image: mergedFile, webImage: mergedBytes);
          }));
        } else {
          // Web: use bytes merging. We already have _cinRectoWebImage from first capture.
          final versoBytes = webBytes;
          final mergedBytes = _mergeBytesVertically(_cinRectoWebImage!, versoBytes);
          Navigator.push(context, MaterialPageRoute(builder: (ctx) {
            return RecognizerCinScreen(image: null, webImage: mergedBytes);
          }));
        }
        // Reset for next CIN scan
        _cinRectoImage = null;
        _cinRectoWebImage = null;
        _isProcessingCapture = false;
      }
    }
  }

  /// Capture and navigate for desktop web (Windows/macOS)
  Future<void> _captureAndNavigatepc() async {
    if (_isProcessingCapture) return;
    _isProcessingCapture = true;

    if (_controller == null || !_controller!.value.isInitialized) {
      _isProcessingCapture = false;
      return;
    }

    // Capture image
    XFile? xfile = await _controller!.takePicture();
    if (!mounted || xfile == null) {
      _isProcessingCapture = false;
      return;
    }
    final file = File(xfile.path);
    Uint8List webBytes = await xfile.readAsBytes();

    if (kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.macOS)) {
      // Apply mirror effect for desktop web
      webBytes = _mirrorImage(webBytes);
    }


    if (_isPassportSelected) {
      Navigator.push(context, MaterialPageRoute(builder: (ctx) {
        return Recognizerscreen(image: file, webImage: webBytes);
      }));
      _isProcessingCapture = false;
    } else {
      // CIN mode: double capture
      if (_cinRectoImage == null && _cinRectoWebImage == null) {
        _cinRectoImage = file;
        _cinRectoWebImage = webBytes;
        await showDialog(
          context: context,
          builder: (ctx) {
            return AlertDialog(
              title: const Text("Recto Capturé"),
              content: const Text(
                  "Veuillez retourner le document et appuyer sur capture pour le verso."),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text("OK"),
                ),
              ],
            );
          },
        );
        setState(() {});
        _isProcessingCapture = false;
      } else {
        // Second capture => merge
        final versoFile = file;
        if (!kIsWeb) {
          final mergedFile = _mergeImagesVertically(_cinRectoImage!, versoFile);
          final mergedBytes = mergedFile.readAsBytesSync();
          Navigator.push(context, MaterialPageRoute(builder: (ctx) {
            return RecognizerCinScreen(image: mergedFile, webImage: mergedBytes);
          }));
        } else {
          final mergedBytes = _mergeBytesVertically(_cinRectoWebImage!, webBytes);
          Navigator.push(context, MaterialPageRoute(builder: (ctx) {
            return RecognizerCinScreen(image: null, webImage: mergedBytes);
          }));
        }
        _cinRectoImage = null;
        _cinRectoWebImage = null;
        _isProcessingCapture = false;
      }
    }
  }

  // Pick images from gallery
  Future<void> _pickFromGallery() async {
    if (_isPassportSelected) {
      final xfile = await imagePicker.pickImage(source: ImageSource.gallery);
      if (xfile != null) {
        final file = File(xfile.path);
        final bytes = await xfile.readAsBytes();
        Navigator.push(context, MaterialPageRoute(builder: (ctx) {
          return Recognizerscreen(image: file, webImage: bytes);
        }));
      }
    } else {
      // CIN mode on web: allow sequential selection
      if (kIsWeb) {
        // First, pick the recto image if not already set
        if (_cinRectoWebImage == null) {
          final xfile = await imagePicker.pickImage(source: ImageSource.gallery);
          if (xfile != null) {
            _cinRectoWebImage = await xfile.readAsBytes();
            // Optionally, show a dialog instructing the user to pick the verso image next.
            await showDialog(
              context: context,
              builder: (ctx) {
                return AlertDialog(
                  title: const Text("Recto Capturé"),
                  content: const Text("Veuillez maintenant sélectionner l'image verso depuis la galerie."),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text("OK"),
                    ),
                  ],
                );
              },
            );
          }
        } else {
          // Now pick the verso image
          final xfile = await imagePicker.pickImage(source: ImageSource.gallery);
          if (xfile != null) {
            final versoBytes = await xfile.readAsBytes();
            final mergedBytes = _mergeBytesVertically(_cinRectoWebImage!, versoBytes);
            Navigator.push(context, MaterialPageRoute(builder: (ctx) {
              return RecognizerCinScreen(image: null, webImage: mergedBytes);
            }));
            // Reset CIN state after processing
            _cinRectoWebImage = null;
          }
        }
      } else {
        // Mobile CIN branch (existing code)
        final xfiles = await imagePicker.pickMultiImage();
        if (xfiles != null && xfiles.isNotEmpty) {
          if (xfiles.length == 1) {
            final file = File(xfiles[0].path);
            final bytes = await xfiles[0].readAsBytes();
            Navigator.push(context, MaterialPageRoute(builder: (ctx) {
              return RecognizerCinScreen(image: file, webImage: bytes);
            }));
          } else {
            final file1 = File(xfiles[0].path);
            final file2 = File(xfiles[1].path);
            final mergedFile = _mergeImagesVertically(file1, file2);
            final mergedBytes = mergedFile.readAsBytesSync();
            Navigator.push(context, MaterialPageRoute(builder: (ctx) {
              return RecognizerCinScreen(image: mergedFile, webImage: mergedBytes);
            }));
          }
        }
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
    // Mobile branch (Android/iOS)
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox.expand(
          child: OrientationBuilder(
            builder: (context, orientation) {
              return Stack(
                children: [
                  // 1. Camera preview
                  if (_controller != null && _controller!.value.isInitialized)
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: AspectRatio(
                          aspectRatio: _controller!.value.aspectRatio,
                          child: CameraPreview(_controller!),
                        ),
                      ),
                    )
                  else
                    const Center(child: CircularProgressIndicator()),

                  // 2. Passport / CIN buttons and "Recto"/"Verso" text (for CIN)
                  Positioned(
                    top: 40,
                    left: 0,
                    right: 0,
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Passport button
                            InkWell(
                              onTap: () {
                                setState(() {
                                  _isPassportSelected = true;
                                  _isCINSelected = false;
                                });
                              },
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
                            // CIN button
                            InkWell(
                              onTap: () {
                                setState(() {
                                  _isCINSelected = true;
                                  _isPassportSelected = false;
                                  _cinRectoImage = null;
                                  _cinRectoWebImage = null;
                                });
                              },
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
                        if (_isCINSelected)
                          Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(
                              _cinRectoImage == null ? "Recto" : "Verso",
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                      ],
                    ),
                  ),

                  // 3. Flash, capture, and gallery buttons at the bottom
                  Positioned(
                    bottom: 20,
                    left: 0,
                    right: 0,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Flash button
                        Positioned(
                          left: 40,
                          child: InkWell(
                            onTap: () async {
                              if (_controller != null) {
                                await _controller!.setFlashMode(
                                  _isFlashOn ? FlashMode.off : FlashMode.torch,
                                );
                                setState(() {
                                  _isFlashOn = !_isFlashOn;
                                });
                                Future.delayed(const Duration(seconds: 30), () {
                                  if (_isFlashOn && mounted) {
                                    _controller?.setFlashMode(FlashMode.off);
                                    setState(() => _isFlashOn = false);
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
                        // Capture button
                        InkWell(
                          onTap: _captureAndNavigate,
                          child: const Icon(
                            Icons.camera,
                            size: 60,
                            color: Colors.white,
                          ),
                        ),
                        // Gallery button
                        Positioned(
                          right: 40,
                          child: InkWell(
                            onTap: _pickFromGallery,
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

                  // 4. Dotted-rectangle overlay (drawn above everything)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return CustomPaint(
                            painter: _DottedFramePainter(
                              orientation: orientation,
                              maxWidth: constraints.maxWidth,
                              maxHeight: constraints.maxHeight,
                            ),
                          );
                        },
                      ),
                    ),
                  ),

                  // 5. Tip overlay inside the dotted frame with message and OK button
                  if (_showTipOverlay)
                    Positioned.fill(
                      child: Center(
                        child: FractionallySizedBox(
                          widthFactor: orientation == Orientation.portrait ? 0.95 : 0.75,
                          heightFactor: orientation == Orientation.portrait ? 0.35 : 0.80,
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.black54.withOpacity(0.8),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text(
                                  "Si vous souhaitez prendre la photo en tournant le téléphone, veuillez activer l'auto-rotation. N'oubliez pas!",
                                  style: TextStyle(color: Colors.white, fontSize: 16),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 10),
                                ElevatedButton(
                                  onPressed: () {
                                    setState(() {
                                      _showTipOverlay = false;
                                    });
                                  },
                                  child: const Text("OK"),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      );
    }



    // Web desktop branch (Windows/macOS)
    else if (kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.macOS)) {
      return Scaffold(
          backgroundColor: Colors.white,
          body: SizedBox.expand(
          child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 10),
    child: Stack(
    children: [
    // Camera preview card
    Align(
    alignment: Alignment.topCenter,
    child: Card(
    color: Colors.white,
    child: Container(
    width: double.infinity,
    height: double.infinity,
    padding: const EdgeInsets.only(top: 20),
    child: _controller != null && _controller!.value.isInitialized
    ? ClipRRect(
    borderRadius: BorderRadius.circular(10),
    child: AspectRatio(
    aspectRatio: MediaQuery.of(context).orientation ==
    Orientation.portrait
    ? 9 / 16
        : 16 / 9,
    child: FittedBox(
    fit: BoxFit.contain,
    child: Transform.rotate(
    angle: 0,
    child: Transform(
    alignment: Alignment.center,
    transform: Matrix4.identity()
    ..scale(-1.0, 1.0, 1.0)
    ..scale(
    _selectedCameraIndex == 1 ? -1.0 : 1.0,
    _selectedCameraIndex == 1 ? -1.0 : 1.0,
    1.0,
    ),
    child: SizedBox(
    width: MediaQuery.of(context).orientation ==
    Orientation.portrait
    ? _controller!.value.previewSize!.width
        : _controller!.value.previewSize!.height,
    height: MediaQuery.of(context).orientation ==
    Orientation.portrait
    ? _controller!.value.previewSize!.height
        : _controller!.value.previewSize!.width,
    child: CameraPreview(_controller!),
    ),
    ),
    ),
    ),
    ),
    )
        : const Center(child: CircularProgressIndicator()),
    ),
    ),
    ),
    // Top buttons (Passport / CIN)
    Positioned(
    top: 40,
    left: 0,
    right: 0,
    child: Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
    // Passport button with shadow
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
    color: Colors.black.withOpacity(0.5),
    blurRadius: 8,
    offset: const Offset(0, 2),
    ),
    ],
    ),
    child: Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8.0),
    child: Row(
    children: [
    Icon(
    Icons.airplane_ticket,
    color: _isPassportSelected
    ? Colors.white
        : Colors.grey[300],
    ),
    const SizedBox(width: 5),
    Text(
    'Passport',
    style: TextStyle(
    color: _isPassportSelected
    ? Colors.white
        : Colors.grey[300],
    ),
    ),
    ],
    ),
    ),
    ),
    ),
    const SizedBox(width: 20),
    // CIN button with shadow; resets the CIN state when selected
    InkWell(
    onTap: () {
    setState(() {
    _isCINSelected = true;
    _isPassportSelected = false;
    _cinRectoImage = null;
    _cinRectoWebImage = null;
    });
    },
    child: Container(
    decoration: BoxDecoration(
    boxShadow: [
    BoxShadow(
    color: Colors.black.withOpacity(0.5),
    blurRadius: 8,
    offset: const Offset(0, 2),
    ),
    ],
    ),
    child: Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8.0),
    child: Row(
    children: [
    Icon(
    Icons.credit_card,
    color: _isCINSelected
    ? Colors.white
        : Colors.grey[300],
    ),
    const SizedBox(width: 5),
    Text(
    'CIN',
    style: TextStyle(
    color: _isCINSelected
    ? Colors.white
        : Colors.grey[300],
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
    // Display "Recto" or "Verso" text if in CIN mode
    if (_isCINSelected)
    Positioned(
    top: 100, // Adjust this vertical offset as needed
    left: 0,
    right: 0,
    child: Center(
    child: Text(
    _cinRectoImage == null ? "Recto" : "Verso",
    style: const TextStyle(
    color: Colors.white,
    fontSize: 20,
    fontWeight: FontWeight.bold,
    ),
    ),
    ),
    ),
    // Bottom buttons (Capture and Gallery)
    Positioned(
    bottom: 30,
    left: 0,
    right: 0,
    child: Container(
    padding: const EdgeInsets.symmetric(horizontal: 10),
    child: Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
    // Capture button
    InkWell(
    onTap: _captureAndNavigatepc,
    child: Container(
    decoration: BoxDecoration(
    boxShadow: [
    BoxShadow(
    color: Colors.black.withOpacity(0.5),
    blurRadius: 8,
    offset: const Offset(0, 2),
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
    const SizedBox(width: 20),
    // Gallery button
    InkWell(
    onTap: _pickFromGallery,
    child: Container(
    decoration: BoxDecoration(
    boxShadow: [
    BoxShadow(
    color: Colors.black.withOpacity(0.5),
    blurRadius: 8,
    offset: const Offset(0, 2),
    ),
    ],
    ),
    child: const Icon(
    Icons.image_outlined,
    size: 35,
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
    ));
  }



    else {
      // This branch is for web on Android/iOS
      return Scaffold(
        backgroundColor: Colors.black,
        body: OrientationBuilder(
          builder: (context, orientation) {
            return SizedBox.expand(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 10),
                child: Stack(
                  children: [
                    // 1. Camera preview
                    Align(
                      alignment: Alignment.topCenter,
                      child: Card(
                        color: Colors.black,
                        child: Container(
                          width: double.infinity,
                          height: double.infinity,
                          padding: const EdgeInsets.only(top: 20),
                          child: (_controller != null && _controller!.value.isInitialized)
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
                    // 2. Mode selection buttons (Passport / CIN)
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
                                          color: _isPassportSelected ? Colors.blue : Colors.white),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            InkWell(
                              onTap: () => setState(() {
                                _isCINSelected = true;
                                _isPassportSelected = false;
                                // Reset CIN state on web:
                                _cinRectoImage = null;
                                _cinRectoWebImage = null;
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
                                          color: _isCINSelected ? Colors.blue : Colors.white),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // 3. "Recto" or "Verso" text for CIN mode
                    if (_isCINSelected)
                      Positioned(
                        top: 100, // adjust vertical offset as needed
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Text(
                            (_cinRectoWebImage == null) ? "Recto" : "Verso",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    // 4. Bottom controls (Capture and Gallery)
                    if (orientation == Orientation.portrait)
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          padding:
                          const EdgeInsets.symmetric(horizontal: 10, vertical: 15),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // Flash button
                              Positioned(
                                left: 40,
                                child: InkWell(
                                  onTap: () async {
                                    // For web on Android/iOS, simply toggle torch (if available)
                                    await toggleTorchWeb(!_isFlashOn);
                                    setState(() => _isFlashOn = !_isFlashOn);
                                  },
                                  child: Icon(
                                    _isFlashOn ? Icons.flash_on : Icons.flash_off,
                                    color: Colors.white,
                                    size: 30,
                                  ),
                                ),
                              ),
                              // Capture button (calls _captureAndNavigatepc)
                              InkWell(
                                onTap: _captureAndNavigatepc,
                                child: const Icon(
                                  Icons.camera,
                                  size: 60,
                                  color: Colors.white,
                                ),
                              ),
                              // Gallery button
                              Positioned(
                                right: 40,
                                child: InkWell(
                                  onTap: () async {
                                    // For CIN mode, use sequential image selection
                                    if (_isCINSelected) {
                                      if (_cinRectoWebImage == null) {
                                        final xfile = await imagePicker.pickImage(
                                          source: ImageSource.gallery,
                                        );
                                        if (xfile != null) {
                                          _cinRectoWebImage = await xfile.readAsBytes();
                                          await showDialog(
                                            context: context,
                                            builder: (ctx) {
                                              return AlertDialog(
                                                title: const Text("Recto Capturé"),
                                                content: const Text(
                                                    "Veuillez maintenant sélectionner l'image verso depuis la galerie."),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () =>
                                                        Navigator.of(ctx).pop(),
                                                    child: const Text("OK"),
                                                  ),
                                                ],
                                              );
                                            },
                                          );
                                          setState(() {}); // Update UI to show "Verso"
                                        }
                                      } else {
                                        final xfile = await imagePicker.pickImage(
                                          source: ImageSource.gallery,
                                        );
                                        if (xfile != null) {
                                          final versoBytes = await xfile.readAsBytes();
                                          final mergedBytes = _mergeBytesVertically(
                                              _cinRectoWebImage!, versoBytes);
                                          Navigator.push(context,
                                              MaterialPageRoute(builder: (ctx) {
                                                return RecognizerCinScreen(
                                                    image: null, webImage: mergedBytes);
                                              }));
                                          _cinRectoWebImage = null;
                                        }
                                      }
                                    } else {
                                      // For Passport mode, simply pick one image.
                                      final xfile =
                                      await imagePicker.pickImage(source: ImageSource.gallery);
                                      if (xfile != null) {
                                        final file = File(xfile.path);
                                        final webImage = await xfile.readAsBytes();
                                        Navigator.push(context,
                                            MaterialPageRoute(builder: (ctx) {
                                              return Recognizerscreen(
                                                  image: file, webImage: webImage);
                                            }));
                                      }
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
                    // Landscape mode: vertical button column on the right
                      Positioned(
                        top: 0,
                        bottom: 0,
                        right: 0,
                        child: Container(
                          width: 80,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              InkWell(
                                onTap: () async {
                                  await toggleTorchWeb(!_isFlashOn);
                                  setState(() => _isFlashOn = !_isFlashOn);
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
                                  if (_isCINSelected) {
                                    if (_cinRectoWebImage == null) {
                                      final xfile =
                                      await imagePicker.pickImage(source: ImageSource.gallery);
                                      if (xfile != null) {
                                        _cinRectoWebImage = await xfile.readAsBytes();
                                        await showDialog(
                                          context: context,
                                          builder: (ctx) {
                                            return AlertDialog(
                                              title: const Text("Recto Capturé"),
                                              content: const Text(
                                                  "Veuillez maintenant sélectionner l'image verso depuis la galerie."),
                                              actions: [
                                                TextButton(
                                                  onPressed: () =>
                                                      Navigator.of(ctx).pop(),
                                                  child: const Text("OK"),
                                                ),
                                              ],
                                            );
                                          },
                                        );
                                        setState(() {}); // Update UI to show "Verso"
                                      }
                                    } else {
                                      final xfile =
                                      await imagePicker.pickImage(source: ImageSource.gallery);
                                      if (xfile != null) {
                                        final versoBytes = await xfile.readAsBytes();
                                        final mergedBytes = _mergeBytesVertically(
                                            _cinRectoWebImage!, versoBytes);
                                        Navigator.push(context,
                                            MaterialPageRoute(builder: (ctx) {
                                              return RecognizerCinScreen(
                                                  image: null, webImage: mergedBytes);
                                            }));
                                        _cinRectoWebImage = null;
                                      }
                                    }
                                  } else {
                                    final xfile =
                                    await imagePicker.pickImage(source: ImageSource.gallery);
                                    if (xfile != null) {
                                      final file = File(xfile.path);
                                      final webImage = await xfile.readAsBytes();
                                      Navigator.push(context,
                                          MaterialPageRoute(builder: (ctx) {
                                            return Recognizerscreen(
                                                image: file, webImage: webImage);
                                          }));
                                    }
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

                    // 5. Dotted-rectangle overlay (drawn above all content)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            return CustomPaint(
                              painter: _DottedFramePainter(
                                orientation: orientation,
                                maxWidth: constraints.maxWidth,
                                maxHeight: constraints.maxHeight,
                              ),
                            );
                          },
                        ),
                      ),
                    ),

                    // 6. Tip overlay message inside the dotted frame
                    if (_showTipOverlay)
                      Positioned.fill(
                        child: Center(
                          child: FractionallySizedBox(
                            widthFactor: orientation == Orientation.portrait ? 0.95 : 0.75,
                            heightFactor: orientation == Orientation.portrait ? 0.35 : 0.80,
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.black54.withOpacity(0.8),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Text(
                                    "Si vous souhaitez prendre la photo en tournant le téléphone, activez l'auto-rotation. N'oubliez pas!",
                                    style: TextStyle(color: Colors.white, fontSize: 16),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 10),
                                  ElevatedButton(
                                    onPressed: () {
                                      setState(() {
                                        _showTipOverlay = false;
                                      });
                                    },
                                    child: const Text("OK"),
                                  ),
                                ],
                              ),
                            ),
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
/// This painter draws a dotted rectangle in the center,
/// sized differently for portrait vs. landscape.
class _DottedFramePainter extends CustomPainter {
  final Orientation orientation;
  final double maxWidth;
  final double maxHeight;

  _DottedFramePainter({
    required this.orientation,
    required this.maxWidth,
    required this.maxHeight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    double rectWidth;
    double rectHeight;

    // Adjust rectangle size based on orientation.
    if(kIsWeb){
      if (orientation == Orientation.portrait) {
        rectWidth = maxWidth * 0.95;    // 80% of the width
        rectHeight = maxHeight * 0.35;    // 35% of the height
      } else {
        rectWidth = maxWidth * 0.50;      // 60% of the width
        rectHeight = maxHeight * 0.80;    // 50% of the height
      }
    }else{
      if (orientation == Orientation.portrait) {
        rectWidth = maxWidth * 0.95;    // 80% of the width
        rectHeight = maxHeight * 0.35;    // 35% of the height
      } else {
        rectWidth = maxWidth * 0.75;      // 60% of the width
        rectHeight = maxHeight * 0.80;    // 50% of the height
      }
    }

    // Calculate rectangle edges
    final left = (maxWidth - rectWidth) / 2;
    final top = (maxHeight - rectHeight) / 2;
    final right = left + rectWidth;
    final bottom = top + rectHeight;

    // Define the paint style for the dashed frame.
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    // Set dash parameters.
    double dashWidth = 10, dashSpace = 6;

    // Draw dashed lines on each edge.
    _drawDashedLine(canvas, Offset(left, top), Offset(right, top), paint, dashWidth, dashSpace);
    _drawDashedLine(canvas, Offset(right, top), Offset(right, bottom), paint, dashWidth, dashSpace);
    _drawDashedLine(canvas, Offset(right, bottom), Offset(left, bottom), paint, dashWidth, dashSpace);
    _drawDashedLine(canvas, Offset(left, bottom), Offset(left, top), paint, dashWidth, dashSpace);
  }

  // Helper function to draw a dashed line between two points.
  void _drawDashedLine(
      Canvas canvas,
      Offset start,
      Offset end,
      Paint paint,
      double dashWidth,
      double dashSpace,
      ) {
    final totalDistance = (end - start).distance;
    final delta = end - start;
    final direction = delta / delta.distance; // Normalize the vector manually

    double distanceCovered = 0;

    while (distanceCovered < totalDistance) {
      final currentStart = start + direction * distanceCovered;
      final currentEnd = start + direction * (distanceCovered + dashWidth);
      canvas.drawLine(currentStart, currentEnd, paint);
      distanceCovered += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}


