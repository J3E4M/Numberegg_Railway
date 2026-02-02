# MINIMAL YOLO Detection - < 4GB
FROM python:3.9-slim

WORKDIR /app

# Install minimal system dependencies only
RUN apt-get update && apt-get install -y --no-install-recommends \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    libgomp1 \
    libgl1-mesa-glx \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Copy requirements first for better caching
COPY railway_requirements_fixed.txt requirements.txt

# Install Python packages with no cache
RUN pip install --no-cache-dir --find-links https://download.pytorch.org/whl/torch_stable.html \
    -r requirements.txt

# Copy app
COPY railway_app.py .

# Create uploads
RUN mkdir -p /app/uploads

# Remove unnecessary files to reduce size
RUN find /usr/local/lib/python3.9 -name "*.pyc" -delete
RUN find /usr/local/lib/python3.9 -name "__pycache__" -type d -exec rm -rf {} +

EXPOSE 8000
CMD ["python", "railway_app.py"]
