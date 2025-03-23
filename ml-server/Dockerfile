FROM python:3.9-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    git \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements first to leverage Docker cache
COPY requirements.txt .

# Install pip packages with increased timeout
RUN pip install --no-cache-dir --timeout 100 -r requirements.txt

# Install gunicorn for production server
RUN pip install --no-cache-dir gunicorn

# Pre-download the model during build
RUN python -c "from sentence_transformers import SentenceTransformer; SentenceTransformer('all-MiniLM-L6-v2')"

# Copy the rest of the application
COPY . .

# Set environment variables for better connection handling
ENV HF_HUB_DOWNLOAD_TIMEOUT=500
ENV HF_HUB_ENABLE_HF_TRANSFER=1

# Expose the port the app runs on
EXPOSE 8000

# Command to run the application
# Use gunicorn with uvicorn workers for production
CMD ["gunicorn", "-k", "uvicorn.workers.UvicornWorker", "main:app", "--bind", "0.0.0.0:8000", "--workers", "4"]