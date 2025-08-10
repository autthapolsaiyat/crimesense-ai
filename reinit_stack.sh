#!/usr/bin/env bash
set -euo pipefail

# ===== SETTINGS =====
STACK_DIR="$(pwd)"               # โฟลเดอร์ที่มี docker-compose.yml
PG_CONTAINER="crime_ai_postgres"
API_CONTAINER="crime_ai_api"
TRAEFIK_CONTAINER="crime_ai_traefik"
MSSQL_CONTAINER="sqlserver_express"
NET_NAME="crime_ai_net"
PG_VOL="crime_ai_pgdata"
LETS_VOL="crime_ai_letsencrypt"
# ตั้งรหัสผ่าน SA ใหม่ (อย่าลืมจด)
export SA_PASSWORD="CrimE@123"

echo "🧭 Working dir: $STACK_DIR"

# ===== (A) BACKUP (เลือกทำ ถ้าต้องการเก็บของเก่า) =====
read -r -p "ต้องการ backup Postgres เดิมก่อนมั้ย? [y/N]: " DO_BACKUP || true
if [[ "${DO_BACKUP:-N}" =~ ^[Yy]$ ]]; then
  if docker ps -a --format '{{.Names}}' | grep -q "^${PG_CONTAINER}$"; then
    echo "🗄️  Backup Postgres..."
    docker exec -i "$PG_CONTAINER" pg_dump -U crimeai -d crime_ai -Fc > "backup_crime_ai_$(date +%Y%m%d_%H%M%S).dump"
    echo "✅ Saved: backup_crime_ai_*.dump"
  else
    echo "ℹ️  ไม่พบคอนเทนเนอร์ $PG_CONTAINER ข้าม backup"
  fi
fi

# ===== (B) NUKE: down + ลบคอนเทนเนอร์/โวลุ่มเก่า =====
echo "🧨 Bringing stack down..."
docker compose down -v || true

echo "🧨 Removing stray containers (if any)..."
docker rm -f "$API_CONTAINER" "$PG_CONTAINER" "$TRAEFIK_CONTAINER" "$MSSQL_CONTAINER" 2>/dev/null || true

echo "🧨 Removing volumes..."
docker volume rm "$PG_VOL" "$LETS_VOL" 2>/dev/null || true

echo "🧨 Removing network..."
docker network rm "$NET_NAME" 2>/dev/null || true

# ===== (C) RECREATE: network + files =====
echo "🌐 Create network..."
docker network create "$NET_NAME" >/dev/null

echo "📝 Writing .env ..."
cat > .env <<'ENV'
# ── Hostnames (เพิ่มใน /etc/hosts ให้ชี้ 127.0.0.1 เมื่อทดสอบในเครื่อง) ─────────
API_HOST=api.crimeai.local
FE_HOST=app.crimeai.local

# ── App / Timezone ─────────────────────────────────────────────────────────────
TZ=Asia/Bangkok

# ── PostgreSQL ────────────────────────────────────────────────────────────────
POSTGRES_USER=crimeai
POSTGRES_PASSWORD=crimeai
POSTGRES_DB=crime_ai
DATABASE_URL=postgresql+psycopg://crimeai:crimeai@db:5432/crime_ai

# ── SQL Server (ภายในสแต็กเดียวกัน) ─────────────────────────────────────────
SQLSERVER_HOST=sqlserver_express
SQLSERVER_PORT=1433
SQLSERVER_DB=FIDSDB
SQLSERVER_USER=sa
SQLSERVER_PASS=CrimE@123
ENV

echo "📝 Writing docker-compose.yml ..."
cat > docker-compose.yml <<'YML'
networks:
  crime_ai_net:
    driver: bridge

volumes:
  crime_ai_pgdata:
  crime_ai_letsencrypt:
  crime_ai_mssql:     # โวลุ่มเก็บข้อมูล MSSQL

