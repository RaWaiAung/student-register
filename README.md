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

## Production (AWS EC2 Free Tier)

See **[DEPLOY-EC2.md](DEPLOY-EC2.md)** – build on your Mac with `./ship.sh`, run on EC2 with `./deploy.sh start`.

Files: `docker-compose.prod.yml` (backend + frontend with memory limits), `mysql/low-memory.cnf`, `ship.sh`, `deploy.sh`.
