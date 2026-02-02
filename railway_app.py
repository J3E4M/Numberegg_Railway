# Railway YOLO Egg Detection API
# FastAPI server for egg detection using YOLOv8
# Integrates with Supabase for authentication and data storage

from fastapi import FastAPI, File, UploadFile, HTTPException, Depends
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, FileResponse
import uvicorn
import os
import tempfile
from PIL import Image
import numpy as np
import torch
from ultralytics import YOLO
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

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    load_model()
    init_supabase()
    yield
    # Shutdown (if needed)

app = FastAPI(title="NumberEgg YOLO API", version="1.0.0", lifespan=lifespan)

# Load environment variables
load_dotenv()

# Supabase configuration
SUPABASE_URL = os.getenv("SUPABASE_URL", "")
SUPABASE_KEY = os.getenv("SUPABASE_ANON_KEY", "")

# Initialize Supabase client
supabase: Optional[Client] = None

# Create uploads directory
UPLOAD_DIR = Path("uploads")
UPLOAD_DIR.mkdir(exist_ok=True)

def init_supabase():
    global supabase
    if SUPABASE_URL and SUPABASE_KEY:
        supabase = create_client(SUPABASE_URL, SUPABASE_KEY)
        print("✅ Supabase client initialized")
    else:
        print("⚠️ Supabase credentials not found in environment variables")

def save_uploaded_file(upload_file: UploadFile) -> str:
    """Save uploaded file to uploads directory and return the file path"""
    file_extension = os.path.splitext(upload_file.filename)[1]
    unique_filename = f"{uuid.uuid4()}{file_extension}"
    file_path = UPLOAD_DIR / unique_filename
    
    with open(file_path, "wb") as buffer:
        shutil.copyfileobj(upload_file.file, buffer)
    
    return str(file_path)

# Configure CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # In production, specify your Flutter app domain
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Load YOLO model
model = None

def load_model():
    global model
    try:
        model = YOLO('yolov8n.pt')  # You can replace with your custom trained model
        # For egg detection, you might want to use a custom trained model
        # model = YOLO('egg_detection_model.pt')
        print("✅ YOLO model loaded successfully")
    except Exception as e:
        print(f"❌ Failed to load YOLO model: {e}")
        raise

@app.get("/")
async def root():
    return {
        "message": "NumberEgg YOLO Detection API",
        "version": "1.0.0",
        "status": "running",
        "endpoints": {
            "detect": "/detect - POST: Upload image for egg detection",
            "health": "/health - GET: Check API health"
        }
    }

@app.get("/health")
async def health_check():
    return {
        "status": "healthy",
        "model_loaded": model is not None,
        "timestamp": datetime.now().isoformat()
    }

