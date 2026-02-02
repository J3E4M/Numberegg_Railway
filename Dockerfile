# Real Egg Detection - < 1.5GB
FROM python:3.9-slim

WORKDIR /app

# Install system dependencies for OpenCV
RUN apt-get update && apt-get install -y --no-install-recommends \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    libgomp1 \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Copy real requirements
COPY railway_requirements_custom.txt requirements.txt

# Install Python packages (real OpenCV version)
RUN pip install --no-cache-dir -r requirements.txt

# Copy real app and detector
COPY railway_app_real.py railway_app.py .
COPY egg_detector_real.py .

# Create uploads
RUN mkdir -p /app/uploads

# Remove cache to reduce size
RUN find /usr/local/lib/python3.9 -name "*.pyc" -delete
RUN find /usr/local/lib/python3.9 -name "__pycache__" -type d -exec rm -rf {} +
RUN rm -rf /root/.cache/pip

EXPOSE 8000
CMD ["python", "railway_app_real.py"]
