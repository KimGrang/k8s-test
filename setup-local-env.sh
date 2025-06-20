set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}🚀 로컬 개발 환경 설정을 시작합니다...${NC}"

# 1. 필수 도구 확인
check_requirements() {
    echo -e "${YELLOW}📋 필수 도구 확인 중...${NC}"

    command -v minikube >/dev/null 2>&1 || {
        echo -e "${RED}❌ minikube가 설치되지 않았습니다.${NC}"
        echo "설치: https://minikube.sigs.k8s.io/docs/start/"
        exit 1
    }

    command -v kubectl >/dev/null 2>&1 || {
        echo -e "${RED}❌ kubectl이 설치되지 않았습니다.${NC}"
        exit 1
    }

    command -v docker >/dev/null 2>&1 || {
        echo -e "${RED}❌ Docker가 설치되지 않았습니다.${NC}"
        exit 1
    }

    echo -e "${GREEN}✅ 모든 필수 도구가 설치되어 있습니다.${NC}"
}

# 2. minikube 시작
start_minikube() {
    echo -e "${YELLOW}🏗️  minikube 클러스터 시작 중...${NC}"

    minikube start --driver=docker --memory=4096 --cpus=2

    # 필요한 애드온 활성화
    minikube addons enable ingress
    minikube addons enable registry
    minikube addons enable metrics-server

    echo -e "${GREEN}✅ minikube 클러스터가 시작되었습니다.${NC}"
}

# 3. 로컬 Docker 레지스트리 설정
setup_registry() {
    echo -e "${YELLOW}📦 로컬 Docker 레지스트리 설정 중...${NC}"

    # 레지스트리 포트 포워딩 (백그라운드에서 실행)
    kubectl port-forward --namespace kube-system service/registry 5000:80 &
    REGISTRY_PID=$!

    # 포트 포워딩이 준비될 때까지 대기
    sleep 5

    echo "REGISTRY_PID=$REGISTRY_PID" > .registry-pid
    echo -e "${GREEN}✅ 로컬 레지스트리가 localhost:5000에서 실행 중입니다.${NC}"
}

# 4. hosts 파일 업데이트 (선택사항)
update_hosts() {
    echo -e "${YELLOW}🌐 hosts 파일 업데이트 중...${NC}"

    MINIKUBE_IP=$(minikube ip)

    # hosts 파일에 항목 추가 (관리자 권한 필요)
    if command -v sudo >/dev/null 2>&1; then
        echo "다음 항목을 /etc/hosts에 추가하려면 sudo 권한이 필요합니다:"
        echo "$MINIKUBE_IP api.local"
        echo "$MINIKUBE_IP dashboard.local"

        read -p "계속하시겠습니까? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            sudo bash -c "echo '$MINIKUBE_IP api.local' >> /etc/hosts"
            sudo bash -c "echo '$MINIKUBE_IP dashboard.local' >> /etc/hosts"
            echo -e "${GREEN}✅ hosts 파일이 업데이트되었습니다.${NC}"
        fi
    fi
}

# 5. Docker 이미지 빌드
build_images() {
    echo -e "${YELLOW}🔨 Docker 이미지 빌드 중...${NC}"

    # minikube의 Docker 환경 사용
    eval $(minikube docker-env)

    # 백엔드 이미지 빌드
    if [ -d "backend" ]; then
        echo "백엔드 이미지 빌드 중..."
        docker build -t localhost:5000/nestjs-backend:latest ./backend
        docker push localhost:5000/nestjs-backend:latest
    fi

    # 웹 대시보드 이미지 빌드
    if [ -d "web-dashboard" ]; then
        echo "웹 대시보드 이미지 빌드 중..."
        docker build -t localhost:5000/web-dashboard:latest ./web-dashboard
        docker push localhost:5000/web-dashboard:latest
    fi

    echo -e "${GREEN}✅ Docker 이미지 빌드 완료${NC}"
}

# 6. Kubernetes 리소스 배포
deploy_to_k8s() {
    echo -e "${YELLOW}⚙️  Kubernetes 리소스 배포 중...${NC}"

    # 네임스페이스 생성
    kubectl apply -f k8s/namespace.yaml

    # 시크릿 생성
    kubectl apply -f k8s/secrets.yaml

    # 모든 리소스 배포
    kubectl apply -f k8s/

    # 배포 상태 확인
    echo -e "${YELLOW}📊 배포 상태 확인 중...${NC}"
    kubectl rollout status deployment/nestjs-backend -n app-deployment --timeout=300s
    kubectl rollout status deployment/web-dashboard -n app-deployment --timeout=300s

    echo -e "${GREEN}✅ Kubernetes 배포 완료${NC}"
}

# 7. 서비스 URL 출력
show_urls() {
    echo -e "${YELLOW}🔗 서비스 접속 정보${NC}"

    MINIKUBE_IP=$(minikube ip)

    echo -e "📍 서비스 URL:"
    echo -e "   백엔드 API: http://api.local (또는 http://$MINIKUBE_IP:$(kubectl get svc nestjs-backend-service -n app-deployment -o jsonpath='{.spec.ports[0].nodePort}'))"
    echo -e "   웹 대시보드: http://dashboard.local (또는 http://$MINIKUBE_IP:30080)"
    echo -e "   Kubernetes 대시보드: minikube dashboard"

    echo -e "\n📊 상태 확인 명령어:"
    echo -e "   kubectl get pods -n app-deployment"
    echo -e "   kubectl get svc -n app-deployment"
    echo -e "   kubectl logs -f deployment/nestjs-backend -n app-deployment"
}

# 8. 정리 함수
cleanup() {
    echo -e "${YELLOW}🧹 정리 작업 수행 중...${NC}"

    if [ -f ".registry-pid" ]; then
        REGISTRY_PID=$(cat .registry-pid | cut -d'=' -f2)
        kill $REGISTRY_PID 2>/dev/null || true
        rm .registry-pid
    fi

    kubectl delete namespace app-deployment --ignore-not-found=true
    minikube stop

    echo -e "${GREEN}✅ 정리 완료${NC}"
}

# 메인 실행 함수
main() {
    case "${1:-setup}" in
        "setup")
            check_requirements
            start_minikube
            setup_registry
            update_hosts
            build_images
            deploy_to_k8s
            show_urls
            ;;
        "build")
            build_images
            deploy_to_k8s
            ;;
        "deploy")
            deploy_to_k8s
            ;;
        "cleanup")
            cleanup
            ;;
        "urls")
            show_urls
            ;;
        *)
            echo "사용법: $0 [setup|build|deploy|cleanup|urls]"
            echo "  setup   - 전체 환경 설정 (기본값)"
            echo "  build   - 이미지 빌드 및 재배포"
            echo "  deploy  - Kubernetes 리소스만 재배포"
            echo "  cleanup - 환경 정리"
            echo "  urls    - 서비스 URL 확인"
            exit 1
            ;;
    esac
}

# 스크립트 실행
main "$@"