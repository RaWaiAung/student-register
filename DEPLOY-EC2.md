# Deploy Student Register on AWS EC2 (Free Tier)

**Stack:** Ubuntu on t2/t3.micro (1 GB RAM) → **nginx** serves the React site and forwards `/api` → **NestJS** (run by PM2) → **MySQL** on the same instance.

> **[Mac]** = run on your Mac **[EC2]** = run on the instance over SSH
> Replace `<EC2-IP>`, `your-key.pem`, `<github-user>` and the passwords with your own.

---

## Part A — Push the code to GitHub [Mac] (one time)

### Step 1. Create the repo and push

On github.com, create a new **empty** repository named `student-register` (no README, no .gitignore). Then:

```bash
cd ~/Documents/project/student-register
git add .
git commit -m "Student register: NestJS + Prisma backend, React MUI frontend"
git branch -M main
git remote add origin https://github.com/<github-user>/student-register.git
git push -u origin main
```

> `backend/.env` is in `backend/.gitignore`, so your database password is not uploaded. Check `git status` before committing.

---

## Part B — Launch and prepare the instance (one time)

### Step 2. Launch the instance (AWS console)

**EC2 → Launch instance**:

| Setting | Value |
|---|---|
| AMI | Ubuntu Server 24.04 LTS |
| Instance type | t2.micro or t3.micro (Free Tier eligible) |
| Key pair | Create one and download the `.pem` file |
| Security group | SSH (22) from **My IP** · HTTP (80) from **Anywhere (0.0.0.0/0)** |
| Storage | **20 GB** gp3 (default 8 GB is too small for building) |

> Free Tier covers up to 30 GB of EBS storage — confirm in **Billing → Free Tier** for your account.

### Step 3. Connect [Mac]

```bash
chmod 400 ~/Downloads/your-key.pem
ssh -i ~/Downloads/your-key.pem ubuntu@<EC2-IP>
```

### Step 4. Install software [EC2]

```bash
sudo apt-get update
sudo apt-get install -y git mysql-server nginx
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt-get install -y nodejs
sudo npm install -g pm2
node -v && mysql --version && nginx -v
```

### Step 5. Set up MySQL [EC2]

Low-memory settings for 1 GB RAM:

```bash
sudo tee /etc/mysql/mysql.conf.d/low-memory.cnf <<'EOF'
[mysqld]
performance_schema      = OFF
innodb_buffer_pool_size = 64M
max_connections         = 30
key_buffer_size         = 8M
tmp_table_size          = 16M
max_heap_table_size     = 16M
EOF
sudo systemctl restart mysql
```

Create the database and user (choose your own password):

```bash
sudo mysql <<'EOF'
CREATE DATABASE student_register;
CREATE USER 'student'@'localhost' IDENTIFIED BY 'StudentPass123';
GRANT ALL PRIVILEGES ON student_register.* TO 'student'@'localhost';
FLUSH PRIVILEGES;
EOF
mysql -ustudent -p'StudentPass123' -e "SHOW DATABASES;"
```

> MySQL only listens on localhost — it is not reachable from the internet.

---

## Part C — Get the code and build

### Step 6. Clone from GitHub [EC2]

**Public repo:**

```bash
cd ~
git clone https://github.com/<github-user>/student-register.git
```

**Private repo** — use a deploy key:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/github_deploy -N ""
cat ~/.ssh/github_deploy.pub
```

On GitHub: repo → **Settings → Deploy keys → Add deploy key** → paste the key (read-only is fine). Then:

```bash
cat >> ~/.ssh/config <<'EOF'
Host github.com
  IdentityFile ~/.ssh/github_deploy
