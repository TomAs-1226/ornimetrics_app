# Bird Detection Model

## Setup Instructions

### 1. Export your YOLO model to TFLite format

If you're using the same YOLO model as the Raspberry Pi:

```bash
# Install ultralytics if needed
pip install ultralytics

# Export to TFLite
yolo export model=best.pt format=tflite
```

This creates `best_saved_model/best_float32.tflite`

### 2. Place the model file

Copy the `.tflite` file to this directory and rename it:
```
assets/models/bird_classifier.tflite
```

### 3. Update labels.txt

Edit `labels.txt` to match your model's class names (one per line, in order).

### 4. Rebuild the app

```bash
flutter clean
flutter pub get
flutter build ios  # or android
```

## If No Model Available

The app automatically falls back to ChatGPT Vision API for bird identification if:
- No model file is present
- Model fails to load
- Local inference fails

This requires the `OPENAI_API_KEY` in your `.env` file.

## Model Input Requirements

- Input size: 224x224 RGB (configurable in code)
- Normalized: 0-1 range
- Format: TensorFlow Lite (.tflite)
