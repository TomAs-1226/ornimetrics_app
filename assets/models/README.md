# Bird Detection Model

## Setup Instructions

### 1. Export your YOLO model to ONNX format

If you're using the same YOLO model as the Raspberry Pi:

```bash
# Install ultralytics if needed
pip install ultralytics

# Export to ONNX
yolo export model=best.pt format=onnx
```

This creates `best.onnx` with embedded class labels.

### 2. Place the model file

Copy the `.onnx` file to this directory and rename it:
```
assets/models/bird_classifier.onnx
```

### 3. Rebuild the app

```bash
flutter clean
flutter pub get
flutter build ios  # or android
```

## Detection Behavior

The app automatically chooses the best detection method:

**Online Mode:**
- Uses cloud-based AI for highest accuracy
- Requires internet connection
- Best for detailed species identification

**Offline Mode:**
- Uses local ONNX model on device
- No internet required
- Fast, private identification
- Works with embedded class labels in model

## Model Requirements

- Format: ONNX (.onnx)
- Input size: 640x640 RGB (YOLO default) or 224x224 (classification)
- Normalized: 0-1 range
- Labels: Embedded in ONNX metadata (no separate labels.txt needed)

## Supported Models

- YOLOv8 classification/detection models
- Custom bird classification models
- Any ONNX-compatible model with proper input/output specs
