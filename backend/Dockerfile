FROM python:3.12-slim

WORKDIR /app

# Install system dependencies required for OpenCV (used by YOLO) and PyTorch Hub
RUN apt-get update && apt-get install -y \
    libgl1 \
    libglib2.0-0 \
    git \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
# Install python packages
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app

# Expose default port but use Render's dynamic PORT env variable in CMD
EXPOSE 8000
CMD sh -c "uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}"
