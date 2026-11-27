# Deploy on AWS EC2 Free Tier

Free Tier instance (t2.micro / t3.micro) = **1 GB RAM, x86_64**. That is too small to *build*
Docker images, so the plan is:

- **Your Mac** builds the images → `./ship.sh` streams them to EC2.
- **EC2** only *runs* them: MySQL (≈350 MB) + backend (≤256 MB) + nginx (≤64 MB).

---

## 1. EC2 setup (one time)

### 1a. Disk – make it 20 GB (still free)
Free Tier includes up to **30 GB** of EBS storage, so 20 GB costs nothing
(check *Billing → Free Tier* in the AWS console to confirm for your account).

AWS console → **EC2 → Volumes** → select the instance's volume → **Actions → Modify volume** → Size `20` → Modify.
Then on the instance:

```bash
lsblk                          # disk is nvme0n1 or xvda
sudo growpart /dev/nvme0n1 1   # or: sudo growpart /dev/xvda 1
sudo resize2fs /dev/root
df -h /                        # should show ~19G
```

### 1b. Security group
Inbound rules: **SSH 22** (your IP only) and **HTTP 80** (0.0.0.0/0).
Do **not** open 3306.

### 1c. Install Docker (Ubuntu)
```bash
sudo apt-get update
sudo apt-get install -y docker.io docker-compose-v2
sudo systemctl enable --now docker
sudo docker compose version
```

### 1d. Start MySQL (low-memory settings)
```bash
mkdir -p ~/student-register/mysql
```
Copy `mysql/low-memory.cnf` to `~/student-register/mysql/` (`./ship.sh` also does this), then:

```bash
sudo docker rm -f mysql 2>/dev/null   # only if you created one before (data volume is kept)
sudo docker network create student-net

sudo docker run -d --name mysql --restart always \
  --memory 400m \
  --network student-net \
  -e MYSQL_ROOT_PASSWORD='MyRootPass123' \
  -e MYSQL_DATABASE=student_register \
  -e MYSQL_USER=student \
  -e MYSQL_PASSWORD='StudentPass123' \
  -v mysql_data:/var/lib/mysql \
  -v ~/student-register/mysql/low-memory.cnf:/etc/mysql/conf.d/low-memory.cnf:ro \
  --log-opt max-size=5m --log-opt max-file=2 \
  mysql:8.4

sudo docker logs -f mysql     # wait for "ready for connections", then Ctrl+C
```

- Use your own passwords (no `< >`; keep the quotes).
- No `-p` port: MySQL is reachable only by containers on the `student-net` network (the backend), never from the internet.
- To open a MySQL shell: `sudo docker exec -it mysql mysql -ustudent -p student_register`

### 1e. Create `.env.prod`
```bash
cd ~/student-register
nano .env.prod
```
```
APP_PORT=80
DATABASE_URL=mysql://student:StudentPass123@mysql:3306/student_register
```
(If the password has `@ : / #`, URL-encode them, e.g. `@` → `%40`.)

---

## 2. Deploy from your Mac (every release)

Needs Docker Desktop running on the Mac.

```bash
cd student-register
./ship.sh          # first run creates ship.env – fill it in:
```
```
EC2_HOST=<EC2 public IP>
EC2_USER=ubuntu
SSH_KEY=~/.ssh/<your-key>.pem
REMOTE_DIR=student-register
PLATFORM=linux/amd64
```
```bash
./ship.sh          # builds, uploads, starts
```

Open `http://<EC2 public IP>`.

The backend creates the `Student` table automatically on first start.

---

## 3. Useful commands on EC2

```bash
cd ~/student-register
sudo ./deploy.sh status         # containers
sudo ./deploy.sh logs backend   # follow backend logs
sudo ./deploy.sh restart
sudo ./deploy.sh down
sudo ./deploy.sh clean          # free disk (unused images/build cache)
free -m                         # memory
sudo docker stats --no-stream   # memory per container
df -h /                         # disk
```

## Troubleshooting

| Problem | Fix |
|---|---|
| `ENOSPC: no space left` | `sudo ./deploy.sh clean`, enlarge disk (step 1a) |
| Backend unhealthy, `P1001 Can't reach database` | MySQL not running (`sudo docker ps`), not on `student-net`, or wrong `DATABASE_URL` |
| `P1000 Authentication failed` | Password in `.env.prod` ≠ `MYSQL_PASSWORD` |
| `exec format error` | Wrong `PLATFORM` in ship.env (t4g → `linux/arm64`) |
| Container keeps restarting / OOM | `sudo docker stats`; MySQL settings are in `mysql/low-memory.cnf` |
