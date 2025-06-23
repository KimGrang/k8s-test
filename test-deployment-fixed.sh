set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🧪 배포 테스트 시작${NC}"

# 1. 기본 헬스체크
health_check() {
    echo -e "${YELLOW}🔍 헬스체크 수행 중...${NC}"

    # 백엔드 헬스체크
    echo "백엔드 서비스 확인: $BACKEND_URL/health"

    MAX_ATTEMPTS=10
    ATTEMPT=1

    while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
        if curl -s -f "$BACKEND_URL/health" > /dev/null; then
            echo -e "${GREEN}✅ 백엔드 서비스 정상${NC}"
            break
        else
            # 첫 시도 실패 시에만 대기 메시지 표시
            if [ $ATTEMPT -eq 1 ]; then
                echo -e "${YELLOW}⏳ 백엔드 서비스 대기 중...${NC}"
            fi
            sleep 2
            ATTEMPT=$((ATTEMPT + 1))
        fi
    done

    if [ $ATTEMPT -gt $MAX_ATTEMPTS ]; then
        echo -e "${RED}❌ 백엔드 서비스 헬스체크 실패${NC}"
        return 1
    fi

    # 웹 대시보드 확인
    echo "웹 대시보드 확인: $WEB_URL"

    if curl -s -f "$WEB_URL" > /dev/null; then
        echo -e "${GREEN}✅ 웹 대시보드 정상${NC}"
    else
        echo -e "${RED}❌ 웹 대시보드 접근 실패${NC}"
        return 1
    fi
}

# 2. API 기능 테스트
api_test() {
    echo -e "${YELLOW}🔧 API 기능 테스트 중...${NC}"

    # 버전 정보 조회 테스트
    echo "버전 정보 API 테스트..."
    VERSION_RESPONSE=$(curl -s "$BACKEND_URL/api/version")

    if echo "$VERSION_RESPONSE" | grep -q '"version"'; then
        echo -e "${GREEN}✅ 버전 API 응답 형식 정상${NC}"
    else
        echo -e "${RED}❌ 버전 API 오류 또는 응답 없음${NC}"
        echo "응답: $VERSION_RESPONSE"
        return 1
    fi

    # 버전 업데이트 테스트
    echo "버전 업데이트 API 테스트..."
    TEST_VERSION="1.2.3-test"
    UPDATE_RESPONSE=$(curl -s -X POST "$BACKEND_URL/api/version/update" \
        -H "Content-Type: application/json" \
        -d "{\"version\": \"$TEST_VERSION\", \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}")

    if echo "$UPDATE_RESPONSE" | grep -q '"version"'; then
        echo -e "${GREEN}✅ 버전 업데이트 API 정상 작동${NC}"
    else
        echo -e "${RED}❌ 버전 업데이트 API 오류${NC}"
        return 1
    fi

    # 업데이트된 버전 정보 다시 확인
    echo "업데이트된 버전 정보 재확인..."
    sleep 1 # DB 반영 시간을 위해 잠시 대기
    VERSION_RESPONSE_AFTER_UPDATE=$(curl -s "$BACKEND_URL/api/version")
    UPDATED_VERSION=$(echo "$VERSION_RESPONSE_AFTER_UPDATE" | sed -n 's/.*"version":"\([^"]*\)".*/\1/p')

    if [ "$UPDATED_VERSION" == "$TEST_VERSION" ]; then
        echo -e "${GREEN}✅ 버전 정보가 성공적으로 업데이트되었습니다: $UPDATED_VERSION${NC}"
    else
        echo -e "${RED}❌ 버전 정보 업데이트 확인 실패${NC}"
        echo "기대값: $TEST_VERSION, 실제값: $UPDATED_VERSION"
        return 1
    fi

    # # 플랫폼별 업데이트 확인 테스트
    # echo "플랫폼별 업데이트 확인 테스트..."
    # CHECK_RESPONSE=$(curl -s "$BACKEND_URL/api/version/check/ios/1.0.0")
    #
    # if echo "$CHECK_RESPONSE" | jq -e '.needsUpdate' > /dev/null 2>&1; then
    #     echo -e "${GREEN}✅ 업데이트 확인 API 정상 작동${NC}"
    #     NEEDS_UPDATE=$(echo "$CHECK_RESPONSE" | jq -r '.needsUpdate')
    #     echo "업데이트 필요: $NEEDS_UPDATE"
    # else
    #     echo -e "${RED}❌ 업데이트 확인 API 오류${NC}"
    #     return 1
    # fi
}

