import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:ocr_canner/passport_service.dart';
import 'torch_helper.dart';
import 'dart:convert';
import 'termesdeconfidentialitees.dart';
import 'database.dart';
import 'package:image/image.dart' as img;

class RecognizerCinScreen extends StatefulWidget {
  final File? image;        // The merged image (Recto + Verso) for mobile
  final Uint8List? webImage; // Merged image bytes for web

  const RecognizerCinScreen({
    Key? key,
    required this.image,
    required this.webImage,
  }) : super(key: key);

  @override
  State<RecognizerCinScreen> createState() => _RecognizerCinScreenState();
}

class _RecognizerCinScreenState extends State<RecognizerCinScreen> {
  Map<String, dynamic>? cinData;   // Extracted data
  bool isLoading = false;
  bool termsAccepted = false;

  final String apiKey = 'dabba084305fcd734ce9b3338179dd63';

  // Label translations
  final Map<String, Map<String, String>> translations = {
    'FR': {
      'id_number': 'Numéro ID',
      'surname': 'Nom',
      'given_names': 'Prénom(s)',
      'birth_date': 'Date de naissance',
      'birth_place': 'Lieu de naissance',
      'gender': 'Genre',
      'country': 'Pays',
      'issuance_date': 'Date d\'émission',
      'expiry_date': 'Date d\'expiration',
      'mrz1': 'MRZ Ligne 1',
      'mrz2': 'MRZ Ligne 2',
    },
    'EN': {
      'id_number': 'ID Number',
      'surname': 'Surname',
      'given_names': 'Given Names',
      'birth_date': 'Date of Birth',
      'birth_place': 'Place of Birth',
      'gender': 'Gender',
      'country': 'Country',
      'issuance_date': 'Issuance Date',
      'expiry_date': 'Expiry Date',
      'mrz1': 'MRZ Line 1',
      'mrz2': 'MRZ Line 2',
    }
  };
  Map<String, String> labels = {};

  // Text controllers for fields
  final Map<String, TextEditingController> controllers = {};

  @override
  void initState() {
    super.initState();
    disableTorchWeb();
    _analyzeImage();
  }

  // Submit the merged document image to Mindee API
  Future<String?> _submitDocument() async {
    if (widget.image == null && widget.webImage == null) {
      debugPrint("No image for analysis");
      return null;
    }
    final url = Uri.parse(
        'https://api.mindee.net/v1/products/mindee/international_id/v2/predict_async');

    try {
      var request = http.MultipartRequest('POST', url)
        ..headers['Authorization'] = 'Token $apiKey';

      if (kIsWeb && widget.webImage != null) {
        final base64Image = base64Encode(widget.webImage!);
        request.fields['document'] = base64Image;
      } else if (widget.image != null && await widget.image!.exists()) {
        request.files.add(
            await http.MultipartFile.fromPath('document', widget.image!.path));
      } else {
        debugPrint("File does not exist");
        return null;
      }

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();

      if (response.statusCode == 202) {
        final data = jsonDecode(responseBody);
        return data['job']['id'];
      } else {
        debugPrint('API Error: ${response.statusCode} - $responseBody');
        return null;
      }
    } catch (e) {
      debugPrint('Error: $e');
      return null;
    }
  }

