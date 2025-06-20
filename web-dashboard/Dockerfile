FROM node:18-alpine AS builder

WORKDIR /app

# 패키지 파일 복사
COPY package*.json ./
RUN npm ci

# 소스 코드 복사
COPY . .

# 환경변수 설정 (빌드 시점)
ARG REACT_APP_API_URL=http://api.local
ENV REACT_APP_API_URL=$REACT_APP_API_URL

# React 앱 빌드
RUN npm run build

# 프로덕션 이미지 (nginx)
FROM nginx:alpine AS production

# nginx 설정 복사
COPY nginx.conf /etc/nginx/nginx.conf

# 빌드된 파일 복사
COPY --from=builder /app/build /usr/share/nginx/html

# 헬스체크 추가
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:80 || exit 1

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
