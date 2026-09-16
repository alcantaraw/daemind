FROM python:slim

# Metadados de Governança
LABEL maintainer="Wellington Alcantara <alcantaraw@gmail.com>"
LABEL description="Microsserviço Soberano de Extração de Documentos & OCR (MarkItDown + Tesseract)"

# Instala dependências nativas para Tesseract OCR, PDF e mídia
RUN apt-get update && apt-get install -y --no-install-recommends \
    tesseract-ocr \
    tesseract-ocr-por \
    tesseract-ocr-eng \
    libtesseract-dev \
    poppler-utils \
    ffmpeg \
    curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Instala bibliotecas Python
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copia código do microsserviço
COPY main.py .

# Cria diretório temporário para uploads/processamento
RUN mkdir -p /tmp/markitdown_uploads && chmod 777 /tmp/markitdown_uploads

EXPOSE 5001

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "5001", "--workers", "2", "--log-level", "warning"]
