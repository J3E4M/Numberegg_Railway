from fastapi import FastAPI, UploadFile, File
from ultralytics import YOLO
import cv2
import numpy as np

from fastapi.middleware.cors import CORSMiddleware

app = FastAPI()

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

model = YOLO("yolov8n.pt")  # หรือ model ไข่ของคุณ

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
