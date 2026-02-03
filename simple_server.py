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
# ✅ แก้ไข URL ให้ถูกต้อง (v8.0.0 แทน v0.0.0)
MODEL_URL = "https://github.com/ultralytics/assets/releases/download/v8.0.0/yolov8n.pt"

def download_model():
    if not os.path.exists(MODEL_PATH):
        print(f"Downloading YOLOv8 model from {MODEL_URL}...")
        try:
            urllib.request.urlretrieve(MODEL_URL, MODEL_PATH)
            print("Model downloaded successfully!")
        except Exception as e:
            print(f"Failed to download model: {e}")
            # Create a dummy model for now to avoid crashes
            print("Using dummy model - detection will not work until model is available")
            return None
    return True

# Download model on startup (but don't fail if it doesn't work)
model_ready = download_model()
if model_ready:
    try:
        model = YOLO(MODEL_PATH)
    except Exception as e:
        print(f"Failed to load model: {e}")
        model = None
else:
    model = None

CLASS_NAMES = {
    0: "egg",
    1: "broken_egg",  # ถ้ามี
}

@app.post("/detect")
async def detect(file: UploadFile = File(...)):
    if model is None:
        return {
            "count": 0,
            "detections": [],
            "error": "Model not available - please try again later"
        }
    
    image_bytes = await file.read()
    np_img = np.frombuffer(image_bytes, np.uint8)
    img = cv2.imdecode(np_img, cv2.IMREAD_COLOR)

    results = model(img)[0]

    detections = []
    for box in results.boxes:
        x1, y1, x2, y2 = box.xyxy[0].tolist()

        detections.append({
            "x1": x1,
            "y1": y1,
            "x2": x2,
            "y2": y2,
            "width_px": x2 - x1,
            "height_px": y2 - y1,
            "confidence": float(box.conf[0]),
            "class_id": int(box.cls[0]),
            "class_name": CLASS_NAMES.get(int(box.cls[0]), "unknown")
        })

    return {
        "count": len(detections),
        "detections": detections
    }

@app.get("/health")
async def health_check():
    return {"status": "healthy"}



# ✅✅✅ ส่วนที่เพิ่มเข้ามาใหม่ (สำคัญที่สุด!) ✅✅✅
if __name__ == "__main__":
    # สั่งรัน Server ที่ 0.0.0.0 เพื่อให้ Docker/Railway เข้าถึงได้
    print("Starting server on 0.0.0.0:8000...")
    uvicorn.run(app, host="0.0.0.0", port=8000)