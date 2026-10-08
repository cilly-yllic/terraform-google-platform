# Multi-stage build for cloud-run-router (Hono + @hono/node-server on Node 24).
#
# Stage 1 (builder): tsc コンパイルを走らせて dist/ を作る。
# Stage 2 (runtime): dist/ と package.json だけを持ち込み、本番依存だけを
#                    `npm ci --omit=dev` で入れる (image サイズ最小化)。

FROM node:24-slim AS builder
WORKDIR /app

COPY package*.json ./
RUN npm ci

COPY tsconfig.json ./
COPY src/ src/
RUN npm run build

FROM node:24-slim
WORKDIR /app

COPY --from=builder /app/dist dist/
COPY --from=builder /app/package*.json ./

# 本番依存のみインストール (hono / @hono/node-server)
RUN npm ci --omit=dev && npm cache clean --force

ENV NODE_ENV=production
EXPOSE 8080

# 公式 image 同梱の非 root ユーザーで実行 (最小権限)
USER node

CMD ["node", "dist/index.js"]
