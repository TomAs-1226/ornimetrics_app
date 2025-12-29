# Bird Detection Model

## Current Implementation

The Ornimetrics app uses cloud-based AI for bird species identification.

### Requirements
- Active internet connection
- Valid API key in `.env` file

### How It Works

1. User takes or selects a photo
2. Image is sent to cloud AI for analysis
3. Species name, scientific name, and confidence are returned
4. Results can be saved to your field detections

### Offline Mode

When offline, the app will display a message asking the user to connect to the internet for species identification. The feeder monitoring and other features continue to work offline with cached data.

### Future Local Model Support

To add offline detection capability in the future:

1. Convert your YOLO model to TensorFlow Lite:
   ```bash
   yolo export model=best.pt format=tflite
   ```

2. Add `tflite_flutter` package to pubspec.yaml

3. Implement TFLite inference in `BirdDetectionService`

4. Place the model at: `assets/models/bird_classifier.tflite`

Note: Flutter's ML ecosystem has limited ONNX support. TFLite is the recommended format for mobile inference.
