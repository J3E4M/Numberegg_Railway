# Railway Real Egg Detection API
# ใช้ real model ที่วัดขอบวัตถุจริงๆ ไม่ใช่ mock data

from fastapi import FastAPI, File, UploadFile, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
import uvicorn
import os
import tempfile
import sqlite3
from PIL import Image
import base64
import io
from datetime import datetime
import json
from supabase import create_client, Client
from dotenv import load_dotenv
from typing import Optional
import uuid
import shutil
from pathlib import Path
from contextlib import asynccontextmanager
from ultralytics import YOLO
import numpy as np
import cv2
import re

# Import our real egg detector
# from egg_detector_real import RealEggDetector

def _load_yolo_model() -> YOLO:
    env_model_path = os.getenv("YOLO_MODEL_PATH", "").strip()
    candidates = [
        Path(env_model_path) if env_model_path else None,
        Path("backend") / "yolov8n.pt",
        Path("yolov8n.pt"),
    ]
    for candidate in candidates:
        if candidate and candidate.exists():
            return YOLO(str(candidate))
    raise RuntimeError("YOLO model file not found. Set YOLO_MODEL_PATH or provide yolov8n.pt")

def _safe_float(value) -> float:
    try:
        return float(value)
    except Exception:
        return 0.0

def _normalize_class_name(name: str) -> str:
    return (name or "").strip().lower().replace("-", "_").replace(" ", "")

def _grade_from_class_name(class_name: str) -> Optional[str]:
    n = _normalize_class_name(class_name)
    m = re.search(r"(grade|no\.?)([0-5])", n)
    if m:
        return f"grade{m.group(2)}"
    if n in {"egg_small", "small", "eggs"}:
        return "grade4"
    if n in {"egg_medium", "medium"}:
        return "grade2"
    if n in {"egg_large", "large"}:
        return "grade1"
    return None

def _grade_from_bbox_ratio(bbox_area: float, image_area: float) -> str:
    ratio = (bbox_area / image_area) if image_area > 0 else 0.0
    if ratio >= 0.12:
        return "grade0"
    if ratio >= 0.09:
        return "grade1"
    if ratio >= 0.06:
        return "grade2"
    if ratio >= 0.04:
        return "grade3"
    if ratio >= 0.02:
        return "grade4"
    return "grade5"

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    try:
        global yolo_model
        yolo_model = _load_yolo_model()
        init_sqlite()
        init_supabase()
        print("✅ YOLO model initialized successfully")
        print("✅ SQLite initialized successfully")
        print("✅ Supabase connected successfully")
    except Exception as e:
        print(f"❌ Initialization failed: {e}")
    yield
    # Shutdown (if needed)

app = FastAPI(title="NumberEgg Real API", version="1.0.0", lifespan=lifespan)

# Load environment variables
load_dotenv()

# Supabase configuration
SUPABASE_URL = os.getenv("SUPABASE_URL", "")
SUPABASE_KEY = os.getenv("SUPABASE_ANON_KEY", "")

# Initialize Supabase client
supabase: Optional[Client] = None

# Initialize YOLO model
yolo_model: Optional[YOLO] = None

# Create uploads directory
UPLOAD_DIR = Path("uploads")
UPLOAD_DIR.mkdir(exist_ok=True)

# SQLite configuration (local first)
SQLITE_DB_PATH = Path("backend") / "database.db"

def init_sqlite():
    """Initialize SQLite database and tables"""
    SQLITE_DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(SQLITE_DB_PATH))
    cur = conn.cursor()
    cur.execute(
        """
        CREATE TABLE IF NOT EXISTS egg_session (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL,
            image_path TEXT NOT NULL,
            egg_count INTEGER NOT NULL,
            success_percent REAL NOT NULL,
            grade0_count INTEGER NOT NULL,
            grade1_count INTEGER NOT NULL,
            grade2_count INTEGER NOT NULL,
            grade3_count INTEGER NOT NULL,
            grade4_count INTEGER NOT NULL,
            grade5_count INTEGER NOT NULL,
            day TEXT NOT NULL,
            created_at TEXT NOT NULL
        )
        """
    )
    conn.commit()
    conn.close()

