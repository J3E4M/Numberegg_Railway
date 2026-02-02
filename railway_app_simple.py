# Railway Simple Egg Detection API
# FastAPI server without AI dependencies
# Mock detection for testing

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

app = FastAPI(title="NumberEgg Simple API", version="1.0.0")

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
    """Initialize Supabase client"""
    global supabase
    try:
        supabase = create_client(SUPABASE_URL, SUPABASE_KEY)
        print("✅ Supabase connected successfully")
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

@app.on_event("startup")
async def startup_event():
    """Initialize services on startup"""
    init_supabase()

@app.get("/")
async def root():
    """Root endpoint"""
    return {"message": "NumberEgg Simple API is running", "version": "1.0.0"}

@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {"status": "healthy", "timestamp": datetime.now().isoformat()}

@app.post("/detect")
async def detect_eggs(file: UploadFile = File(...)):
    """Mock egg detection endpoint"""
    try:
        # Read uploaded file
        contents = await file.read()
        
        # Save temporarily
        with tempfile.NamedTemporaryFile(delete=False, suffix=".jpg") as tmp_file:
            tmp_file.write(contents)
            tmp_file_path = tmp_file.name
        
        try:
            # Mock detection results (grade0-5 system)
            mock_results = {
                "session_id": str(uuid.uuid4()),
                "detection_results": {
                    "grade0_count": 1,  # เบอร์ 0 (พิเศษ)
                    "grade1_count": 2,  # เบอร์ 1 (ใหญ่)
                    "grade2_count": 3,  # เบอร์ 2 (กลาง)
                    "grade3_count": 2,  # เบอร์ 3 (เล็ก)
                    "grade4_count": 1,  # เบอร์ 4 (เล็กมาก)
                    "grade5_count": 0,  # เบอร์ 5 (พิเศษเล็ก)
                    "total_eggs": 9,
                    "success_percent": 100.0
                },
                "detections": [
                    {"id": 1, "grade": "grade2", "confidence": 0.95},
                    {"id": 2, "grade": "grade1", "confidence": 0.92},
                    {"id": 3, "grade": "grade3", "confidence": 0.88}
                ],
                "saved_path": f"uploads/{uuid.uuid4()}.jpg"
            }
            
            # Save to Supabase if available
            if supabase:
                try:
                    supabase.table("egg_detections").insert({
                        "session_id": mock_results["session_id"],
                        "grade0_count": mock_results["detection_results"]["grade0_count"],
                        "grade1_count": mock_results["detection_results"]["grade1_count"],
                        "grade2_count": mock_results["detection_results"]["grade2_count"],
                        "grade3_count": mock_results["detection_results"]["grade3_count"],
                        "grade4_count": mock_results["detection_results"]["grade4_count"],
                        "grade5_count": mock_results["detection_results"]["grade5_count"],
                        "total_eggs": mock_results["detection_results"]["total_eggs"],
                        "success_percent": mock_results["detection_results"]["success_percent"],
                        "created_at": datetime.now().isoformat()
                    }).execute()
                    print("✅ Saved to Supabase")
                except Exception as e:
                    print(f"❌ Supabase save failed: {e}")
            
            return JSONResponse(content=mock_results)
            
        finally:
            # Clean up temp file
            if os.path.exists(tmp_file_path):
                os.unlink(tmp_file_path)
                
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Detection failed: {str(e)}")

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
