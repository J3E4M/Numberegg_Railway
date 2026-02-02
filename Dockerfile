# Ultra minimal - no AI, just API
FROM python:3.9-alpine

WORKDIR /app

# Install minimal dependencies
RUN apk add --no-cache wget curl

# Copy requirements (minimal)
COPY railway_requirements_minimal.txt requirements.txt

# Install Python packages
RUN pip install --no-cache-dir -r requirements.txt

# Copy app
COPY railway_app_simple.py .

# Create uploads
RUN mkdir -p /app/uploads

EXPOSE 8000
CMD ["python", "railway_app_simple.py"]
