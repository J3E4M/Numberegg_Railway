# Real Egg Detection - < 1.5GB
FROM python:3.9-slim

WORKDIR /app

# Install system dependencies for OpenCV + tools for model download
RUN apt-get update && apt-get install -y --no-install-recommends \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    libgomp1 \
    wget \
    curl \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Install YOLO backend requirements
COPY backend/requirements.txt requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

# Copy Railway app
COPY railway_app_real.py .

# Download YOLO weights
RUN wget -O yolov8n.pt https://github.com/ultralytics/assets/releases/download/v0.0.0/yolov8n.pt

# Create uploads
RUN mkdir -p /app/uploads

# Remove cache to reduce size
RUN find /usr/local/lib/python3.9 -name "*.pyc" -delete
RUN find /usr/local/lib/python3.9 -name "__pycache__" -type d -exec rm -rf {} +
RUN rm -rf /root/.cache/pip

EXPOSE 8000
CMD ["python", "railway_app_real.py"]
