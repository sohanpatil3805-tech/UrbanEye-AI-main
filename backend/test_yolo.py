import sys
from pathlib import Path
from app.services.yolo_service import detect_image

def main():
    if len(sys.argv) > 1:
        img_path = Path(sys.argv[1])
    else:
        # Default to one of the uploads
        img_path = Path('uploads/20260912_123824_881004.jpg')
    
    if not img_path.exists():
        print(f"Error: {img_path} not found")
        sys.exit(1)
        
    print(f"Running detection on {img_path}...")
    try:
        detections = detect_image(img_path)
        print("Detections:")
        for d in detections:
            print(f" - {d}")
        if not detections:
            print("No detections found.")
    except Exception as e:
        print(f"Detection failed: {e}")

if __name__ == '__main__':
    main()
