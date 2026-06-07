import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

Future<void> main() async {
  var result = await FilePicker.pickFiles();
  print(result);
}
