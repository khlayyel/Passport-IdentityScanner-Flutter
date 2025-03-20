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
  final File? image;  // Garde File pour mobile
  final Uint8List? webImage;  // Ajoute Uint8List pour web

  const RecognizerCinScreen({super.key, this.image, this.webImage});

  @override
  State<RecognizerCinScreen> createState() => _RecognizerCinScreenState();
}

class _RecognizerCinScreenState extends State<RecognizerCinScreen> {
  Map<String, dynamic>? cinData;
  bool isLoading = false;
  bool termsAccepted = false;
  String? detectedCountry;
  Map<String, String> labels = {};
  final String apiKey = 'ade521d63f9926e7e30af449a82e9a73';

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

  // Contrôleurs de texte
  final Map<String, TextEditingController> controllers = {};

  @override
  void initState() {
    super.initState();

    disableTorchWeb();
    _analyzeImage();
  }


  Future<String?> _submitDocument() async {
    final url = Uri.parse('https://api.mindee.net/v1/products/mindee/international_id/v2/predict_async');
    try {
      var request = http.MultipartRequest('POST', url)
        ..headers['Authorization'] = 'Token $apiKey';

      if (kIsWeb && widget.webImage != null) {
        // Envoie l'image sans la modifier pour le web
        String base64Image = base64Encode(widget.webImage!);
        request.fields['document'] = base64Image;
      } else if (widget.image != null && await widget.image!.exists()) {
        request.files.add(await http.MultipartFile.fromPath('document', widget.image!.path));
      } else {
        debugPrint('Erreur : Aucune image valide.');
        return null;
      }

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();

      if (response.statusCode == 202) {
        final data = jsonDecode(responseBody);
        return data['job']['id'];
      } else {
        debugPrint('Erreur API : ${response.statusCode} - $responseBody');
        return null;
      }
    } catch (e) {
      debugPrint('Erreur : $e');
      return null;
    }
  }

  Future<void> _fetchDocumentData(String jobId) async {
    final url = Uri.parse('https://api.mindee.net/v1/products/mindee/international_id/v2/documents/queue/$jobId');

    try {
      final response = await http.get(url, headers: {'Authorization': 'Token $apiKey'});
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
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

          // Populate labels for UI
          labels = translations['FR'] ?? {}; // Set labels for French translations
        });
      } else {
        debugPrint('Erreur récupération données : ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      debugPrint('Erreur : $e');
    }
  }



  Future<void> _analyzeImage() async {
    setState(() {
      isLoading = true;
    });

    String? jobId = await _submitDocument();
    if (jobId != null) {
      await Future.delayed(Duration(seconds: 5));
      await _fetchDocumentData(jobId);
    }
    setState(() => isLoading = false);
  }

  // Valider les champs avant soumission
  bool _validateInputs() {
    for (var controller in controllers.values) {
      if (controller.text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Veuillez remplir tous les champs")),
        );
        return false;
      }
    }
    return true;
  }

  void _submitData() async {
    if (!termsAccepted) {
      if (!mounted) return; // Check if the widget is still in the tree
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text("Vous devez accepter les termes de confidentialité")),
      );
      return;
    }

    if (!_validateInputs()) {
      return;
    }

    setState(() {
      isLoading = true; // Show loading indicator
    });

    // Récupérer les données modifiées
    final Map<String, dynamic> submittedData = {};
    controllers.forEach((key, controller) {
      submittedData[key] = controller.text;
    });

    // Afficher les données soumises dans la console (pour le débogage)
    debugPrint("Données soumises : $submittedData");

    // Envoyer les données à MongoDB
    try {
      if (kIsWeb) {
        // Si c'est le Web, utiliser le service backend avec l'API
        await PassportService.savePassportData(submittedData);
      } else {
        // Si c'est sur mobile, utiliser MongoDB localement avec mongo_dart
        await MongoDatabase.connect(); // Connect to MongoDB
        await MongoDatabase.insertData(submittedData); // Insert data
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Données envoyées avec succès!")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Erreur lors de l'envoi des données: $e")),
      );
    }
    finally {
      if (mounted) {
        setState(() {
          isLoading = false; // Hide loading indicator
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text(
          'Recognizer Cin',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      backgroundColor: Colors.black, // Arrière-plan global
      body: Column(
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height / 3,
            width: double.infinity,
            child: InteractiveViewer(
              panEnabled: true,
              boundaryMargin: const EdgeInsets.all(20),
              minScale: 1.0,
              maxScale: 5.0,
              child: Image(
                image: kIsWeb && widget.webImage != null
                    ? MemoryImage(widget.webImage!)
                    : widget.image != null
                    ? FileImage(widget.image!) as ImageProvider
                    : const AssetImage('assets/placeholder.png'),
                fit: BoxFit.contain,
              ),
            ),
          ),
          Expanded(
            child: isLoading
                ? const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white), // Style du loading
                ))
                : cinData != null
                ? Padding(
              padding: const EdgeInsets.all(16.0),
              child: ListView(
                children: [
                  ...cinData!.keys.map((key) => TextField(
                    controller: controllers[key],
                    style: const TextStyle(color: Colors.white), // Texte saisi en blanc
                    decoration: InputDecoration(
                      labelText: labels[key] ?? key,
                      labelStyle: const TextStyle(
                          color: Colors.white70), // Titre en blanc
                      enabledBorder: const UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.grey)),
                      focusedBorder: const UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.blue)),
                    ),
                  )),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Checkbox(
                        value: termsAccepted,
                        checkColor: Colors.black, // Couleur de la coche
                        fillColor: MaterialStateProperty.all(Colors.white), // Fond checkbox
                        onChanged: (bool? newValue) {
                          setState(() {
                            termsAccepted = newValue ?? false;
                          });
                        },
                      ),
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) =>
                                    TermesDeConfidentialiteesScreen()),
                          );
                        },
                        child: RichText(
                          text: TextSpan(
                            style: TextStyle(color: Colors.white),
                            children: [
                              const TextSpan(text: "J'accepte les "),
                              TextSpan(
                                text: "termes de confidentialité",
                                style: const TextStyle(
                                  color: Colors.blue, // Couleur de lien classique
                                  // Épaisseur du trait
                                ),
                                recognizer: TapGestureRecognizer()
                                  ..onTap = () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => TermesDeConfidentialiteesScreen(),
                                      ),
                                    );
                                  },
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
                    child: const Text('Confirmer et envoyer'),
                  ),
                ],
              ),
            )
                : const Center(
                child: Text('Aucune donnée extraite',
                    style: TextStyle(color: Colors.white))), // Texte en blanc
          ),
        ],
      ),
    );
  }
}