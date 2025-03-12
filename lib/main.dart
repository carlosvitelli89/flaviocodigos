import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // Importação do Firestore
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Captura e Upload de Fotos',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const MyHomePage(title: 'Captura e Upload de Fotos'),
    );
  }
}

class ImageData {
  File imageFile;
  Position? position;
  String? imageUrl;

  ImageData({required this.imageFile, this.position, this.imageUrl});
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  List<ImageData> _imageDataList = [];
  final ImagePicker _picker = ImagePicker();
  bool isUploading = false;

  // Solicita permissão para acessar a localização
  Future<bool> _requestLocationPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  // Obtém a localização atual do usuário
  Future<Position?> _getCurrentLocation() async {
    bool hasPermission = await _requestLocationPermission();
    if (!hasPermission) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Permissão de localização negada')),
      );
      return null;
    }

    try {
      return await Geolocator.getCurrentPosition();
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao obter localização: $e')));
      return null;
    }
  }

  // Pega imagem da galeria
  Future<void> _pickImageFromGallery() async {
    final XFile? pickedFile = await _picker.pickImage(
      source: ImageSource.gallery,
    );
    if (pickedFile != null) {
      Position? position = await _getCurrentLocation();
      setState(() {
        _imageDataList.add(
          ImageData(imageFile: File(pickedFile.path), position: position),
        );
      });
    }
  }

  // Tira foto com a câmera
  Future<void> _getImageFromCamera() async {
    final XFile? pickedFile = await _picker.pickImage(
      source: ImageSource.camera,
    );
    if (pickedFile != null) {
      Position? position = await _getCurrentLocation();
      setState(() {
        _imageDataList.add(
          ImageData(imageFile: File(pickedFile.path), position: position),
        );
      });
    }
  }

  void _removeImage(int index) {
    setState(() {
      _imageDataList.removeAt(index);
    });
  }

  void _removeAllImages() {
    setState(() {
      _imageDataList.clear();
    });
  }

  Future<void> _uploadAllImages() async {
    if (_imageDataList.isEmpty) return;

    setState(() {
      isUploading = true;
    });

    for (var imageData in _imageDataList) {
      try {
        final fileName = DateTime.now().millisecondsSinceEpoch.toString();
        final ref = FirebaseStorage.instance.ref().child(
          'uploads/$fileName.jpg',
        );
        await ref.putFile(imageData.imageFile);

        // Obter a URL da imagem após o upload
        final imageUrl = await ref.getDownloadURL();

        // Agora, salvar a URL e a localização no Firestore
        await FirebaseFirestore.instance.collection('images').add({
          'imageUrl': imageUrl,
          'latitude': imageData.position?.latitude,
          'longitude': imageData.position?.longitude,
          'timestamp':
              FieldValue.serverTimestamp(), // Opcional: adicionar um timestamp
        });

        // Atualizar o ImageData com a URL da imagem
        setState(() {
          imageData.imageUrl = imageUrl;
        });
      } catch (e) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Erro no upload: $e")));
      }
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("Upload concluído!")));

    setState(() {
      isUploading = false;
    });
  }

  void _showImageDialog(BuildContext context, ImageData imageData) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (BuildContext context) {
          return Scaffold(
            appBar: AppBar(title: const Text('Visualizar Imagem')),
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.file(imageData.imageFile),
                  const SizedBox(height: 20),
                  if (imageData.position != null)
                    Text(
                      'Localização:\nLatitude: ${imageData.position!.latitude}, Longitude: ${imageData.position!.longitude}',
                      textAlign: TextAlign.center,
                    )
                  else
                    const Text('Localização não disponível.'),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: <Widget>[
          if (_imageDataList.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: 'Remover Todas as Fotos',
              onPressed: _removeAllImages,
            ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: _getImageFromCamera,
                  child: const Text('Tirar Foto'),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _pickImageFromGallery,
                  child: const Text('Escolher da Galeria'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: isUploading ? null : _uploadAllImages,
              child:
                  isUploading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Upload Todas Imagens'),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 150,
              child:
                  _imageDataList.isEmpty
                      ? const Text('Nenhuma foto tirada ainda.')
                      : ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _imageDataList.length,
                        itemBuilder: (BuildContext context, int index) {
                          final imageData = _imageDataList[index];
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8.0,
                            ),
                            child: Stack(
                              children: [
                                GestureDetector(
                                  onTap:
                                      () =>
                                          _showImageDialog(context, imageData),
                                  child: AspectRatio(
                                    aspectRatio: 1.0,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        border: Border.all(color: Colors.grey),
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.zero,
                                        child: Image.file(
                                          imageData.imageFile,
                                          width: 150,
                                          height: 150,
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  top: 0,
                                  right: 0,
                                  child: IconButton(
                                    icon: const Icon(
                                      Icons.close,
                                      color: Colors.red,
                                    ),
                                    onPressed: () => _removeImage(index),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
            ),
          ],
        ),
      ),
    );
  }
}
