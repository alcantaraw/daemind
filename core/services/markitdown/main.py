import os
import shutil
import tempfile
from pathlib import Path
from fastapi import FastAPI, File, UploadFile, Request, Response, HTTPException
from fastapi.responses import JSONResponse, PlainTextResponse
from markitdown import MarkItDown
import pytesseract
from PIL import Image
from pdf2image import convert_from_path

app = FastAPI(
    title="MarkItDown & Tesseract OCR Service",
    description="Serviço unificado de conversão de documentos e OCR para o ecossistema daemind.",
    version="1.0.0"
)

md_converter = MarkItDown()

IMAGE_EXTENSIONS = {".png", ".jpg", ".jpeg", ".tiff", ".bmp", ".webp"}

def extract_text_with_ocr(file_path: str, ext: str) -> str:
    """Executa OCR usando Tesseract com suporte a Português e Inglês."""
    if ext in IMAGE_EXTENSIONS:
        img = Image.open(file_path)
        return pytesseract.image_to_string(img, lang="por+eng")
    elif ext == ".pdf":
        try:
            pages = convert_from_path(file_path)
            ocr_text = []
            for i, page in enumerate(pages):
                page_text = pytesseract.image_to_string(page, lang="por+eng")
                ocr_text.append(f"<!-- Page {i+1} -->\n{page_text}")
            return "\n\n".join(ocr_text)
        except Exception as e:
            return f"Erro no OCR de PDF: {str(e)}"
    return ""

def process_file(file_path: str) -> str:
    """
    Processa arquivos com MarkItDown.
    Se for imagem pura ou se o MarkItDown retornar pouco texto em PDFs escaneados,
    aplica fallback inteligente para Tesseract OCR.
    """
    ext = Path(file_path).suffix.lower()

    if ext in IMAGE_EXTENSIONS:
        return extract_text_with_ocr(file_path, ext)

    try:
        result = md_converter.convert(file_path)
        content = result.text_content.strip() if result and result.text_content else ""
        if ext == ".pdf" and len(content) < 50:
            # Possível PDF escaneado / sem texto selecionável
            ocr_content = extract_text_with_ocr(file_path, ext)
            if len(ocr_content.strip()) > len(content):
                return ocr_content
        return content
    except Exception as e:
        if ext == ".pdf":
            return extract_text_with_ocr(file_path, ext)
        raise e

@app.get("/health")
def health_check():
    return {
        "status": "healthy",
        "service": "markitdown-tesseract",
        "ocr_languages": ["por", "eng"],
        "engine": "markitdown"
    }

@app.post("/v1/convert")
@app.post("/convert")
async def convert_file(file: UploadFile = File(...)):
    """Rota canônica de conversão multipart para o ecossistema e n8n."""
    suffix = Path(file.filename).suffix if file.filename else ".tmp"
    with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
        shutil.copyfileobj(file.file, tmp)
        tmp_path = tmp.name

    try:
        extracted = process_file(tmp_path)
        return {
            "filename": file.filename,
            "content": extracted,
            "format": "markdown"
        }
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Erro ao processar documento: {str(exc)}")
    finally:
        if os.path.exists(tmp_path):
            try:
                os.remove(tmp_path)
            except OSError:
                pass

@app.put("/tika")
@app.post("/tika")
async def tika_raw_stream(request: Request):
    """
    Emulação da API Apache Tika (Stream binário no body)
    Consumida nativamente pelo Open WebUI com CONTENT_EXTRACTION_ENGINE=tika.
    """
    body = await request.body()
    with tempfile.NamedTemporaryFile(delete=False, suffix=".bin") as tmp:
        tmp.write(body)
        tmp_path = tmp.name

    try:
        extracted = process_file(tmp_path)
        return PlainTextResponse(extracted)
    except Exception as exc:
        return PlainTextResponse(f"Erro na extração: {str(exc)}", status_code=500)
    finally:
        if os.path.exists(tmp_path):
            try:
                os.remove(tmp_path)
            except OSError:
                pass

@app.post("/tika/form")
async def tika_form_multipart(file: UploadFile = File(...)):
    """Emulação da API Tika via multipart/form-data."""
    suffix = Path(file.filename).suffix if file.filename else ".tmp"
    with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
        shutil.copyfileobj(file.file, tmp)
        tmp_path = tmp.name

    try:
        extracted = process_file(tmp_path)
        return PlainTextResponse(extracted)
    except Exception as exc:
        return PlainTextResponse(f"Erro na extração: {str(exc)}", status_code=500)
    finally:
        if os.path.exists(tmp_path):
            try:
                os.remove(tmp_path)
            except OSError:
                pass
