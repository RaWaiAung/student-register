# Student Register

Simple student register: NestJS + Prisma + MySQL backend, React (Vite) frontend, all in Docker.

## Run

```bash
docker compose up --build
```

- Frontend: http://localhost:8080
- API: http://localhost:3000/api/students
- MySQL: localhost:3307 (user `student` / `student123`, db `student_register`)

The backend runs `prisma migrate deploy` on startup, so the `Student` table is created automatically.

## API

| Method | URL | Body |
|---|---|---|
| GET | `/api/students` | – returns `[{ id, name, createdAt }]` |
| POST | `/api/students` | `{ "name": "Aung", "password": "secret123" }` |

Passwords are hashed with bcrypt and never returned. Names are unique (duplicate → 409).

## Local dev (without Docker for the apps)

```bash
docker compose up -d mysql
cd backend && cp .env.example .env && npm install && npx prisma migrate dev && npm run start:dev
cd frontend && npm install && npm run dev   # proxies /api to :3000
```

## Production

```bash
./deploy.sh          # build + start (creates .env.prod with random DB passwords on first run)
./deploy.sh status   # container status
./deploy.sh logs     # follow logs (e.g. ./deploy.sh logs backend)
./deploy.sh backup   # dump MySQL to backups/
./deploy.sh clean    # free disk: remove unused images/build cache (DB data kept)
./deploy.sh down     # stop
```

Uses `docker-compose.prod.yml`: only the frontend is published (port `APP_PORT`, default 80); MySQL and the API are internal-only.
