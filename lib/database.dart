import 'package:flutter/foundation.dart';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:flutter/material.dart';

class MongoDatabase {
  static late Db db;
  static late DbCollection collection;


  static Future<void> connect() async {
    if (!kIsWeb) {
      try {
        const connectionString = 'mongodb+srv://khlayel:1959@cluster0.p1kbi.mongodb.net/Hotix?retryWrites=true&w=majority&appName=Cluster0';

        debugPrint("Connecting to MongoDB...");
        db = await Db.create(connectionString);
        await db.open();
        debugPrint("✅ Connected to MongoDB!");

        // Replace with your collection name
        collection = db.collection("Scanner");
        debugPrint("Collection initialized: ${collection.collectionName}");
      } catch (e) {
        debugPrint("❌ MongoDB Connection Error: $e");
      }
    }
  }


  // Method to insert data into the collection
  static Future<void> insertData(Map<String, dynamic> data) async {
    if (db.isConnected) {
      try {
        debugPrint("Inserting data: $data");
        await collection.insert(data);
        debugPrint("✅ Data inserted successfully!");
      } catch (e) {
        debugPrint("❌ Error inserting data: $e");
      }
    } else {
      debugPrint("❌ MongoDB is not connected. Please connect first.");
    }
  }
}
