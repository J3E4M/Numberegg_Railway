from fastapi import FastAPI, UploadFile, File
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from ultralytics import YOLO
import cv2
import numpy as np
import os
import urllib.request

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
    if not os.path.exists(MODEL_PATH):
        print(f"Downloading YOLOv8 model from {MODEL_URL}...")
        urllib.request.urlretrieve(MODEL_URL, MODEL_PATH)
        print("Model downloaded successfully!")

# Download model on startup
download_model()
model = YOLO(MODEL_PATH)

CLASS_NAMES = {
    0: "egg",
    1: "broken_egg",  # ถ้ามี
}

@app.post("/detect")
async def detect(file: UploadFile = File(...)):
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
        "detections": detections  # เปลี่ยนจาก "eggs" เป็น "detections" เพื่อให้ตรงกับ Flutter app
    }

@app.get("/health")
async def health_check():
    return {"status": "healthy"}

@app.post("/login")
async def login(request: LoginRequest):
    # Simple mock login - accept test02@gmail.com with any password
    if request.email == "test02@gmail.com":
        return {
            "id": 1,
            "email": request.email,
            "name": "Test User",
            "privilege": "User",
            "message": "Login successful"
        }
    else:
        return JSONResponse(
            status_code=401,
            content={"error": "Invalid credentials"}
        )
