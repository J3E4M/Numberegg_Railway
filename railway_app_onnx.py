# Railway ONNX Egg Detection API
# Uses ONNX runtime for minimal image size

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
import cv2
import numpy as np
import onnxruntime as ort

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    init_supabase()
    init_onnx()
    yield
    # Shutdown (if needed)

app = FastAPI(title="NumberEgg ONNX API", version="1.0.0", lifespan=lifespan)

# Load environment variables
load_dotenv()

# Supabase configuration
SUPABASE_URL = os.getenv("SUPABASE_URL", "")
SUPABASE_KEY = os.getenv("SUPABASE_ANON_KEY", "")

# Initialize Supabase client
supabase: Optional[Client] = None

# Initialize ONNX session
onnx_session = None
input_name = None

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

def init_onnx():
    """Initialize ONNX model"""
    global onnx_session, input_name
    try:
        # Try to load ONNX model
        if os.path.exists("yolov8n.onnx"):
            onnx_session = ort.InferenceSession("yolov8n.onnx")
            input_name = onnx_session.get_inputs()[0].name
            print("✅ Loaded ONNX model successfully")
        else:
            print("❌ ONNX model not found. Please ensure model conversion completed.")
    except Exception as e:
        print(f"❌ Failed to initialize ONNX model: {e}")

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
    return {"message": "NumberEgg ONNX API is running", "version": "1.0.0", "model": "YOLOv8n ONNX"}

@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {"status": "healthy", "timestamp": datetime.now().isoformat(), "model": "YOLOv8n ONNX"}

def classify_egg_by_size(bbox, image_shape):
    """Classify egg grade based on bounding box size"""
    x1, y1, x2, y2 = bbox
    width = x2 - x1
    height = y2 - y1
    area = width * height
    
    # Thai Industrial Standard TIS 227-2524 egg grading based on pixel area
    if area >= 15000:
        grade = "grade0"  # เบอร์ 0 (พิเศษ) - ใหญ่พิเศษ > 70g
    elif area >= 10000:
        grade = "grade1"  # เบอร์ 1 (ใหญ่) - 60-70g
    elif area >= 6000:
        grade = "grade2"  # เบอร์ 2 (กลาง) - 50-60g
    elif area >= 3000:
        grade = "grade3"  # เบอร์ 3 (เล็ก) - 40-50g
    elif area >= 1500:
        grade = "grade4"  # เบอร์ 4 (เล็กมาก) - 30-40g
    else:
        grade = "grade5"  # เบอร์ 5 (พิเศษเล็ก) - < 30g
    
    return grade

def preprocess_image(image):
    """Preprocess image for ONNX inference"""
    # Resize to 640x640
    img_resized = cv2.resize(image, (640, 640))
    # Convert to RGB and normalize
    img_rgb = cv2.cvtColor(img_resized, cv2.COLOR_BGR2RGB)
    img_normalized = img_rgb.astype(np.float32) / 255.0
    # Transpose dimensions: HWC -> CHW
    img_transposed = np.transpose(img_normalized, (2, 0, 1))
    # Add batch dimension
    img_batch = np.expand_dims(img_transposed, axis=0)
    return img_batch

def postprocess_outputs(outputs, original_shape, input_shape=(640, 640)):
    """Postprocess ONNX outputs to get detections"""
    detections = []
    
    # YOLOv8 output shape: [1, 84, 8400] (batch, classes+4, num_detections)
    output = outputs[0]
    
    # Transpose to get [8400, 84]
    output = output.transpose()
    
    # Extract boxes, scores, and classes
    boxes = output[:, :4]  # x1, y1, x2, y2
    scores = output[:, 4]  # confidence
    class_probs = output[:, 5:]  # class probabilities
    
    # Calculate final scores
    final_scores = scores * np.max(class_probs, axis=1)
    class_ids = np.argmax(class_probs, axis=1)
    
    # Scale boxes back to original image size
    orig_h, orig_w = original_shape[:2]
    input_h, input_w = input_shape
    
    scale_x = orig_w / input_w
    scale_y = orig_h / input_h
    
    for i in range(len(boxes)):
        if final_scores[i] > 0.3:  # Confidence threshold
            x1, y1, x2, y2 = boxes[i]
            
            # Scale to original size
            x1 = int(x1 * scale_x)
            y1 = int(y1 * scale_y)
            x2 = int(x2 * scale_x)
            y2 = int(y2 * scale_y)
            
            detections.append({
                'bbox': [x1, y1, x2, y2],
                'confidence': float(final_scores[i]),
                'class_id': int(class_ids[i])
            })
    
    return detections

@app.post("/detect")
async def detect_eggs(file: UploadFile = File(...)):
    """ONNX-based egg detection endpoint"""
    try:
        if onnx_session is None:
            raise HTTPException(status_code=500, detail="ONNX model not initialized")
        
        # Read uploaded file
        contents = await file.read()
        
        # Convert to OpenCV format
        np_img = np.frombuffer(contents, np.uint8)
        img = cv2.imdecode(np_img, cv2.IMREAD_COLOR)
        original_shape = img.shape
        
        # Preprocess image
        input_tensor = preprocess_image(img)
        
        # Run ONNX inference
        outputs = onnx_session.run(None, {input_name: input_tensor})
        
        # Postprocess outputs
        detections = postprocess_outputs(outputs, original_shape)
        
        # Process detections for egg grading
        grade_counts = {
            "grade0_count": 0,
            "grade1_count": 0,
            "grade2_count": 0,
            "grade3_count": 0,
            "grade4_count": 0,
            "grade5_count": 0
        }
        
        processed_detections = []
        for i, detection in enumerate(detections):
            # Classify egg grade by size
            grade = classify_egg_by_size(detection['bbox'], original_shape)
            
            # Update grade counts
            grade_counts[f"{grade}_count"] += 1
            
            # Create detection object
            detection_obj = {
                "id": i + 1,
                "grade": grade,
                "confidence": round(detection['confidence'], 2),
                "bbox": [
                    int(detection['bbox'][0]),
                    int(detection['bbox'][1]),
                    int(detection['bbox'][2] - detection['bbox'][0]),
                    int(detection['bbox'][3] - detection['bbox'][1])
                ]
            }
            processed_detections.append(detection_obj)
        
        # Calculate statistics
        total_eggs = len(processed_detections)
        success_percent = 100.0 if total_eggs > 0 else 0.0
        
        # Format response
        results = {
            "session_id": str(uuid.uuid4()),
            "detection_results": {
                "grade0_count": grade_counts["grade0_count"],
                "grade1_count": grade_counts["grade1_count"], 
                "grade2_count": grade_counts["grade2_count"],
                "grade3_count": grade_counts["grade3_count"],
                "grade4_count": grade_counts["grade4_count"],
                "grade5_count": grade_counts["grade5_count"],
                "total_eggs": total_eggs,
                "success_percent": success_percent
            },
            "detections": processed_detections,
            "saved_path": f"uploads/{uuid.uuid4()}.jpg",
            "model_info": {
                "type": "YOLOv8n ONNX",
                "method": "ONNX Runtime Inference",
                "features": ["Object Detection", "Size Classification", "Optimized Inference"]
            }
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
