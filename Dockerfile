# Use an official lightweight Python image
FROM python:3.11-slim

# Set working directory
WORKDIR /app

# Copy dependency file first (for Docker caching)
COPY requirements.txt .

# Install dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy app source code
COPY . .

# Expose Flask port
EXPOSE 5000

# Run the app with Gunicorn (production)
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "app:app"]
