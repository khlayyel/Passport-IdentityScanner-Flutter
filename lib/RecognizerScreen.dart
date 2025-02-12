import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'termesdeconfidentialitees.dart';

class Recognizerscreen extends StatefulWidget {
  final File image;

  Recognizerscreen(this.image);

  @override
  State<Recognizerscreen> createState() => _RecognizerscreenState();
}

class _RecognizerscreenState extends State<Recognizerscreen> {
  Map<String, dynamic>? passportData;
  bool isLoading = false;
  bool termsAccepted = false;
  String? detectedCountry;
  Map<String, String> labels = {};

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
    _analyzeImage();
  }

  Future<void> _analyzeImage() async {
    setState(() {
      isLoading = true;
    });

    final url = Uri.parse('https://api.mindee.net/v1/products/mindee/passport/v1/predict');
    const apiKey = 'c5286babbf94955ff5664fd4b91638b5';

    try {
      if (!await widget.image.exists()) {
        debugPrint('Erreur : Fichier image introuvable.');
        return;
      }

      var request = http.MultipartRequest('POST', url)
        ..headers['Authorization'] = 'Token $apiKey'
        ..headers['Accept'] = 'application/json'
        ..files.add(await http.MultipartFile.fromPath('document', widget.image.path));

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();

      if (response.statusCode == 201) {
        final data = jsonDecode(responseBody);
        final prediction = data['document']['inference']['prediction'];

        setState(() {
          detectedCountry = prediction['country']?['value'] ?? 'FR';
          labels = translations[detectedCountry] ?? translations['FR']!;

          passportData = {
            'id_number': prediction['id_number']?['value'] ?? '',
            'surname': prediction['surname']?['value'] ?? '',
            'given_names': (prediction['given_names'] as List?)
                ?.map((e) => e['value'])
                .join(' ') ??
                '',
            'birth_date': prediction['birth_date']?['value'] ?? '',
            'birth_place': prediction['birth_place']?['value'] ?? '',
            'gender': prediction['gender']?['value'] ?? '',
            'country': prediction['country']?['value'] ?? '',
            'issuance_date': prediction['issuance_date']?['value'] ?? '',
            'expiry_date': prediction['expiry_date']?['value'] ?? '',
            'mrz1': prediction['mrz1']?['value'] ?? '',
            'mrz2': prediction['mrz2']?['value'] ?? '',
          };

          // Initialiser les contrôleurs
          passportData!.forEach((key, value) {
            controllers[key] = TextEditingController(text: value);
          });
        });
      } else {
        debugPrint('Erreur API : ${response.statusCode} - ${responseBody}');
      }
    } catch (e) {
      debugPrint('Erreur: $e');
    }

    setState(() {
      isLoading = false;
    });
  }

  void _submitData() {
    if (!termsAccepted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Vous devez accepter les termes de confidentialité")),
      );
      return;
    }

    final submittedData = controllers.map((key, controller) => MapEntry(key, controller.text));

    print("Données soumises : $submittedData");

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Données envoyées avec succès!")),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blueAccent,
        title: const Text('Recognizer'),
      ),
      body: Column(
        children: [
          Container(
            height: MediaQuery.of(context).size.height / 3,
            width: double.infinity,
            decoration: BoxDecoration(
              image: DecorationImage(
                image: kIsWeb
                    ? MemoryImage(Uint8List.fromList(widget.image.readAsBytesSync()))
                    : FileImage(widget.image) as ImageProvider,
                fit: BoxFit.cover,
              ),
            ),
          ),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : passportData != null
                ? Padding(
              padding: const EdgeInsets.all(16.0),
              child: ListView(
                children: [
                  ...passportData!.keys.map((key) => TextField(
                    controller: controllers[key],
                    decoration: InputDecoration(labelText: labels[key] ?? key),
                  )),
                  SizedBox(height: 16),
                  Row(
                    children: [
                      Checkbox(
                        value: termsAccepted,
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
                        child: Text(
                          "J'accepte les termes de confidentialité",
                          style: TextStyle(
                            color: Colors.blue,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _submitData,
                    child: const Text('Confirmer et envoyer'),
                  ),
                ],
              ),
            )
                : const Center(child: Text('Aucune donnée extraite')),
          ),
        ],
      ),
    );
  }
}