# 3. 롤링 업데이트 테스트
rolling_update_test() {
    echo -e "${YELLOW}🔄 롤링 업데이트 테스트 중...${NC}"

    # 현재 레플리카 수 확인
    CURRENT_REPLICAS=$(kubectl get deployment nestjs-backend -n app-deployment -o jsonpath='{.spec.replicas}')
    echo "현재 백엔드 레플리카 수: $CURRENT_REPLICAS"

    # 이미지 업데이트 (태그 변경으로 시뮬레이션)
    NEW_TAG="test-$(date +%s)"
    echo "새 이미지 태그로 업데이트: $NEW_TAG"

    # 이미지 다시 태그하고 푸시
    eval $(minikube docker-env)
    docker tag localhost:5000/nestjs-backend:latest localhost:5000/nestjs-backend:$NEW_TAG
    docker push localhost:5000/nestjs-backend:$NEW_TAG

    # 배포 업데이트
    kubectl set image deployment/nestjs-backend -n app-deployment \
        nestjs-backend=localhost:5000/nestjs-backend:$NEW_TAG

    # 롤아웃 상태 확인
    echo "롤아웃 상태 확인 중..."
    kubectl rollout status deployment/nestjs-backend -n app-deployment --timeout=120s

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ 롤링 업데이트 성공${NC}"
    else
        echo -e "${RED}❌ 롤링 업데이트 실패${NC}"
        return 1
    fi

    # 서비스 가용성 확인
    sleep 5
    health_check
}

# 4. 로드 테스트
load_test() {
    echo -e "${YELLOW}⚡ 간단한 로드 테스트 수행 중...${NC}"

    # Apache Bench를 사용한 로드 테스트 (설치되어 있는 경우)
    if command -v ab >/dev/null 2>&1; then
        echo "Apache Bench로 로드 테스트 수행..."
        ab -n 100 -c 10 "$BACKEND_URL/api/version"
    else
        # curl을 사용한 간단한 반복 테스트
        echo "curl을 사용한 간단한 반복 테스트..."

        SUCCESS_COUNT=0
        TOTAL_REQUESTS=20

        for i in $(seq 1 $TOTAL_REQUESTS); do
            if curl -s -f "$BACKEND_URL/api/version" > /dev/null; then
                SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
            fi
            echo -n "."
        done
        echo

        SUCCESS_RATE=$((SUCCESS_COUNT * 100 / TOTAL_REQUESTS))
        echo "성공률: $SUCCESS_RATE% ($SUCCESS_COUNT/$TOTAL_REQUESTS)"

        if [ $SUCCESS_RATE -ge 90 ]; then
            echo -e "${GREEN}✅ 로드 테스트 통과 (성공률 90% 이상)${NC}"
        else
            echo -e "${RED}❌ 로드 테스트 실패 (성공률 90% 미만)${NC}"
            return 1
        fi
    fi
}

# 5. 리소스 사용량 확인
resource_check() {
    echo -e "${YELLOW}📊 리소스 사용량 확인 중...${NC}"

    echo "Pod 상태:"
    kubectl get pods -n app-deployment -o wide

    echo -e "\n메모리 및 CPU 사용량:"
    kubectl top pods -n app-deployment 2>/dev/null || echo "metrics-server가 준비되지 않았습니다."

    echo -e "\n노드 리소스 사용량:"
    kubectl top nodes 2>/dev/null || echo "metrics-server가 준비되지 않았습니다."

    echo -e "\nPod 이벤트 확인:"
    kubectl get events -n app-deployment --sort-by='.lastTimestamp' | tail -10
}

# 6. 네트워크 연결 테스트
network_test() {
    echo -e "${YELLOW}🌐 네트워크 연결 테스트 중...${NC}"

    # 서비스 간 통신 테스트
    echo "서비스 간 통신 테스트..."

    # 백엔드 Pod에서 다른 서비스로의 연결 테스트
    BACKEND_POD=$(kubectl get pods -n app-deployment -l app=nestjs-backend -o jsonpath='{.items[0].metadata.name}')

    if [ -n "$BACKEND_POD" ]; then
        echo "백엔드 Pod에서 DNS 해석 테스트..."
        kubectl exec -n app-deployment $BACKEND_POD -- nslookup web-dashboard-service.app-deployment.svc.cluster.local || echo "DNS 해석 실패"

        echo "백엔드 Pod에서 웹 서비스 연결 테스트..."
        kubectl exec -n app-deployment $BACKEND_POD -- wget -q -O- http://web-dashboard-service.app-deployment.svc.cluster.local:80 > /dev/null && echo "✅ 연결 성공" || echo "❌ 연결 실패"
    fi
}

