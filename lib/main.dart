import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import 'dart:io';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI 기반 PCB 불량 검사',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0D1117),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00E676), // PCB 회로 느낌의 그린
          brightness: Brightness.dark,
        ),
        fontFamily: 'Roboto',
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF161B22),
          elevation: 0,
          centerTitle: true,
        ),
      ),
      home: const HomePage(),
    );
  }
}

enum InspectionStatus { idle, loading, normal, defect, error }

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String _message = 'PCB 이미지를 업로드하여 검사를 시작하세요';
  double? _confidence;
  InspectionStatus _status = InspectionStatus.idle;
  File? _imageFile;
  Interpreter? _interpreter;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadModel();
  }

  Future<void> _loadModel() async {
    try {
      _interpreter = await Interpreter.fromAsset('assets/model.tflite');
      // ignore: avoid_print
      print('모델 로드 성공!');
    } catch (e) {
      // ignore: avoid_print
      print('모델 로드 실패: $e');
      setState(() {
        _status = InspectionStatus.error;
        _message = '모델 로드 실패';
      });
    }
  }

  Future<void> _selectImage() async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.gallery,
      );

      if (pickedFile == null) {
        setState(() {
          _status = InspectionStatus.idle;
          _message = '이미지 선택이 취소되었습니다';
        });
        return;
      }

      _imageFile = File(pickedFile.path);

      setState(() {
        _status = InspectionStatus.loading;
        _message = '분석 중...';
        _confidence = null;
      });

      await _runInference();
    } catch (e) {
      setState(() {
        _status = InspectionStatus.error;
        _message = '오류 발생: $e';
      });
    }
  }

  Future<void> _runInference() async {
    if (_imageFile == null || _interpreter == null) {
      setState(() {
        _status = InspectionStatus.error;
        _message = '이미지 또는 모델이 없습니다';
      });
      return;
    }

    try {
      final imageBytes = await _imageFile!.readAsBytes();
      img.Image? image = img.decodeImage(imageBytes);

      if (image == null) {
        setState(() {
          _status = InspectionStatus.error;
          _message = '이미지 처리 실패';
        });
        return;
      }

      img.Image resizedImage = img.copyResize(image, width: 224, height: 224);

      var input = List.generate(
        224,
        (y) => List.generate(224, (x) {
          var pixel = resizedImage.getPixel(x, y);
          return [pixel.r / 255.0, pixel.g / 255.0, pixel.b / 255.0];
        }),
      );

      var inputData = [input];
      var output = List.filled(1 * 2, 0.0).reshape([1, 2]);

      _interpreter!.run(inputData, output);

      List<double> probabilities = output[0].cast<double>();
      int maxIndex = 0;
      double maxValue = probabilities[0];

      for (int i = 1; i < probabilities.length; i++) {
        if (probabilities[i] > maxValue) {
          maxValue = probabilities[i];
          maxIndex = i;
        }
      }

      List<String> classNames = ['정상', '결함'];
      final isDefect = maxIndex == 1;

      setState(() {
        _status = isDefect ? InspectionStatus.defect : InspectionStatus.normal;
        _message = classNames[maxIndex];
        _confidence = maxValue * 100;
      });
    } catch (e) {
      setState(() {
        _status = InspectionStatus.error;
        _message = 'AI 분석 실패: $e';
      });
    }
  }

  Color get _statusColor {
    switch (_status) {
      case InspectionStatus.normal:
        return const Color(0xFF00E676);
      case InspectionStatus.defect:
        return const Color(0xFFFF5252);
      case InspectionStatus.error:
        return const Color(0xFFFFB300);
      case InspectionStatus.loading:
        return const Color(0xFF29B6F6);
      case InspectionStatus.idle:
        return Colors.grey.shade600;
    }
  }

  IconData get _statusIcon {
    switch (_status) {
      case InspectionStatus.normal:
        return Icons.check_circle_rounded;
      case InspectionStatus.defect:
        return Icons.error_rounded;
      case InspectionStatus.error:
        return Icons.warning_rounded;
      case InspectionStatus.loading:
        return Icons.hourglass_top_rounded;
      case InspectionStatus.idle:
        return Icons.memory_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.developer_board, color: Color(0xFF00E676)),
            SizedBox(width: 8),
            Text(
              'PCB 불량 검사 AI',
              style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const SizedBox(height: 8),
              // 이미지 프리뷰 영역
              Container(
                height: 260,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFF161B22),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _status == InspectionStatus.idle
                        ? Colors.grey.shade800
                        : _statusColor.withOpacity(0.6),
                    width: 1.5,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: _imageFile != null
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.file(_imageFile!, fit: BoxFit.cover),
                          if (_status == InspectionStatus.loading)
                            Container(
                              color: Colors.black.withOpacity(0.5),
                              child: const Center(
                                child: CircularProgressIndicator(
                                  color: Color(0xFF29B6F6),
                                ),
                              ),
                            ),
                        ],
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.developer_board_outlined,
                            size: 64,
                            color: Colors.grey.shade700,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '검사할 PCB 이미지가 없습니다',
                            style: TextStyle(color: Colors.grey.shade500),
                          ),
                        ],
                      ),
              ),

              const SizedBox(height: 20),

              // 결과 카드
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF161B22),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _statusColor.withOpacity(0.5)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _statusColor.withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(_statusIcon, color: _statusColor, size: 28),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _statusLabel(),
                            style: TextStyle(
                              color: Colors.grey.shade400,
                              fontSize: 12,
                              letterSpacing: 1,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _message,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          if (_confidence != null) ...[
                            const SizedBox(height: 10),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: LinearProgressIndicator(
                                value: _confidence! / 100,
                                minHeight: 6,
                                backgroundColor: Colors.grey.shade800,
                                color: _statusColor,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '신뢰도 ${_confidence!.toStringAsFixed(1)}%',
                              style: TextStyle(
                                color: Colors.grey.shade400,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // 업로드 버튼
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: _status == InspectionStatus.loading
                      ? null
                      : _selectImage,
                  icon: const Icon(Icons.upload_file_rounded),
                  label: Text(
                    _imageFile == null ? '이미지 업로드' : '다른 이미지 검사',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00E676),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _statusLabel() {
    switch (_status) {
      case InspectionStatus.normal:
      case InspectionStatus.defect:
        return '검사 결과';
      case InspectionStatus.error:
        return '오류';
      case InspectionStatus.loading:
        return '처리 중';
      case InspectionStatus.idle:
        return '대기 중';
    }
  }
}
