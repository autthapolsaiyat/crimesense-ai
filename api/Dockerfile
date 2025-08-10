# api/Dockerfile
FROM python:3.11-slim

ENV TZ=Asia/Bangkok \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# ติดตั้งเครื่องมือเบา ๆ สำหรับ healthcheck/debug
RUN apt-get update && apt-get install -y --no-install-recommends curl && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# ติดตั้ง dependencies ก่อน (ใช้ layer cache)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# คัดลอกซอร์สทั้งหมด
COPY . .

# สร้าง user ที่ไม่ใช่ root และโอนสิทธิ์ไฟล์ให้ใช้งานได้
RUN useradd -m appuser && chown -R appuser:appuser /app
USER appuser

# ให้สอดคล้องกับ Traefik/compose (service api ใช้พอร์ต 8080)
EXPOSE 8080

# มี /health แล้ว healthcheck ของ compose จะยิง curl มาหาพอร์ตนี้
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8080"]

