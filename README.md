# crimesense-ai
crimesense-ai
CrimeSenseAI
ระบบวิเคราะห์/เชื่อมโยงคดีอาชญากรรมด้วย AI ช่วยลดเวลาสืบสวนและเพิ่มอัตราปิดคดี รองรับการนำเข้าข้อมูลหลายศูนย์ (Multi‑Center), การค้นหาแบบ Keyword/Semantic, การจัดกลุ่มด้วยคลัสเตอร์ และแจ้งเตือนคดีที่มีความคล้ายสูง


คุณสมบัติหลัก (Features)
Multi‑Center Ingestion: นำเข้าข้อมูลจากหลายศูนย์พร้อมกัน แยกประมวลผลเป็นรายศูนย์ และรวมผลภาพรวมได้

AI Processing: ฝังเวกเตอร์ด้วย BGE‑M3, จัดกลุ่ม (HDBSCAN/DBSCAN), สรุปผลสำหรับค้นหาและแสดงผล

Semantic & Keyword Search: ค้นได้ทั้งคำ/ประโยค พร้อมตัวกรองเวลา หน่วยงาน และหมวดหมู่คดี

Similarity Alert: แจ้งเตือนเมื่อพบคดีคล้ายกัน ≥80% และจำนวนพบ ≥3 รายการ

Dashboard/Frontend: หน้าเว็บ React + Tailwind + shadcn/ui (Responsive, Dark mode)

Scheduled Sync: ตั้งเวลา Sync อัตโนมัติ (เที่ยงคืน) อัปเดต Embedding/Cluster/แดชบอร์ด

KPI Tracking (เตรียมการ): ติดตามสเตจคดี (ส่งให้พนักงานสอบสวน → สืบสวน → จับกุม)

สถาปัตยกรรม
flowchart LR
  subgraph Client
    U[User (Investigator/Admin)]
    FE[Web Frontend (React)]
  end

  subgraph Backend
    API[FastAPI Service]
    JOB[Scheduler / Sync Worker]
  end

  subgraph Data
    PG[(PostgreSQL)]
    MSSQL[(External SQL Server<br/>(FIDS/Legacy))]
    VEC[(Embeddings)]
  end

  subgraph Infra
    RP[Traefik Reverse Proxy]
    DKR[Docker Compose]
  end

  U --> FE --> RP --> API
  JOB --> API
  API <--> PG
  API --> VEC
  JOB --> MSSQL
  JOB --> PG
  RP -. dashboard .- U
โครงสร้างโปรเจกต์ (สรุป)
crime_ai_stack/
├── api/                  # FastAPI, routes, ingestion/sync, embedding
├── frontend/             # React + Tailwind + shadcn/ui
├── db/                   # init scripts (PostgreSQL)
├── sql/                  # index & maintenance SQL
├── scripts/              # test_curls.sh และสคริปต์ช่วยงาน
├── docker-compose.yml    # บริการทั้งหมด (traefik, api, db, frontend)
├── Makefile              # คำสั่งช่วย build/run/clean
├── check_backend.sh      # health check
├── reinit_stack.sh       # re-create stack แบบสะอาด
├── reset_and_resync.sh   # reset และ sync ใหม่
└── README.md
การติดตั้งและใช้งาน (Quick Start)
ต้องมี Docker / Docker Compose และ Git
แนะนำ Python 3.10+ หากจะรันงานฝั่ง AI นอกคอนเทนเนอร์
# โคลนโปรเจกต์
git clone https://github.com/autthapolsaiyat/crimesense-ai.git
cd crimesense-ai    # (หากคุณย้าย .git มาไว้ที่โฟลเดอร์หลักแล้ว ให้ cd ไปที่โฟลเดอร์หลักของโปรเจกต์แทน)

# (ทางเลือก) ตั้งค่าตัวแปรแวดล้อม
cp .env.example .env    # แก้ไขค่าใน .env ให้เหมาะสม (อย่าใส่ secrets จริงลง public repo)

# สตาร์ททั้งหมดด้วย Docker
docker compose up -d --build
# หรือใช้ Makefile ถ้ามี target
make build && make up
Endpoints (ค่าเริ่มต้นที่พบได้บ่อย):

Frontend: http://localhost/

API (FastAPI docs): http://localhost/docs

Traefik Dashboard: http://localhost:8088 (ถ้าเปิดพอร์ตนี้ไว้ใน docker-compose)

โปรดตรวจสอบโดเมน/พอร์ตตาม docker-compose.yml ของคุณ (บางสภาพแวดล้อมใช้ *.local ผ่าน Traefik
ตัวอย่าง API (สำหรับ Frontend)
GET /cases — รายการคดี (รองรับ limit, offset)

GET /cases/filters — ตัวเลือกตัวกรอง (ศูนย์, หมวดหมู่ ฯลฯ)

GET /cases/{id} — รายละเอียดคดี

GET /stats — สถิติโดยรวม (จำนวนคดี/หลักฐาน ฯลฯ)

POST /sync — สั่ง sync นำเข้าจากแหล่งข้อมูล (หุ้มสิทธิ์ก่อนใช้จริง)

โครงสร้างจริงอาจต่างจากนี้ตามเวอร์ชันในโค้ด ตรวจสอบจาก api/app.py
ข้อมูลสำคัญด้านความปลอดภัย
ห้าม commit ความลับ เช่น รหัสผ่านฐานข้อมูล, tokens, คีย์ API → ใส่ใน .env (และ .gitignore)

หากใช้งาน Traefik เปิด HTTPS/ACME (Let’s Encrypt) ในการใช้งานจริง

เปิด RBAC + 2FA (TOTP) ในระบบผู้ใช้ก่อนเปิดใช้งานภายนอก

ติดตั้ง WAF + OWASP CRS ที่ reverse proxy (ตาม Roadmap)
Roadmap (ย่อ)
 WAF v4 + TLS/Let’s Encrypt + multi‑upstream

 RBAC + Email registration + 2FA (TOTP)

 Midnight auto‑sync (cron) + retry

 Similarity alert (≥80% & ≥3 รายการ) + notification

 KPI/Outcome Tracking (investigate → arrest)

 เอกสาร TOR/Presentation สำหรับของบประมาณ
License
โครงการนี้ใช้สัญญาอนุญาต MIT (ดูไฟล์ LICENSE)
