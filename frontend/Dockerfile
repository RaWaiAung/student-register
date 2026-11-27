# ---- build stage ----
FROM node:22-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci --no-audit --no-fund
COPY . .
# cap Node memory so the build fits on small EC2 instances (t2/t3.micro)
ENV NODE_OPTIONS=--max-old-space-size=768
RUN npm run build

# ---- runtime: static files only (~25 MB image) ----
FROM nginx:1.27-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 80
