# ULTRA MINIMAL YOLO Detection - < 3GB
FROM python:3.9-slim

WORKDIR /app

# Install minimal system dependencies only
RUN apt-get update && apt-get install -y --no-install-recommends \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    libgomp1 \
    libglvnd0 \
    libglx-mesa0 \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Copy requirements first for better caching
COPY railway_requirements_fixed.txt requirements.txt

# Install PyTorch CPU-only first (smaller)
RUN pip install --no-cache-dir \
    torch==1.13.1+cpu \
    torchvision==0.14.1+cpu \
    --index-url https://download.pytorch.org/whl/cpu

# Install other packages
RUN pip install --no-cache-dir -r requirements.txt

# Copy app
COPY railway_app.py .

# Create uploads
RUN mkdir -p /app/uploads

# Remove unnecessary files to reduce size
RUN find /usr/local/lib/python3.9 -name "*.pyc" -delete
RUN find /usr/local/lib/python3.9 -name "__pycache__" -type d -exec rm -rf {} +
RUN rm -rf /root/.cache/pip

EXPOSE 8000
CMD ["python", "railway_app.py"]
