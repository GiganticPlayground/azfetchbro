# syntax=docker/dockerfile:1.7

FROM node:20-alpine AS deps
WORKDIR /app
COPY ./azfetchbro-service/package*.json ./
RUN npm ci --omit=dev

FROM node:20-alpine AS runner
WORKDIR /app

RUN addgroup -S tb && adduser -S tb -G tb

COPY --from=deps /app/node_modules ./node_modules
COPY ./azfetchbro-service/dist ./dist/

USER tb

ENV NODE_ENV=production \
    HOST=0.0.0.0 \
    PORT=8080 \
    TB_ADX_RESOURCE=https://api.kusto.windows.net \
    TB_EXPIRY_SKEW_MS=120000 \
    TB_DEFAULT_SAS_TTL_MS=86400000 \
    TB_POLICY_FILE=/etc/azfetchbro/policy.json \
    TB_TOKENS_FILE=/etc/azfetchbro/tokens.json

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:8080/healthz').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

CMD ["node", "dist/server.js"]