import 'package:flutter/material.dart';

class TermesDeConfidentialiteesScreen extends StatelessWidget {
  const TermesDeConfidentialiteesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Termes de Confidentialité")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Politique de Confidentialité",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 10),
            Text(
              "Nous collectons et stockons vos données pour une durée de 5 ans conformément aux réglementations en vigueur. "
                  "Ces informations peuvent être utilisées pour améliorer nos services et répondre aux obligations légales.",
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: Text("Fermer"),
            ),
          ],
        ),
      ),
    );
  }
}