def save_to_sqlite(payload: dict) -> int:
    """Save egg session to SQLite and return session id"""
    conn = sqlite3.connect(str(SQLITE_DB_PATH))
    cur = conn.cursor()
    cur.execute(
        """
        INSERT INTO egg_session (
            user_id, image_path, egg_count, success_percent,
            grade0_count, grade1_count, grade2_count, grade3_count, grade4_count, grade5_count,
            day, created_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            payload["user_id"],
            payload["image_path"],
            payload["egg_count"],
            payload["success_percent"],
            payload["grade0_count"],
            payload["grade1_count"],
            payload["grade2_count"],
            payload["grade3_count"],
            payload["grade4_count"],
            payload["grade5_count"],
            payload["day"],
            payload["created_at"],
        ),
    )
    conn.commit()
    session_id = cur.lastrowid
    conn.close()
    return session_id

def init_supabase():
    """Initialize Supabase client"""
    global supabase
    try:
        supabase = create_client(SUPABASE_URL, SUPABASE_KEY)
    except Exception as e:
        print(f"❌ Supabase connection failed: {e}")

# Configure CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/")
async def root():
    """Root endpoint"""
    return {
        "message": "NumberEgg Real API is running", 
        "version": "1.0.0", 
        "model": "YOLO (ultralytics)"
    }

@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {
        "status": "healthy", 
        "timestamp": datetime.now().isoformat(), 
        "model": "YOLO (ultralytics)",
        "detector_ready": yolo_model is not None
    }

@app.post("/detect")
async def detect_eggs(file: UploadFile = File(...), user_id: int = 1):
    """YOLO egg detection endpoint"""
    try:
        if yolo_model is None:
            raise HTTPException(status_code=503, detail="YOLO model not initialized")
        
        # Read uploaded file
        contents = await file.read()
        
        # Convert to PIL Image
        image = Image.open(io.BytesIO(contents))
        
        # Convert RGB if needed
        if image.mode != 'RGB':
            image = image.convert('RGB')
        
        np_img = np.array(image)
        bgr_img = cv2.cvtColor(np_img, cv2.COLOR_RGB2BGR)

        image_area = float(image.width * image.height)

        result = yolo_model(bgr_img)[0]

        detections_list = []
        confidences = []

        grade_counts = {
            "grade0_count": 0,
            "grade1_count": 0,
            "grade2_count": 0,
            "grade3_count": 0,
            "grade4_count": 0,
            "grade5_count": 0,
        }

        for i, box in enumerate(result.boxes):
            x1, y1, x2, y2 = box.xyxy[0].tolist()
            conf = _safe_float(box.conf[0])
            cls_id = int(box.cls[0]) if hasattr(box, "cls") else -1
            class_name = ""
            try:
                class_name = str(result.names.get(cls_id, ""))
            except Exception:
                class_name = ""

            w = max(0.0, _safe_float(x2) - _safe_float(x1))
            h = max(0.0, _safe_float(y2) - _safe_float(y1))
            bbox_area = w * h

            grade = _grade_from_class_name(class_name) or _grade_from_bbox_ratio(bbox_area, image_area)

            confidences.append(conf)
            grade_key = f"{grade}_count"
            if grade_key in grade_counts:
                grade_counts[grade_key] += 1
            detections_list.append({
                "id": i + 1,
                "grade": grade,
                "confidence": round(conf, 2),
                "bbox": {
                    "x1": _safe_float(x1),
                    "y1": _safe_float(y1),
                    "x2": _safe_float(x2),
                    "y2": _safe_float(y2),
                    "width": w,
                    "height": h,
                    "area": bbox_area,
                },
            })

        total_eggs = len(detections_list)
        avg_conf = (sum(confidences) / len(confidences)) if confidences else 0.0
        success_percent = round(avg_conf * 100.0, 1)

        # Prepare response
        saved_path = f"uploads/{uuid.uuid4()}.jpg"

        detection_results = {
            "session_id": str(uuid.uuid4()),
            "image_info": {
                "saved_path": saved_path,
                "filename": file.filename or "upload",
                "format": "RGB",
            },
            "detection_results": {
                **grade_counts,
                "total_eggs": total_eggs,
                "success_percent": success_percent,
                "detections": detections_list,
            },
            "detections": detections_list,
            "saved_path": saved_path,
            "model_info": {
                "type": "YOLO",
                "framework": "ultralytics",
                "weights": "yolov8n.pt",
            },
        }
        
        payload = {
            "user_id": user_id,
            "image_path": detection_results["saved_path"],
            "egg_count": detection_results["detection_results"]["total_eggs"],
            "success_percent": detection_results["detection_results"]["success_percent"],
            "grade0_count": detection_results["detection_results"]["grade0_count"],
            "grade1_count": detection_results["detection_results"]["grade1_count"],
            "grade2_count": detection_results["detection_results"]["grade2_count"],
            "grade3_count": detection_results["detection_results"]["grade3_count"],
            "grade4_count": detection_results["detection_results"]["grade4_count"],
            "grade5_count": detection_results["detection_results"]["grade5_count"],
            "day": datetime.now().strftime("%Y-%m-%d"),
            "created_at": datetime.now().isoformat()  # Add created_at for SQLite
        }

        sqlite_session_id = save_to_sqlite(payload)
        print(f"✅ Saved to SQLite (egg_session) id: {sqlite_session_id}")

        # Sync to Supabase if available
        if supabase:
            try:
                supabase.table("egg_session").insert(payload).execute()
                print(f"✅ Synced to Supabase (egg_session) for user_id: {user_id}")
            except Exception as e:
                print(f"❌ Supabase sync failed: {e}")
        
        return JSONResponse(content=detection_results)
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Detection failed: {str(e)}")

@app.get("/model-info")
async def model_info():
    """Get model information"""
    return {
        "model": "YOLO (ultralytics)",
        "version": "1.0.0",
        "method": "Ultralytics YOLO inference (YOLO_MODEL_PATH or backend/yolov8n.pt or yolov8n.pt)",
        "grade_mapping": "Prefer class-name mapping (grade0-5 / No.0-5 / egg_small-medium-large) then fallback to bbox_area/image_area heuristic",
        "detector_ready": yolo_model is not None
    }
        
if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
