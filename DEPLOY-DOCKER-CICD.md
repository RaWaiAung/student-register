# Production Deploy with Docker Compose (multi-stage) + GitHub Actions CI/CD

**Flow:** `git push` to `main` → **GitHub Actions** lints & builds → builds multi-stage Docker images → pushes them to **GitHub Container Registry (ghcr.io)** → SSH into **EC2** → `docker compose pull && up -d`.

Images are built on GitHub's servers, **not on EC2**, so a Free Tier t2/t3.micro (1 GB RAM) only has to *run* them.

```
 Mac ──git push──▶ GitHub ──Actions──▶ ghcr.io (images)
                                   └──SSH──▶ EC2: docker compose pull && up -d
                                              ├─ frontend (nginx :80)  ──/api──▶ backend (NestJS :3000)
                                              └─ mysql (internal only) ◀─────────┘
```

> Replace `<github-user>`, `<EC2-IP>` and the passwords with your own.
> GHCR image names must be **lowercase** — use your GitHub username in lowercase.

---

## Part A — Add the Docker files to the project [Mac]

Final layout:

```
student-register/
├── .github/workflows/deploy.yml
├── docker-compose.prod.yml
├── backend/
│   ├── Dockerfile
│   └── .dockerignore
└── frontend/
    ├── Dockerfile
    ├── .dockerignore
    └── nginx.conf
```

### A1. `backend/Dockerfile` (multi-stage)

Installs **production dependencies only** (no Nest CLI / Jest / ESLint), compiles with `tsc`, trims `node_modules`, and copies the result into a clean runtime image.

```dockerfile
# ---- Stage 1: build ----
FROM node:22-alpine AS build
RUN apk add --no-cache openssl
WORKDIR /app
COPY package*.json ./
COPY prisma ./prisma
RUN npm ci --omit=dev --no-audit --no-fund \
 && npx prisma generate \
 && npm cache clean --force
COPY tsconfig*.json ./
COPY src ./src
# Node type definitions only for compiling, then deleted
RUN npm i --prefix /tmp/types --no-save --no-audit --no-fund @types/node@22 \
 && npx tsc -p tsconfig.build.json --typeRoots /tmp/types/node_modules/@types --types node \
 && rm -rf /tmp/types /root/.npm /root/.cache \
 && cd node_modules \
 && find @prisma/client/runtime -name '*wasm*' -delete \
 && rm -rf prisma/prisma-client rxjs/src rxjs/dist/bundles \
 && find . -type f \( -name '*.map' -o -name '*.d.ts' -o -name '*.d.mts' -o -name '*.d.cts' \
      -o -iname 'README*' -o -iname 'CHANGELOG*' \) -delete

# ---- Stage 2: runtime ----
FROM node:22-alpine
RUN apk add --no-cache openssl
WORKDIR /app
ENV NODE_ENV=production
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/package.json ./package.json
COPY --from=build /app/prisma ./prisma
COPY --from=build /app/dist ./dist
USER node
EXPOSE 3000
# Apply DB migrations, then start the API
CMD ["sh", "-c", "./node_modules/.bin/prisma migrate deploy && exec node dist/main"]
```

> Requires `binaryTargets = ["native", "linux-musl-openssl-3.0.x"]` in `backend/prisma/schema.prisma` (already set).

### A2. `backend/.dockerignore`

```
node_modules
dist
.env
.env.*
coverage
test
.git
*.md
```

### A3. `frontend/Dockerfile` (multi-stage)

```dockerfile
# ---- Stage 1: build the React app ----
FROM node:22-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci --no-audit --no-fund
COPY . .
RUN npm run build

# ---- Stage 2: serve static files with nginx (~50 MB image) ----
FROM nginx:1.27-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 80
```

### A4. `frontend/.dockerignore`

```
node_modules
dist
.git
*.md
```

### A5. `frontend/nginx.conf`