  // Fetch extracted data from Mindee API
  Future<void> _fetchDocumentData(String jobId) async {
    final url = Uri.parse(
      'https://api.mindee.net/v1/products/mindee/international_id/v2/documents/queue/$jobId',
    );

    try {
      final resp = await http.get(url, headers: {'Authorization': 'Token $apiKey'});
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final prediction = data['document']['inference']['prediction'];

        setState(() {
          cinData = {
            'id_number': prediction['document_number']?['value'] ?? '**',
            'surname': prediction['surnames']?.map((e) => e['value']).join(' ') ?? '**',
            'given_names': prediction['given_names']?.map((e) => e['value']).join(' ') ?? '**',
            'birth_date': prediction['birth_date']?['value'] ?? '**',
            'gender': prediction['sex']?['value'] ?? '**',
            'country': prediction['country_of_issue']?['value'] ?? '**',
            'expiry_date': prediction['expiry_date']?['value'] ?? '**',
            'mrz1': prediction['mrz_line1']?['value'] ?? '**',
            'mrz2': prediction['mrz_line2']?['value'] ?? '**',
            'mrz3': prediction['mrz_line3']?['value'] ?? '**',
            'address': prediction['address']?['value'] ?? '**',
            'birth_place': prediction['birth_place']?['value'] ?? '**',
            'state_of_issue': prediction['state_of_issue']?['value'] ?? '**',
            'nationality': prediction['nationality']?['value'] ?? '**',
            'personal_number': prediction['personal_number']?['value'] ?? '**',
            'issue_date': prediction['issue_date']?['value'] ?? '**'
          };

          cinData!.forEach((key, value) {
            controllers[key] = TextEditingController(text: value);
          });

          labels = translations['FR'] ?? {};
        });
      } else {
        debugPrint('Data fetch error: ${resp.statusCode} - ${resp.body}');
      }
    } catch (e) {
      debugPrint("Error: $e");
    }
  }

  // Analyze the merged image via API
  Future<void> _analyzeImage() async {
    setState(() => isLoading = true);
    final jobId = await _submitDocument();
    if (jobId != null) {
      await Future.delayed(const Duration(seconds: 5));
      await _fetchDocumentData(jobId);
    }
    setState(() => isLoading = false);
  }

  // Validate inputs before submitting
  bool _validateInputs() {
    for (var ctrl in controllers.values) {
      if (ctrl.text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Veuillez remplir tous les champs")),
        );
        return false;
      }
    }
    return true;
  }

  void _submitData() async {
    if (!termsAccepted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Vous devez accepter les termes de confidentialité")),
      );
      return;
    }
    if (!_validateInputs()) return;

    setState(() => isLoading = true);
    final Map<String, dynamic> finalData = {};
    controllers.forEach((key, ctrl) {
      finalData[key] = ctrl.text;
    });

    debugPrint("Données soumises : $finalData");

    try {
      if (kIsWeb) {
        await PassportService.savePassportData(finalData);
      } else {
        await MongoDatabase.connect();
        await MongoDatabase.insertData(finalData);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Données envoyées avec succès!")),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Erreur lors de l'envoi des données: $e")),
      );
    } finally {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recognizer Cin'),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      backgroundColor: Colors.black,
      body: Column(
        children: [
          // Display the merged image (or single image) with InteractiveViewer
          SizedBox(
            height: MediaQuery.of(context).size.height / 3,
            width: double.infinity,
            child: InteractiveViewer(
              panEnabled: true,
              minScale: 1.0,
              maxScale: 5.0,
              child: Image(
                image: kIsWeb && widget.webImage != null
                    ? MemoryImage(widget.webImage!)
                    : widget.image != null
                    ? FileImage(widget.image!)
                    : const AssetImage('assets/placeholder.png')
                as ImageProvider,
                fit: BoxFit.contain,
              ),
            ),
          ),
          Expanded(
            child: isLoading
                ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            )
                : cinData != null
                ? Padding(
              padding: const EdgeInsets.all(16.0),
              child: ListView(
                children: [
                  ...cinData!.keys.map((key) {
                    return TextField(
                      controller: controllers[key],
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: labels[key] ?? key,
                        labelStyle: const TextStyle(color: Colors.white70),
                        enabledBorder: const UnderlineInputBorder(
                            borderSide: BorderSide(color: Colors.grey)),
                        focusedBorder: const UnderlineInputBorder(
                            borderSide: BorderSide(color: Colors.blue)),
                      ),
                    );
                  }).toList(),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Checkbox(
                        value: termsAccepted,
                        checkColor: Colors.black,
                        fillColor: MaterialStateProperty.all(Colors.white),
                        onChanged: (bool? val) {
                          setState(() => termsAccepted = val ?? false);
                        },
                      ),
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (ctx) => TermesDeConfidentialiteesScreen()),
                          );
                        },
                        child: RichText(
                          text: const TextSpan(
                            style: TextStyle(color: Colors.white),
                            children: [
                              TextSpan(text: "J'accepte les "),
                              TextSpan(
                                text: "termes de confidentialité",
                                style: TextStyle(color: Colors.blue),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _submitData,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text("Confirmer et envoyer"),
                  ),
                ],
              ),
            )
                : const Center(
              child: Text(
                'Aucune donnée extraite',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
