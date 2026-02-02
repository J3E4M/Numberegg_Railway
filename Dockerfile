# Ultra-minimal YOLO - < 300MB
FROM python:3.11-alpine

WORKDIR /app

# Install OpenCV system deps only
RUN apk add --no-cache \
    libglib \
    libsm \
    libxext \
    libxrender \
    libgcc \
    wget \
    && rm -rf /var/cache/apk/*

# Install Python packages (no OpenCV, use ultralytics built-in)
RUN pip install --no-cache-dir \
    fastapi==0.104.1 \
    uvicorn==0.24.0 \
    ultralytics==8.0.196 \
    numpy==1.24.4

# Copy app
COPY railway_app_real.py .

# Download YOLO weights
RUN wget -O yolov8n.pt https://github.com/ultralytics/assets/releases/download/v0.0.0/yolov8n.pt

# Create uploads
RUN mkdir -p /app/uploads

# Remove all cache
RUN rm -rf /root/.cache/pip /root/.cache

EXPOSE 8000
CMD ["python", "railway_app_real.py"]
