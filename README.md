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
./deploy.sh          # build + start (first run creates .env.prod - set DATABASE_URL, then run again)
./deploy.sh status   # container status
./deploy.sh logs     # follow logs (e.g. ./deploy.sh logs backend)
./deploy.sh clean    # free disk: remove unused images/build cache
./deploy.sh down     # stop
```

Uses `docker-compose.prod.yml` (backend + frontend only). Only the frontend is published (port `APP_PORT`, default 80).

MySQL is **not** included - run it yourself on the instance and set `DATABASE_URL` in `.env.prod`. Example with Docker:

```bash
docker run -d --name mysql --restart always -p 3306:3306 \
  -e MYSQL_ROOT_PASSWORD=<root-pass> -e MYSQL_DATABASE=student_register \
  -e MYSQL_USER=student -e MYSQL_PASSWORD=<pass> \
  -v mysql_data:/var/lib/mysql mysql:8.4
```

Then `DATABASE_URL=mysql://student:<pass>@host.docker.internal:3306/student_register`.
The backend creates the tables automatically on startup (`prisma migrate deploy`).
Don't open port 3306 in the EC2 security group.