EOF
cd ~
git clone git@github.com:<github-user>/student-register.git
```

### Step 7. Build the frontend (first, while memory is free) [EC2]

```bash
cd ~/student-register/frontend
npm ci
NODE_OPTIONS=--max-old-space-size=512 npm run build
ls dist                          # index.html and assets/
```

### Step 8. Publish the frontend files [EC2]

Run inside the `frontend` folder:

```bash
cd ~/student-register/frontend
sudo mkdir -p /var/www/student-register
sudo rm -rf /var/www/student-register/*
sudo cp -r dist/* /var/www/student-register/
sudo chown -R www-data:www-data /var/www/student-register
rm -rf node_modules              # optional: frees ~200 MB
```

### Step 9. Build the backend [EC2]

Use the same password as Step 5:

```bash
cd ~/student-register/backend
echo 'DATABASE_URL="mysql://student:StudentPass123@localhost:3306/student_register"' > .env

npm ci
npx prisma generate
NODE_OPTIONS=--max-old-space-size=512 npm run build
npx prisma migrate deploy        # creates the Student table
npm prune --omit=dev             # removes build tools, saves disk
```

> If the password contains `@ : / #`, URL-encode them in `DATABASE_URL` (e.g. `@` → `%40`).

---

## Part D — Run it

### Step 10. Start the backend with PM2 [EC2]

```bash
cd ~/student-register/backend
pm2 start dist/main.js --name student-api --max-memory-restart 200M
pm2 save
pm2 startup                      # copy and run the sudo command it prints
curl localhost:3000/api/students # should print []
```

### Step 11. Configure nginx [EC2]

```bash
sudo tee /etc/nginx/sites-available/student-register <<'EOF'
server {
  listen 80;
  server_name _;
  root /var/www/student-register;
  index index.html;

  gzip on;
  gzip_types text/css application/javascript application/json image/svg+xml;

  location /api/ {
    proxy_pass http://127.0.0.1:3000;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
  }

  location / {
    try_files $uri $uri/ /index.html;
  }
}
EOF
sudo ln -sf /etc/nginx/sites-available/student-register /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl reload nginx
curl localhost/api/students      # should print [] through nginx
```

### Step 12. Open it

Browse to **http://\<EC2-IP\>** — register a student and it appears in the list.

---

## Part E — Updating later

**[Mac]** push your changes:

```bash
git add . && git commit -m "your change" && git push
```

**[EC2]** pull them:

```bash
cd ~/student-register && git pull
```

**[EC2]** frontend (if it changed):

```bash
cd ~/student-register/frontend && npm ci \
  && NODE_OPTIONS=--max-old-space-size=512 npm run build \
  && sudo rm -rf /var/www/student-register/* \
  && sudo cp -r dist/* /var/www/student-register/
```

**[EC2]** backend (if it changed):

```bash
cd ~/student-register/backend && npm ci && npx prisma generate \
  && NODE_OPTIONS=--max-old-space-size=512 npm run build \
  && npx prisma migrate deploy && npm prune --omit=dev \
  && pm2 restart student-api
```

> `.env` is not in Git, so `git pull` never overwrites it.

---

## Useful commands [EC2]

```bash
pm2 status                       # backend running?
pm2 logs student-api             # backend logs
sudo systemctl status mysql nginx
sudo tail -f /var/log/nginx/error.log
free -m                          # memory
df -h /                          # disk
```

## Troubleshooting

| Problem | Fix |
|---|---|
| Build stops with `Killed` | Out of memory → `pm2 stop student-api`, build, then `pm2 start student-api` |
| `ENOSPC: no space left` | Disk too small → **EC2 → Volumes → Modify** to 20 GB, then `sudo growpart /dev/nvme0n1 1 && sudo resize2fs /dev/root` |
| `git clone` asks for a password / `Permission denied (publickey)` | Repo is private → use the deploy key in Step 6 |
| `P1000 Authentication failed` | Password in `backend/.env` ≠ Step 5 |
| `P1001 Can't reach database` | `sudo systemctl status mysql` |
| `502 Bad Gateway` | Backend not running → `pm2 restart student-api` |
| nginx welcome page instead of the app | Re-run the `rm` and `reload` lines in Step 11 |
