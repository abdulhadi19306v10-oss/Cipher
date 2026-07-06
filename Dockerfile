# Python Backend Deployment for Cipher
FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y libpq-dev gcc

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy FastAPI and raw socket server files
COPY api/ api/
COPY chat_server.py .

# Expose ports: 8000 for FastAPI, 5000 for TCP/UDP raw socket
EXPOSE 8000
EXPOSE 5000

# Script to run both servers (in production you might use supervisord)
RUN echo "#!/bin/bash\nuvicorn api.main:app --host 0.0.0.0 --port 8000 & python chat_server.py\nwait" > start.sh
RUN chmod +x start.sh

CMD ["./start.sh"]
