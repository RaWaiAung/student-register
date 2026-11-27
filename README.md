# Student Register

Simple student register: NestJS + Prisma + MySQL backend, React (Vite + Material UI) frontend.

## API

| Method | URL | Body |
|---|---|---|
| GET | `/api/students` | – returns `[{ id, name, createdAt }]` |
| POST | `/api/students` | `{ "name": "Aung", "password": "secret123" }` |

Passwords are hashed with bcrypt and never returned. Names are unique (duplicate → 409).

## Run locally

Needs a MySQL server. Set `DATABASE_URL` in `backend/.env` (see `backend/.env.example`).

```bash
cd backend && npm install && npx prisma migrate deploy && npm run start:dev   # http://localhost:3000
cd frontend && npm install && npm run dev                                     # http://localhost:5173 (proxies /api to :3000)
```

## Deploy

See **[DEPLOY-EC2.md](DEPLOY-EC2.md)** for step-by-step AWS EC2 (Free Tier) deployment.