```nginx
server {
  listen 80;
  root /usr/share/nginx/html;
  index index.html;

  gzip on;
  gzip_types text/css application/javascript application/json image/svg+xml;
  gzip_min_length 1024;

  # API → backend container
  location /api/ {
    proxy_pass http://backend:3000;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
  }

  # hashed build assets can be cached for a long time
  location /assets/ {
    expires 1y;
    add_header Cache-Control "public, immutable";
  }

  location / {
    try_files $uri $uri/ /index.html;
  }
}
```

### A6. `docker-compose.prod.yml` (project root)

Pulls ready-made images from ghcr.io. Memory limits fit a 1 GB instance; only port 80 is published.

```yaml
name: student-register

x-logging: &logging
  driver: json-file
  options:
    max-size: "5m"     # keep logs from filling the disk
    max-file: "2"

services:
  mysql:
    image: mysql:8.4
    restart: always
    command:              # low-memory settings for 1 GB RAM
      - --performance-schema=OFF
      - --innodb-buffer-pool-size=64M
      - --max-connections=30
      - --key-buffer-size=8M
      - --tmp-table-size=16M
      - --max-heap-table-size=16M
    environment:
      MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD:?set in .env}
      MYSQL_DATABASE: ${MYSQL_DATABASE:-student_register}
      MYSQL_USER: ${MYSQL_USER:-student}
      MYSQL_PASSWORD: ${MYSQL_PASSWORD:?set in .env}
    volumes:
      - mysql_data:/var/lib/mysql
    mem_limit: 400m
    healthcheck:
      test: ["CMD-SHELL", "mysqladmin ping -h localhost -uroot -p$$MYSQL_ROOT_PASSWORD"]
      interval: 10s
      timeout: 5s
      retries: 30
    logging: *logging

  backend:
    image: ${IMAGE_PREFIX:?set in .env}-backend:${TAG:-latest}
    restart: always
    environment:
      NODE_ENV: production
      PORT: 3000
      NODE_OPTIONS: --max-old-space-size=160
      DATABASE_URL: mysql://${MYSQL_USER:-student}:${MYSQL_PASSWORD}@mysql:3306/${MYSQL_DATABASE:-student_register}
    depends_on:
      mysql:
        condition: service_healthy
    mem_limit: 256m
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://localhost:3000/api/students >/dev/null || exit 1"]
      interval: 15s
      timeout: 5s
      retries: 10
      start_period: 30s
    logging: *logging

  frontend:
    image: ${IMAGE_PREFIX}-frontend:${TAG:-latest}
    restart: always
    ports:
      - "80:80"
    depends_on:
      backend:
        condition: service_healthy
    mem_limit: 64m
    logging: *logging

volumes:
  mysql_data:
```

### A7. `.github/workflows/deploy.yml`

Three jobs: **ci** (lint + build check) → **build** (multi-stage images → ghcr.io) → **deploy** (SSH to EC2).

