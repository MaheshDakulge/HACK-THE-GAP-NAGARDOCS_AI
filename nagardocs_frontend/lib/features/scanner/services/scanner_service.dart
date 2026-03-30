import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:flutter/services.dart';

class ScannerService {
  Future<List<String>?> scanDocument() async {
    try {
      final List<String>? pictures = await CunningDocumentScanner.getPictures();
      return pictures;
    } on PlatformException {
      // Permission denied or other platform error
      return null;
    } catch (e) {
      // Other errors
      return null;
    }
  }
}
