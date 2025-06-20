# backend/Dockerfile
FROM node:20-alpine AS builder

WORKDIR /app

# 패키지 파일 복사
COPY package*.json ./
# 빌드를 위해 모든 의존성 설치
RUN npm ci

# 소스 코드 복사
COPY . .

# TypeScript 빌드
RUN npm run build

# 프로덕션 의존성만 따로 설치
RUN npm prune --production

# ---

# 프로덕션 이미지
FROM node:20-alpine AS production

WORKDIR /app

# 보안을 위한 non-root 사용자 생성
RUN addgroup -g 1001 -S nodejs
RUN adduser -S nestjs -u 1001

# 의존성 및 빌드 결과물 복사
COPY --from=builder --chown=nestjs:nodejs /app/node_modules ./node_modules
COPY --from=builder --chown=nestjs:nodejs /app/dist ./dist
COPY --from=builder --chown=nestjs:nodejs /app/package*.json ./

# 헬스체크 추가
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:3000/health || exit 1

USER nestjs

EXPOSE 3000

CMD ["node", "-r", "crypto", "dist/main"]