services:
  reverse_proxy:
    image: traefik:v3.0
    container_name: crime_ai_traefik
    command:
      - "--api.dashboard=true"
      - "--providers.docker=true"
      - "--entrypoints.web.address=:80"
    ports:
      - "80:80"
      - "8088:8080"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - crime_ai_letsencrypt:/letsencrypt
    restart: unless-stopped
    networks: [crime_ai_net]

  db:
    image: postgres:16-alpine
    container_name: crime_ai_postgres
    environment:
      POSTGRES_USER: ${POSTGRES_USER:-crimeai}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-crimeai}
      POSTGRES_DB: ${POSTGRES_DB:-crime_ai}
      TZ: ${TZ:-Asia/Bangkok}
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U $$POSTGRES_USER -d $$POSTGRES_DB"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 20s
    volumes:
      - crime_ai_pgdata:/var/lib/postgresql/data
    restart: unless-stopped
    networks: [crime_ai_net]

  mssql:
    image: mcr.microsoft.com/mssql/server:2022-latest
    container_name: sqlserver_express
    environment:
      ACCEPT_EULA: "Y"
      SA_PASSWORD: ${SQLSERVER_PASS}
      MSSQL_PID: "Express"
      TZ: ${TZ:-Asia/Bangkok}
    ports:
      - "1433:1433"   # เปิดไว้เผื่อตรวจจาก host
    healthcheck:
      test: ["CMD-SHELL", "/opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P $$SA_PASSWORD -Q 'SELECT 1' -C"]
      interval: 10s
      timeout: 5s
      retries: 20
      start_period: 30s
    volumes:
      - crime_ai_mssql:/var/opt/mssql
    restart: unless-stopped
    networks: [crime_ai_net]

  api:
    build: ./api
    container_name: crime_ai_api
    depends_on:
      db:
        condition: service_healthy
      mssql:
        condition: service_healthy
    env_file: .env
    environment:
      TZ: ${TZ:-Asia/Bangkok}
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.api.rule=Host(`${API_HOST}`)"
      - "traefik.http.services.api.loadbalancer.server.port=8080"
    restart: unless-stopped
    networks: [crime_ai_net]

  frontend:
    build: ./frontend
    container_name: crime_ai_frontend
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.fe.rule=Host(`${FE_HOST}`)"
      - "traefik.http.services.fe.loadbalancer.server.port=80"
    restart: unless-stopped
    networks: [crime_ai_net]
YML

# ===== (D) START CORE WITHOUT API (เพื่อ restore DB ก่อน) =====
echo "🚀 Starting core services (traefik, db, mssql)..."
docker compose up -d reverse_proxy db mssql

echo "⏳ Waiting MSSQL healthy..."
for i in {1..60}; do
  if [[ "$(docker inspect -f '{{.State.Health.Status}}' sqlserver_express 2>/dev/null || echo starting)" == "healthy" ]]; then
    break
  fi
  sleep 2
done
docker inspect -f '{{.State.Health.Status}}' sqlserver_express

# ===== (E) RESTORE FIDSDB จาก .bak (ใช้ชื่อ logical ที่คุณให้: FIDS35DB / FIDS35DB_log) =====
BAK_ON_HOST="${STACK_DIR}/FIDS.bak"
if [[ ! -f "$BAK_ON_HOST" ]]; then
  echo "ℹ️  วางไฟล์สำรอง FIDS.bak ไว้ที่: $BAK_ON_HOST แล้วค่อยรัน restore ด้านล่าง"
else
  echo "📦 Copy backup to container..."
  docker cp "$BAK_ON_HOST" sqlserver_express:/var/opt/mssql/backup/FIDS.bak

  echo "🗂️  RESTORE to FIDSDB..."
  docker exec -it sqlserver_express /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$SA_PASSWORD" -C -Q "
IF DB_ID('FIDSDB') IS NOT NULL
BEGIN
  ALTER DATABASE [FIDSDB] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
  DROP DATABASE [FIDSDB];
END;
RESTORE DATABASE [FIDSDB]
FROM DISK = N'/var/opt/mssql/backup/FIDS.bak'
WITH MOVE N'FIDS35DB'     TO N'/var/opt/mssql/data/FIDSDB.mdf',
     MOVE N'FIDS35DB_log' TO N'/var/opt/mssql/data/FIDSDB_log.ldf',
     REPLACE, RECOVERY, STATS=10;"
fi

echo "🔎 Verify MSSQL..."
docker exec -it sqlserver_express /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$SA_PASSWORD" -C -Q "SELECT name FROM sys.databases;"

# ===== (F) START API & FRONTEND =====
echo "🐳 Build & start API + Frontend..."
docker compose up -d --build api frontend

echo "⏳ Waiting API to start..."
sleep 5

# ===== (G) HEALTH + SYNC TEST (ผ่าน Traefik ที่พอร์ต 80) =====
echo "❤️  /health"
curl -sS -H "Host: api.crimeai.local" http://127.0.0.1/health || true
echo

echo "🔄 /sync (9 ศูนย์)"
curl -sS -X POST -H "Host: api.crimeai.local" -H "Content-Type: application/json" \
  -d '{"prefixes":["01-CSI","01-CNT","01-NBI","01-AYA","01-LRI","01-SPK","01-SRI","01-SBR","01-ATG"]}' \
  http://127.0.0.1/sync || true
echo

echo "📊 /stats"
curl -sS -H "Host: api.crimeai.local" http://127.0.0.1/stats || true
echo

echo "✅ Done."