@app.post("/detect")
async def detect_eggs(
    file: UploadFile = File(...),
    user_id: Optional[int] = Form(None)  # รับ user_id จาก frontend
):
    """
    Detect eggs in uploaded image using YOLO
    Returns egg count, sizes, and confidence scores
    Only processes detection, doesn't save image
    """
    if not model:
        raise HTTPException(status_code=500, detail="Model not loaded")
    
    if not file.content_type.startswith('image/'):
        raise HTTPException(status_code=400, detail="File must be an image")
    
    try:
        # Read image directly without saving
        contents = await file.read()
        image = Image.open(io.BytesIO(contents))
        
        # Convert to RGB if needed
        if image.mode != 'RGB':
            image = image.convert('RGB')
        
        # Run YOLO detection
        results = model(image)
        
        # Process detection results
        detections = []
        egg_count = 0
        grade0_count = 0
        grade1_count = 0
        grade2_count = 0
        grade3_count = 0
        grade4_count = 0
        grade5_count = 0
        
        for result in results:
            boxes = result.boxes
            if boxes is not None:
                for box in boxes:
                    # Get box coordinates and confidence
                    x1, y1, x2, y2 = box.xyxy[0].cpu().numpy()
                    confidence = float(box.conf[0].cpu().numpy())
                    class_id = int(box.cls[0].cpu().numpy())
                    
                    # Calculate egg size based on bounding box area
                    width = x2 - x1
                    height = y2 - y1
                    area = width * height
                    
                    # Classify egg size into 6 grades (NEW SYSTEM - grade0-5)
                    # TODO: calibrate with real-world scale
                    if area >= 22000:
                        egg_grade = "grade0"  # เบอร์ 0 (พิเศษ)
                        grade0_count += 1
                    elif area >= 20000:
                        egg_grade = "grade1"  # เบอร์ 1 (ใหญ่)
                        grade1_count += 1
                    elif area >= 18000:
                        egg_grade = "grade2"  # เบอร์ 2 (กลาง)
                        grade2_count += 1
                    elif area >= 16000:
                        egg_grade = "grade3"  # เบอร์ 3 (เล็ก)
                        grade3_count += 1
                    elif area >= 14000:
                        egg_grade = "grade4"  # เบอร์ 4 (เล็กมาก)
                        grade4_count += 1
                    else:
                        egg_grade = "grade5"  # เบอร์ 5 (พิเศษเล็ก)
                        grade5_count += 1
                    
                    egg_count += 1
                    
                    detection = {
                        "id": len(detections) + 1,
                        "grade": egg_grade,  # NEW: grade0-5 strings
                        "confidence": round(confidence, 3),
                        "bbox": {
                            "x1": round(float(x1), 2),
                            "y1": round(float(y1), 2),
                            "x2": round(float(x2), 2),
                            "y2": round(float(y2), 2),
                            "width": round(float(width), 2),
                            "height": round(float(height), 2),
                            "area": round(float(area), 2)
                        }
                    }
                    detections.append(detection)
        
        # Calculate success percentage
        success_percent = min(100.0, round((len(detections) / max(1, egg_count)) * 100, 2))
        
        # Save results to Supabase if configured and user_id is provided
        session_id = None
        if supabase and user_id is not None:
            try:
                # Create egg session record
                session_data = {
                    "user_id": user_id,  # ใช้ user_id จาก frontend
                    "image_path": f"uploads/{uuid.uuid4()}.jpg",  # Supabase Storage path
                    "egg_count": egg_count,
                    "success_percent": success_percent,
                    "grade0_count": grade0_count,
                    "grade1_count": grade1_count,
                    "grade2_count": grade2_count,
                    "grade3_count": grade3_count,
                    "grade4_count": grade4_count,
                    "grade5_count": grade5_count,
                    "day": datetime.now().strftime("%Y-%m-%d"),
                    "created_at": datetime.now().isoformat()
                }
                
                session_result = supabase.table("egg_session").insert(session_data).execute()
                
                if session_result.data:
                    session_id = session_result.data[0]['id']
                    
                    # Create egg item records
                    for detection in detections:
                        item_data = {
                            "session_id": session_id,
                            "grade": int(detection["grade"].replace("grade", "")) if "grade" in detection["grade"] else 5,
                            "confidence": detection["confidence"]
                        }
                        supabase.table("egg_item").insert(item_data).execute()
                    
                    print(f"✅ Detection results saved to Supabase with session ID: {session_id} for user {user_id}")
                
            except Exception as e:
                print(f"❌ Failed to save to Supabase: {e}")
                session_id = None  # ถ้า save ล้มเหลว
        
        # Convert image to base64 for response
        buffered = io.BytesIO()
        image.save(buffered, format="JPEG")
        img_base64 = base64.b64encode(buffered.getvalue()).decode()
        
        response = {
            "success": True,
            "timestamp": datetime.now().isoformat(),
            "session_id": session_id,  # ใช้ session_id จาก Supabase
            "image_info": {
                "filename": file.filename,
                "saved_path": f"uploads/{uuid.uuid4()}.jpg" if session_id else None,  # Supabase Storage path
                "size": len(contents),
                "format": image.format,
                "dimensions": f"{image.width}x{image.height}"
            },
            "detection_results": {
                "egg_count": egg_count,
                "grade0_count": grade0_count,
                "grade1_count": grade1_count,
                "grade2_count": grade2_count,
                "grade3_count": grade3_count,
                "grade4_count": grade4_count,
                "grade5_count": grade5_count,
                "success_percent": success_percent,
                "detections": detections
            },
            "processed_image": f"data:image/jpeg;base64,{img_base64}"
        }
        
        return response
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Detection failed: {str(e)}")

@app.get("/uploads/{filename}")
async def get_uploaded_file(filename: str):
    """Serve uploaded files"""
    file_path = UPLOAD_DIR / filename
    if not file_path.exists():
        raise HTTPException(status_code=404, detail="File not found")
    
    return FileResponse(file_path)

@app.post("/train")
async def train_model():
    """
    Endpoint for training custom egg detection model
    This would require training data to be uploaded
    """
    return {
        "message": "Training endpoint - requires implementation with training data",
        "status": "not_implemented"
    }

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8000))
    uvicorn.run(app, host="0.0.0.0", port=port)
