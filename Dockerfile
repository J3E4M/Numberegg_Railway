# ONNX YOLO - < 400MB
FROM python:3.11-slim

WORKDIR /app

# Install minimal system deps
RUN apt-get update && apt-get install -y --no-install-recommends \
    wget \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Install Python packages (ONNX only)
RUN pip install --no-cache-dir \
    fastapi==0.104.1 \
    uvicorn==0.24.0 \
    onnxruntime==1.16.3 \
    numpy==1.24.4 \
    pillow==10.0.0

# Copy app
COPY railway_app_real.py .

# Download YOLO ONNX model (smaller than .pt)
RUN wget -O yolov8n.onnx https://github.com/ultralytics/assets/releases/download/v0.0.0/yolov8n.onnx

# Create uploads
RUN mkdir -p /app/uploads

# Remove cache
RUN rm -rf /root/.cache/pip

EXPOSE 8000
CMD ["python", "railway_app_real.py"]