```yaml
name: CI/CD

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: read
  packages: write

concurrency:
  group: deploy-${{ github.ref }}
  cancel-in-progress: false

jobs:
  # ---------- 1. Lint & build check ----------
  ci:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        app: [backend, frontend]
    defaults:
      run:
        working-directory: ${{ matrix.app }}
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 22
          cache: npm
          cache-dependency-path: ${{ matrix.app }}/package-lock.json
      - run: npm ci
      - if: matrix.app == 'backend'
        run: npx prisma generate
      - run: npm run lint
      - run: npm run build

  # ---------- 2. Build & push images (only on main) ----------
  build:
    needs: ci
    if: github.event_name != 'pull_request'
    runs-on: ubuntu-latest
    strategy:
      matrix:
        app: [backend, frontend]
    steps:
      - uses: actions/checkout@v4

      - name: Image name (lowercase)
        run: echo "IMAGE=ghcr.io/${GITHUB_REPOSITORY_OWNER,,}/student-register-${{ matrix.app }}" >> "$GITHUB_ENV"

      - uses: docker/setup-buildx-action@v3

      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - uses: docker/build-push-action@v6
        with:
          context: ./${{ matrix.app }}
          platforms: linux/amd64          # t2/t3.micro; use linux/arm64 for t4g
          push: true
          tags: |
            ${{ env.IMAGE }}:latest
            ${{ env.IMAGE }}:${{ github.sha }}
          cache-from: type=gha,scope=${{ matrix.app }}
          cache-to: type=gha,mode=max,scope=${{ matrix.app }}

  # ---------- 3. Deploy to EC2 ----------
  deploy:
    needs: build
    if: github.event_name != 'pull_request'
    runs-on: ubuntu-latest
    environment: production
    steps:
      - uses: actions/checkout@v4

      - name: Copy docker-compose.prod.yml to EC2
        uses: appleboy/scp-action@v0.1.7
        with:
          host: ${{ secrets.EC2_HOST }}
          username: ${{ secrets.EC2_USER }}
          key: ${{ secrets.EC2_SSH_KEY }}
          source: docker-compose.prod.yml
          target: ~/student-register

      - name: Pull images & restart
        uses: appleboy/ssh-action@v1.2.0
        with:
          host: ${{ secrets.EC2_HOST }}
          username: ${{ secrets.EC2_USER }}
          key: ${{ secrets.EC2_SSH_KEY }}
          script_stop: true
          script: |
            cd ~/student-register
            echo "${{ secrets.GITHUB_TOKEN }}" | docker login ghcr.io -u ${{ github.actor }} --password-stdin
            export TAG=${{ github.sha }}
            docker compose -f docker-compose.prod.yml --env-file .env pull
            docker compose -f docker-compose.prod.yml --env-file .env up -d --remove-orphans --wait
            docker logout ghcr.io
            docker image prune -af
            docker compose -f docker-compose.prod.yml --env-file .env ps
```

> Action versions are pinned to known releases; you can bump them (e.g. `actions/checkout@v5`) when newer ones are available.

Commit and push:

```bash
git add .
git commit -m "Add multi-stage Dockerfiles, prod compose and CI/CD"
git push
```

(The first run's **deploy** job will fail until Parts B and C are done — that's expected.)

---

## Part B — Prepare the EC2 instance (one time)

### B1. Launch the instance (AWS console → EC2 → Launch instance)

| Setting | Value |
|---|---|
| AMI | Ubuntu Server 24.04 LTS |
| Instance type | t2.micro or t3.micro (Free Tier) |
| Key pair | Create one, download the `.pem` |
| Storage | **20 GB** gp3 (Free Tier covers up to 30 GB — confirm in Billing → Free Tier) |
| Security group | **HTTP 80** from Anywhere · **SSH 22** from Anywhere* |

\* GitHub Actions runners use changing IP addresses, so SSH must accept connections from anywhere. It is still protected by the SSH key (password login is disabled on Ubuntu AMIs). Never open 3000 or 3306.

### B2. Install Docker + Compose plugin [EC2]

```bash
ssh -i ~/Downloads/your-key.pem ubuntu@<EC2-IP>

curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker ubuntu
exit                      # log out and back in so the group applies
```

```bash
ssh -i ~/Downloads/your-key.pem ubuntu@<EC2-IP>
docker compose version    # should work without sudo
```

### B3. Create the app folder and `.env` [EC2]

```bash
mkdir -p ~/student-register && cd ~/student-register
nano .env
```

```env
# ghcr.io/<github-user in lowercase>/student-register
IMAGE_PREFIX=ghcr.io/<github-user>/student-register

MYSQL_DATABASE=student_register
MYSQL_USER=student
MYSQL_PASSWORD=StudentPass123
MYSQL_ROOT_PASSWORD=MyRootPass123
```

```bash
chmod 600 .env
```

> Use letters and numbers only in `MYSQL_PASSWORD` (it is placed inside the `DATABASE_URL`), or URL-encode `@ : / #`.
> `.env` lives only on the server — never commit it.

---

## Part C — Configure GitHub (one time)

### C1. Repository secrets

GitHub repo → **Settings → Secrets and variables → Actions → New repository secret**:

| Secret | Value |
|---|---|
| `EC2_HOST` | EC2 public IP (or DNS) |
| `EC2_USER` | `ubuntu` |
| `EC2_SSH_KEY` | Full contents of your `.pem` file (`cat ~/Downloads/your-key.pem`), including the `-----BEGIN…` / `-----END…` lines |

