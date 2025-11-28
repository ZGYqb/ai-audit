#!/bin/bash

echo "==== AI Audit System: One-Click Deployment ===="

sudo apt update -y
sudo apt install -y docker.io docker-compose git

# 创建根目录
mkdir -p ai-audit
cd ai-audit

# 写入 docker-compose 文件
cat > docker-compose.yml << 'EOF'
version: "3.9"

services:
  ollama:
    image: ollama/ollama:latest
    container_name: ollama
    restart: unless-stopped
    volumes:
      - ./data/ollama:/root/.ollama
    ports:
      - "11434:11434"

  postgres:
    image: postgres:15
    container_name: audit-postgres
    restart: always
    env_file: ./config/postgres.env
    volumes:
      - ./data/postgres:/var/lib/postgresql/data
    ports:
      - "5432:5432"

  chroma:
    image: chromadb/chroma:latest
    container_name: audit-chroma
    restart: always
    volumes:
      - ./data/chroma:/chroma/chroma
    ports:
      - "8000:8000"

  minio:
    image: minio/minio
    container_name: audit-minio
    restart: always
    environment:
      MINIO_ROOT_USER: admin
      MINIO_ROOT_PASSWORD: admin123
    command: server /data --console-address ":9001"
    volumes:
      - ./data/minio:/data
    ports:
      - "9000:9000"
      - "9001:9001"

  ocr:
    build: ./ocr
    container_name: audit-ocr
    restart: always
    ports:
      - "7000:7000"

  api:
    build: ./backend
    container_name: audit-api
    restart: always
    env_file: ./config/api.env
    depends_on:
      - ollama
      - chroma
      - postgres
    ports:
      - "8080:8080"
EOF

# 创建配置文件
mkdir -p config
cat > config/postgres.env << 'EOF'
POSTGRES_USER=audit
POSTGRES_PASSWORD=audit123
POSTGRES_DB=auditdb
EOF

cat > config/api.env << 'EOF'
DB_HOST=postgres
DB_USER=audit
DB_PASSWORD=audit123
DB_NAME=auditdb

CHROMA_HOST=chroma
CHROMA_PORT=8000
OLLAMA_HOST=ollama
OLLAMA_PORT=11434
EOF

# PaddleOCR 服务
mkdir -p ocr
cat > ocr/Dockerfile << 'EOF'
FROM python:3.10

RUN pip install fastapi uvicorn paddlepaddle paddleocr

COPY server.py /server.py

CMD ["uvicorn", "server:app", "--host", "0.0.0.0", "--port", "7000"]
EOF

cat > ocr/server.py << 'EOF'
from fastapi import FastAPI, UploadFile
from paddleocr import PaddleOCR

app = FastAPI()
ocr = PaddleOCR(use_angle_cls=True, lang="ch")

@app.post("/ocr")
async def ocr_api(file: UploadFile):
    content = await file.read()
    with open("temp.jpg", "wb") as f:
        f.write(content)
    result = ocr.ocr("temp.jpg", cls=True)
    return {"result": result}
EOF

# FastAPI 后端
mkdir -p backend
cat > backend/requirements.txt << 'EOF'
fastapi
uvicorn
psycopg2-binary
chromadb
requests
pydantic
EOF

cat > backend/Dockerfile << 'EOF'
FROM python:3.10

WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt

COPY app.py app.py

CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8080"]
EOF

cat > backend/app.py << 'EOF'
from fastapi import FastAPI
import requests

app = FastAPI()

@app.get("/")
def home():
    return {"status": "AI Audit System Running"}

@app.get("/llm")
def llm(q: str):
    payload = {"model": "qwen2.5", "prompt": q}
    r = requests.post("http://ollama:11434/api/generate", json=payload, stream=False)
    return r.json()
EOF

# 创建数据目录
mkdir -p data/postgres data/minio data/chroma

echo "==== Starting Containers ===="
sudo docker-compose up -d

echo "==== Deployment Finished ===="
echo "API: http://<server-ip>:8080/"
echo "OCR: http://<server-ip>:7000/"
echo "MinIO: http://<server-ip>:9001/ (admin/admin123)"
echo "Ollama: http://<server-ip>:11434/"
