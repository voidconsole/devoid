import 'dart:io';
import 'dart:typed_data';
import 'package:devoid/screens/confirmation_screen.dart';
import 'package:devoid/theme/app_colors.dart';
import 'package:devoid/widgets/dashed_squircle_border.dart';
import 'package:devoid/widgets/squircle_border.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:exif/exif.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';

class HandshakeScreen extends StatefulWidget {
  const HandshakeScreen({Key? key}) : super(key: key);

  @override
  State<HandshakeScreen> createState() => _HandshakeScreenState();
}

class _HandshakeScreenState extends State<HandshakeScreen> {
  File? _image;
  Uint8List? _imageBytes; // For web/desktop
  Map<String, dynamic>? _metadata;
  bool _isLoading = false;
  final _textController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _textController.addListener(() {
      if (_textController.text.length >= 90) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => ConfirmationScreen(
              textCode:  _textController.text,
            ),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _getImage() async {
    setState(() {
      _isLoading = true;
      _metadata = null;
    });

    try {
      if (kIsWeb) {
        FilePickerResult? result = await FilePicker.platform.pickFiles(
          type: FileType.image,
          allowMultiple: false,
        );

        if (result != null && result.files.single.bytes != null) {
          _imageBytes = result.files.single.bytes!;
          await _extractMetadata();
        }
      } else if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
        FilePickerResult? result = await FilePicker.platform.pickFiles(
          type: FileType.image,
          allowMultiple: false,
        );

        if (result != null) {
          if (result.files.single.bytes != null) {
            _imageBytes = result.files.single.bytes!;
          } else if (result.files.single.path != null) {
            _image = File(result.files.single.path!);
            _imageBytes = await _image!.readAsBytes();
          }
          await _extractMetadata();
        }
      } else {
        final picker = ImagePicker();
        final pickedImage = await picker.pickImage(source: ImageSource.gallery);

        if (pickedImage != null) {
          _image = File(pickedImage.path);
          _imageBytes = await _image!.readAsBytes();
          await _extractMetadata();
        }
      }

      setState(() {
        _isLoading = false;
      });

      if (mounted && _metadata != null) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => ConfirmationScreen(
              metadata: _metadata,
            ),
          ),
        );
      }
    } catch (e) {
      print('Error picking image: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _extractMetadata() async {
    if (_imageBytes == null) {
      return;
    }
    try {
      final data = await readExifFromBytes(_imageBytes!);
      final Map<String, dynamic> attributes =
          data.map((key, value) => MapEntry(key, value.printable));

      setState(() {
        _metadata = attributes;
      });
    } catch (e) {
      print('Error extracting metadata: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Hero(
                tag: 'square',
                child: Container(
                  width: 35,
                  height: 35,
                  decoration: ShapeDecoration(
                    color: primaryColor,
                    shape: SquircleBorder(radius: 20),
                  ),
                ),
              ),
              const SizedBox(height: 48),
              Text(
                'Upload your handshake to\nconnect to the void\nnetwork',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: primaryColor,
                  fontSize: 26,
                  fontWeight: FontWeight.w400,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 64),
              GestureDetector(
                onTap: _isLoading ? null : _getImage,
                child: Container(
                  width: double.infinity,
                  height: 160,
                  decoration: ShapeDecoration(
                    color: primaryColor.withAlpha(10),
                    shape: DashedSquircleBorder(
                      side: BorderSide(
                        color: primaryColor.withAlpha(77),
                        width: 2,
                      ),
                      radius: 50,
                      dashLength: 8,
                      dashGap: 6,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_isLoading)
                        CircularProgressIndicator(
                          color: primaryColor.withAlpha(128),
                        )
                      else
                        Text(
                          'Drag and drop the handshake\nor click to browse files',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: primaryColor.withAlpha(128),
                            fontSize: 18,
                            height: 1.5,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'OR',
                style: TextStyle(
                  color: primaryColor.withAlpha(128),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 24),
              Container(
                decoration: ShapeDecoration(
                  shape: SquircleBorder(
                    side: BorderSide(
                      color: primaryColor.withAlpha(77),
                    ),
                    radius: 22,
                  ),
                ),
                child: TextField(
                  controller: _textController,
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    hintText: "Type in your handshake's key",
                    hintStyle: TextStyle(
                      color: primaryColor.withAlpha(77),
                      fontSize: 16,
                    ),
                    filled: true,
                    fillColor: primaryColor.withAlpha(10),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                  ),
                  style: TextStyle(
                    color: primaryColor,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