`GITHUB_TOKEN` is provided automatically — no need to create it.

### C2. Environment (optional approval gate)

Repo → **Settings → Environments → New environment** → `production`.
Optionally add **Required reviewers** so every deploy waits for your approval.

### C3. Workflow permissions

Repo → **Settings → Actions → General → Workflow permissions** → **Read and write permissions** → Save.

---

## Part D — Deploy

Push to `main` (or **Actions → CI/CD → Run workflow**):

```bash
git push
```

Watch it in the **Actions** tab: `ci` → `build` → `deploy`.
Then open **http://\<EC2-IP\>**.

On first start the backend runs `prisma migrate deploy`, which creates the `Student` table automatically.

---

## Everyday workflow

| You do | What happens |
|---|---|
| Open a Pull Request | `ci` runs lint + build (no deploy) |
| Merge / push to `main` | Lint → build images → push to ghcr.io → deploy to EC2 |
| Re-deploy without code change | Actions → CI/CD → **Run workflow** |

### Roll back to a previous version [EC2]

Every image is also tagged with its commit SHA:

```bash
cd ~/student-register
TAG=<old-commit-sha> docker compose -f docker-compose.prod.yml --env-file .env up -d
```

(Private repo: run `docker login ghcr.io -u <github-user>` first with a Personal Access Token that has `read:packages`.)

---

## Useful commands [EC2]

```bash
cd ~/student-register
alias dc='docker compose -f docker-compose.prod.yml --env-file .env'

dc ps                     # status
dc logs -f backend        # backend logs
dc logs -f mysql          # mysql logs
dc restart backend
dc down                   # stop (data kept in volume mysql_data)
docker stats --no-stream  # memory per container
df -h /                   # disk
docker exec -it student-register-mysql-1 mysql -ustudent -p student_register   # MySQL shell
```

## Back up the database [EC2]

```bash
cd ~/student-register && mkdir -p backups
docker exec student-register-mysql-1 sh -c \
  'exec mysqldump -uroot -p"$MYSQL_ROOT_PASSWORD" --single-transaction "$MYSQL_DATABASE"' \
  > backups/db_$(date +%Y%m%d_%H%M).sql
```

## Test the production images locally [Mac] (optional)

```bash
docker build -t local/student-register-backend ./backend
docker build -t local/student-register-frontend ./frontend
printf 'IMAGE_PREFIX=local/student-register\nMYSQL_PASSWORD=pass123\nMYSQL_ROOT_PASSWORD=root123\n' > .env.local
docker compose -f docker-compose.prod.yml --env-file .env.local up -d
# open http://localhost  → when done:
docker compose -f docker-compose.prod.yml --env-file .env.local down
```

---

## Troubleshooting

| Problem | Fix |
|---|---|
| `deploy` job: `ssh: handshake failed` / `unable to authenticate` | `EC2_SSH_KEY` must be the whole `.pem` content; `EC2_USER` = `ubuntu`; SG port 22 open |
| `deploy` job: `dial tcp … i/o timeout` | Security group doesn't allow SSH 22 from Anywhere, or wrong `EC2_HOST` |
| `denied: permission_denied` when pushing to ghcr.io | Part C3: set Workflow permissions to Read and write |
| `invalid reference format: repository name must be lowercase` | `IMAGE_PREFIX` in `.env` must be lowercase |
| `permission denied … docker.sock` on EC2 | Run `sudo usermod -aG docker ubuntu`, then log out and back in |
| Backend unhealthy, `P1000 Authentication failed` | `MYSQL_PASSWORD` changed after the volume was created → `dc down -v` (**deletes data**) and `dc up -d` |
| `exec format error` | Wrong platform: t4g (ARM) needs `platforms: linux/arm64` |
| Container restarting / OOM | `docker stats`; memory limits are in `docker-compose.prod.yml` |
| `no space left on device` | `docker system prune -af` (volumes are kept), or enlarge the EBS volume |
