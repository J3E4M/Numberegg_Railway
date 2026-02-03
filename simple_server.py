from fastapi import FastAPI, UploadFile, File
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from ultralytics import YOLO
import cv2
import numpy as np
import os
import urllib.request
import uvicorn # ✅ Import uvicorn ตรงนี้เลย

from fastapi.middleware.cors import CORSMiddleware

app = FastAPI()

# Pydantic model for login request
class LoginRequest(BaseModel):
    email: str
    password: str

# เพิ่ม CORS middleware เพื่อรองรับการเรียกจาก mobile app
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # ⭐ สำคัญ: อนุญาตให้เรียกจากทุก origin
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.options("/{path:path}")
async def options_handler(path: str):
    return {}

@app.get("/detect")
async def detect_get():
    return {"status": "ok"}

# Download model at runtime if not exists
MODEL_PATH = "yolov8n.pt"
MODEL_URL = "https://github.com/ultralytics/assets/releases/download/v0.0.0/yolov8n.pt"

def download_model():
    max_retries = 3
    for attempt in range(max_retries):
        try:
            print(f"=== Attempt {attempt + 1}/{max_retries} ===")
            
            # Check current directory and files
            print(f"Current directory: {os.getcwd()}")
            print(f"Files in current directory: {os.listdir('.')}")
            print(f"Model file exists: {os.path.exists(MODEL_PATH)}")
            
            # Download model if not exists
            if not os.path.exists(MODEL_PATH):
                print(f"Downloading YOLO model from {MODEL_URL}...")
                import requests
                response = requests.get(MODEL_URL, stream=True, timeout=30)
                response.raise_for_status()
                
                with open(MODEL_PATH, 'wb') as f:
                    for chunk in response.iter_content(chunk_size=8192):
                        f.write(chunk)
                print(f"Model downloaded. Size: {os.path.getsize(MODEL_PATH)} bytes")
            else:
                print(f"Model already exists. Size: {os.path.getsize(MODEL_PATH)} bytes")
            
            # Try to load model
            print("Loading YOLO model...")
            model = YOLO(MODEL_PATH)
            print("✅ Model loaded successfully!")
            return model
            
        except Exception as e:
            print(f"❌ Attempt {attempt + 1} failed: {type(e).__name__}: {e}")
            import traceback
            traceback.print_exc()
            
            # Clean up corrupted file
            if os.path.exists(MODEL_PATH):
                try:
                    os.remove(MODEL_PATH)
                    print("Removed corrupted model file")
                except:
                    pass
            
            if attempt == max_retries - 1:
                print("❌ All attempts failed. Model not available.")
                return None
            continue
    
    return None

# Load model on startup
print("🚀 Starting server and loading model...")
model = download_model()
if model:
    print("✅ Server ready with YOLO model")
else:
    print("❌ Server started but YOLO model not available")

CLASS_NAMES = {
    0: "egg",
    1: "broken_egg",  # ถ้ามี
}

@app.post("/detect")
async def detect(file: UploadFile = File(...)):
    # Retry model loading if not available
    global model
    if model is None:
        print("Model not available, attempting to reload...")
        model = download_model()
        
    if model is None:
        return {
            "count": 0,
            "detections": [],
            "error": "Model not available - please try again later"
        }
    
    try:
        image_bytes = await file.read()
        print(f"Received image: {len(image_bytes)} bytes")
        
        # Convert bytes to numpy array properly
        nparr = np.frombuffer(image_bytes, np.uint8)
        print(f"Created numpy array: {nparr.shape}, dtype: {nparr.dtype}")
        
        # Decode image
        img = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
        
        if img is None:
            print("❌ Failed to decode image - invalid format")
            return {
                "count": 0,
                "detections": [],
                "error": "Invalid image format - could not decode"
            }
        
        print(f"✅ Image decoded successfully: {img.shape}")
        
        # Run YOLO detection
        results = model(img)[0]
        print(f"✅ YOLO inference completed")

        detections = []
        for box in results.boxes:
            x1, y1, x2, y2 = box.xyxy[0].tolist()
            confidence = float(box.conf[0])
            class_id = int(box.cls[0])
            
            detections.append({
                "x1": x1,
                "y1": y1,
                "x2": x2,
                "y2": y2,
                "width_px": x2 - x1,
                "height_px": y2 - y1,
                "confidence": confidence,
                "class_id": class_id,
                "class_name": CLASS_NAMES.get(class_id, "unknown")
            })
        
        print(f"✅ Found {len(detections)} detections")
        return {
            "count": len(detections),
            "detections": detections
        }
        
    except Exception as e:
        print(f"Detection error: {e}")
        return {
            "count": 0,
            "detections": [],
            "error": f"Detection failed: {str(e)}"
        }

@app.get("/health")
async def health_check():
    return {"status": "healthy"}



# ✅✅✅ ส่วนที่เพิ่มเข้ามาใหม่ (สำคัญที่สุด!) ✅✅✅
if __name__ == "__main__":
    # สั่งรัน Server ที่ 0.0.0.0 เพื่อให้ Docker/Railway เข้าถึงได้
    print("Starting server on 0.0.0.0:8000...")
    uvicorn.run(app, host="0.0.0.0", port=8000)