import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class PassportService {
  // The base URL of your Node.js server
  static const String _baseUrl = 'https://backend-api-a9tm.onrender.com'; // Update to your server's URL if needed

  // Function to send the entire passport data to the server
  static Future<void> savePassportData(Map<String, dynamic> passportData) async {
    final url = Uri.parse('$_baseUrl/savePassportData');
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(passportData), // Send the entire map
    );

    if (response.statusCode == 200) {
      if (kDebugMode) {
        print('Passport data saved successfully!');
      }
    } else {
      if (kDebugMode) {
        print('Failed to save passport data');
      }
    }
  }
}
