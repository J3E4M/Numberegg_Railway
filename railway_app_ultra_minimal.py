# Railway Ultra-Minimal Egg Detection API
# Uses OpenCV for detection - smallest possible image size
# Target: < 2GB Docker image

from fastapi import FastAPI, File, UploadFile, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
import uvicorn
import os
import tempfile
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
from egg_detector_real import RealEggDetector

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    init_supabase()
    init_detector()
    yield
    # Shutdown (if needed)

app = FastAPI(title="NumberEgg Ultra-Minimal API", version="1.0.0", lifespan=lifespan)

# Load environment variables
load_dotenv()

# Supabase configuration
SUPABASE_URL = os.getenv("SUPABASE_URL", "")
SUPABASE_KEY = os.getenv("SUPABASE_ANON_KEY", "")

# Initialize Supabase client
supabase: Optional[Client] = None

# Initialize egg detector
detector = None

# Create uploads directory
UPLOAD_DIR = Path("uploads")
UPLOAD_DIR.mkdir(exist_ok=True)

def init_supabase():
    """Initialize Supabase client"""
    global supabase
    try:
        supabase = create_client(SUPABASE_URL, SUPABASE_KEY)
        print("✅ Supabase connected successfully")
    except Exception as e:
        print(f"❌ Supabase connection failed: {e}")

def init_detector():
    """Initialize egg detector"""
    global detector
    try:
        detector = RealEggDetector()
        print("✅ Egg detector initialized successfully")
    except Exception as e:
        print(f"❌ Egg detector initialization failed: {e}")

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
    return {"message": "NumberEgg Ultra-Minimal API is running", "version": "1.0.0", "model": "OpenCV Edge Detection"}

@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {"status": "healthy", "timestamp": datetime.now().isoformat(), "model": "OpenCV Edge Detection"}

@app.post("/detect")
async def detect_eggs(file: UploadFile = File(...)):
    """OpenCV-based egg detection endpoint"""
    try:
        if detector is None:
            raise HTTPException(status_code=500, detail="Egg detector not initialized")
        
        # Read uploaded file
        contents = await file.read()
        
        # Convert to PIL Image
        image = Image.open(io.BytesIO(contents))
        
        # Run detection
        detection_result = detector.detect_eggs(image)
        
        # Format response to match expected structure
        results = {
            "session_id": str(uuid.uuid4()),
            "detection_results": {
                "grade0_count": detection_result["grade_counts"]["grade0_count"],
                "grade1_count": detection_result["grade_counts"]["grade1_count"], 
                "grade2_count": detection_result["grade_counts"]["grade2_count"],
                "grade3_count": detection_result["grade_counts"]["grade3_count"],
                "grade4_count": detection_result["grade_counts"]["grade4_count"],
                "grade5_count": detection_result["grade_counts"]["grade5_count"],
                "total_eggs": detection_result["total_eggs"],
                "success_percent": detection_result["success_percent"]
            },
            "detections": detection_result["detections"],
            "saved_path": f"uploads/{uuid.uuid4()}.jpg",
            "model_info": detection_result["model_info"]
        }
        
        # Save to Supabase if available
        if supabase:
            try:
                supabase.table("egg_session").insert({
                    "user_id": 1,
                    "image_path": results["saved_path"],
                    "egg_count": results["detection_results"]["total_eggs"],
                    "success_percent": results["detection_results"]["success_percent"],
                    "grade0_count": results["detection_results"]["grade0_count"],
                    "grade1_count": results["detection_results"]["grade1_count"],
                    "grade2_count": results["detection_results"]["grade2_count"],
                    "grade3_count": results["detection_results"]["grade3_count"],
                    "grade4_count": results["detection_results"]["grade4_count"],
                    "grade5_count": results["detection_results"]["grade5_count"],
                    "day": datetime.now().strftime("%Y-%m-%d")
                }).execute()
                print("✅ Saved to Supabase")
            except Exception as e:
                print(f"❌ Supabase save failed: {e}")
        
        return JSONResponse(content=results)
                
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Detection failed: {str(e)}")

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
