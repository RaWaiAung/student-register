# ---- build: production deps only (no Nest CLI / Jest / ESLint), compile with tsc ----
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
# Node type definitions go to a temp folder just for compiling, then get deleted
RUN npm i --prefix /tmp/types --no-save --no-audit --no-fund @types/node@22 \
 && npx tsc -p tsconfig.build.json --typeRoots /tmp/types/node_modules/@types --types node \
 && rm -rf /tmp/types /root/.npm /root/.cache \
 && cd node_modules \
 && find @prisma/client/runtime -name '*wasm*' -delete \
 && rm -rf prisma/prisma-client rxjs/src rxjs/dist/bundles \
 && find . -type f \( -name '*.map' -o -name '*.d.ts' -o -name '*.d.mts' -o -name '*.d.cts' \
      -o -iname 'README*' -o -iname 'CHANGELOG*' \) -delete

# ---- runtime ----
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
# Apply migrations, then start the API
CMD ["sh", "-c", "./node_modules/.bin/prisma migrate deploy && exec node dist/main"]
