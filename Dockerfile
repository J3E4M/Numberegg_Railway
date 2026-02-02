# ONNX YOLO - < 400MB (Optimized)
FROM python:3.11-slim

WORKDIR /app

# ✅ Minimal dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    wget \
    && rm -rf /var/lib/apt/lists/*

# ✅ Install Python packages (opencv-headless)
RUN pip install --no-cache-dir \
    fastapi==0.104.1 \
    uvicorn==0.24.0 \
    onnxruntime==1.16.3 \
    numpy==1.24.4 \
    pillow==10.0.0 \
    opencv-python-headless==4.8.1.78 \
    ultralytics==8.0.196

# Copy app
COPY railway_app_real.py .

# ✅ Download and convert (with proper environment)
RUN wget -O yolov8n.pt https://github.com/ultralytics/assets/releases/download/v0.0.0/yolov8n.pt

# ✅ Convert with environment variables
ENV DISPLAY=
ENV QT_QPA_PLATFORM=offscreen

RUN python -c "from ultralytics import YOLO; YOLO('yolov8n.pt').export(format='onnx', imgsz=640)" && \
    rm yolov8n.pt

# Create uploads
RUN mkdir -p /app/uploads

# Clean up
RUN rm -rf /root/.cache/pip

EXPOSE 8000
CMD ["python", "railway_app_real.py"]