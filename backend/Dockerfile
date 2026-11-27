# ---- build stage: full deps to compile TypeScript ----
FROM node:22-alpine AS build
RUN apk add --no-cache openssl
WORKDIR /app
COPY package*.json ./
RUN npm ci --no-audit --no-fund
COPY prisma ./prisma
RUN npx prisma generate
COPY . .
RUN npm run build

# ---- prod deps only (no Nest CLI, Jest, ESLint, SWC...) + prune junk ----
FROM node:22-alpine AS deps
RUN apk add --no-cache openssl
WORKDIR /app
COPY package*.json ./
COPY prisma ./prisma
RUN npm ci --omit=dev --no-audit --no-fund \
 && npx prisma generate \
 && cd node_modules \
 && find @prisma/client/runtime -name '*wasm*' -delete \
 && rm -rf prisma/prisma-client rxjs/src rxjs/dist/bundles \
 && find . -type f \( -name '*.map' -o -name '*.d.ts' -o -name '*.d.mts' -o -name '*.d.cts' \
      -o -iname 'README*' -o -iname 'CHANGELOG*' \) -delete \
 && npm cache clean --force && rm -rf /root/.cache /root/.npm

# ---- runtime ----
FROM node:22-alpine
RUN apk add --no-cache openssl
WORKDIR /app
ENV NODE_ENV=production
COPY --from=deps /app/node_modules ./node_modules
COPY --from=deps /app/package.json ./package.json
COPY prisma ./prisma
COPY --from=build /app/dist ./dist
USER node
EXPOSE 3000
# Apply migrations, then start the API
CMD ["sh", "-c", "./node_modules/.bin/prisma migrate deploy && exec node dist/main"]