# # 7. 시뮬레이션된 CI/CD 파이프라인 테스트
# simulate_cicd() {
#     echo -e "${YELLOW}🚀 CI/CD 파이프라인 시뮬레이션${NC}"
#
#     # 코드 변경 시뮬레이션 (새 버전 번호 생성)
#     NEW_VERSION="2.0.0-$(date +%s)"
#     echo "새 버전 시뮬레이션: $NEW_VERSION"
#
#     # 백엔드에 버전 업데이트
#     BACKEND_URL=$(minikube service nestjs-backend-service -n app-deployment --url)
#
#     curl -s -X POST "$BACKEND_URL/api/version/update" \
#         -H "Content-Type: application/json" \
#         -d "{\"version\": \"$NEW_VERSION\", \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" > /dev/null
#
#     echo "✅ 버전 업데이트 완료: $NEW_VERSION"
#
#     # 모바일 앱 업데이트 확인 시뮬레이션
#     echo "모바일 앱 업데이트 확인 시뮬레이션..."
#
#     IOS_CHECK=$(curl -s "$BACKEND_URL/api/version/check/ios/1.0.0")
#     ANDROID_CHECK=$(curl -s "$BACKEND_URL/api/version/check/android/1.0.0")
#
#     echo "iOS 업데이트 필요: $(echo "$IOS_CHECK" | jq -r '.needsUpdate')"
#     echo "Android 업데이트 필요: $(echo "$ANDROID_CHECK" | jq -r '.needsUpdate')"
#
#     echo -e "${GREEN}✅ CI/CD 파이프라인 시뮬레이션 완료${NC}"
# }

# 각 테스트를 실행하고 결과를 기록하는 헬퍼 함수
run_test() {
    echo -e "\n${BLUE}--- $1 시작 ---${NC}"
    "$2"
    if [ $? -ne 0 ]; then
        echo -e "${RED}--- $1 실패 ---${NC}"
        FAILED_TESTS+=("$1")
    else
        echo -e "${GREEN}--- $1 성공 ---${NC}"
    fi
}

# 메인 테스트 실행
main() {
    echo -e "${BLUE}📋 테스트 계획:${NC}"
    echo "1. 헬스체크"
    echo "2. API 기능 테스트"
    echo "3. 롤링 업데이트 테스트"
    echo "4. 로드 테스트"
    echo "5. 리소스 사용량 확인"
    echo "6. 네트워크 연결 테스트"
    # echo "7. CI/CD 파이프라인 시뮬레이션"
    echo

    # kubectl port-forward를 사용하여 서비스에 직접 연결
    BACKEND_LOCAL_PORT=8080
    WEB_LOCAL_PORT=8081

    echo -e "${YELLOW}🔄 백엔드 포트 포워딩 설정 중... (localhost:$BACKEND_LOCAL_PORT -> backend:3000)${NC}"
    kubectl port-forward -n app-deployment service/nestjs-backend-service $BACKEND_LOCAL_PORT:3000 &
    BACKEND_PID=$!

    echo -e "${YELLOW}🔄 웹 대시보드 포트 포워딩 설정 중... (localhost:$WEB_LOCAL_PORT -> web:80)${NC}"
    kubectl port-forward -n app-deployment service/web-dashboard-service $WEB_LOCAL_PORT:80 &
    WEB_PID=$!

    # 스크립트 종료 시 모든 포트 포워딩 프로세스를 자동으로 정리합니다.
    trap "echo -e '\n${YELLOW}🔪 포트 포워딩 프로세스 종료 중...${NC}'; kill $BACKEND_PID $WEB_PID 2>/dev/null" EXIT

    # 포트 포워드가 시작될 시간을 줍니다.
    sleep 3

    # 포트 포워딩이 정상적으로 시작되었는지 확인합니다.
    if ! kill -0 $BACKEND_PID 2>/dev/null || ! kill -0 $WEB_PID 2>/dev/null; then
        echo -e "${RED}❌ 포트 포워딩 시작에 실패했습니다. 다른 프로세스가 $BACKEND_LOCAL_PORT 또는 $WEB_LOCAL_PORT 포트를 사용 중인지 확인해주세요.${NC}"
        exit 1
    fi

    export BACKEND_URL="http://127.0.0.1:$BACKEND_LOCAL_PORT"
    export WEB_URL="http://127.0.0.1:$WEB_LOCAL_PORT"
    echo -e "${GREEN}✅ 백엔드 URL: $BACKEND_URL${NC}"
    echo -e "${GREEN}✅ 웹 대시보드 URL: $WEB_URL${NC}"

    FAILED_TESTS=()

    run_test "헬스체크" health_check
    run_test "API 기능 테스트" api_test
    run_test "롤링 업데이트 테스트" rolling_update_test
    run_test "로드 테스트" load_test
    run_test "리소스 사용량 확인" resource_check
    run_test "네트워크 연결 테스트" network_test
    # run_test "CI/CD 파이프라인 시뮬레이션" simulate_cicd

    echo

    if [ ${#FAILED_TESTS[@]} -ne 0 ]; then
        echo -e "${RED}❌ 다음 테스트 실패:${NC}"
        for test in "${FAILED_TESTS[@]}"; do
            echo -e "  - $test"
        done
        exit 1
    else
        echo -e "${GREEN}✅ 모든 테스트 통과!${NC}"
    fi
}

# 스크립트 실행
main "$@"
