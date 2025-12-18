#!/bin/bash

set -e

echo "=========================================="
echo "Развертывание сервисов с трейсингом"
echo "=========================================="

# Цвета для вывода
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Функция для проверки команды
check_command() {
    if ! command -v $1 &> /dev/null; then
        echo -e "${RED}Ошибка: $1 не установлен${NC}"
        exit 1
    fi
}

# Проверка необходимых команд
echo "Проверка необходимых команд..."
check_command kubectl
check_command minikube
check_command docker

# Проверка статуса minikube
echo -e "\n${YELLOW}Проверка статуса Minikube...${NC}"
if ! minikube status &> /dev/null; then
    echo "Запуск Minikube..."
    minikube start --addons=ingress
else
    echo -e "${GREEN}Minikube уже запущен${NC}"
fi

# Настройка Docker для minikube
echo -e "\n${YELLOW}Настройка Docker для Minikube...${NC}"
eval $(minikube docker-env)

# Создание namespace для observability
echo -e "\n${YELLOW}Создание namespace observability...${NC}"
kubectl create namespace observability --dry-run=client -o yaml | kubectl apply -f -

# Установка cert-manager (нужен для webhook сертификатов)
echo -e "\n${YELLOW}Проверка cert-manager...${NC}"
if ! kubectl get deployment cert-manager -n cert-manager &> /dev/null; then
    echo "Установка cert-manager..."
    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.3/cert-manager.yaml
    
    echo "Ожидание готовности cert-manager..."
    kubectl wait --for=condition=available --timeout=180s deployment/cert-manager -n cert-manager 2>/dev/null || true
    kubectl wait --for=condition=available --timeout=180s deployment/cert-manager-webhook -n cert-manager 2>/dev/null || true
    sleep 10  # Дополнительное время для инициализации
else
    echo -e "${GREEN}cert-manager уже установлен${NC}"
fi

# Установка Jaeger Operator
echo -e "\n${YELLOW}Проверка Jaeger Operator...${NC}"
if ! kubectl get deployment jaeger-operator -n observability &> /dev/null; then
    echo "Установка Jaeger Operator..."
    kubectl create -f https://github.com/jaegertracing/jaeger-operator/releases/download/v1.51.0/jaeger-operator.yaml -n observability
else
    echo -e "${GREEN}Jaeger Operator найден${NC}"
fi

# Ожидание готовности Jaeger Operator (включая webhook)
echo "Ожидание готовности Jaeger Operator и webhook..."
kubectl wait --for=condition=available --timeout=300s deployment/jaeger-operator -n observability 2>/dev/null || true

# Дополнительное ожидание для webhook
echo "Ожидание готовности webhook..."
timeout=120
elapsed=0
while [ $elapsed -lt $timeout ]; do
    if kubectl get pods -n observability -l name=jaeger-operator -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q Running; then
        # Проверяем, что webhook доступен
        if kubectl get validatingwebhookconfiguration jaeger-operator-validating-webhook &> /dev/null; then
            echo -e "${GREEN}Jaeger Operator и webhook готовы${NC}"
            break
        fi
    fi
    echo "Ожидание webhook... ($elapsed/$timeout сек)"
    sleep 3
    elapsed=$((elapsed + 3))
done

if [ $elapsed -ge $timeout ]; then
    echo -e "${YELLOW}Предупреждение: таймаут ожидания webhook, продолжаем...${NC}"
fi

# Развертывание Jaeger
echo -e "\n${YELLOW}Развертывание Jaeger...${NC}"
kubectl apply -f k8s/jaeger-instance.yaml

echo "Ожидание готовности Jaeger..."
timeout=120
elapsed=0
while [ $elapsed -lt $timeout ]; do
    # Jaeger создается в default namespace
    if kubectl get pod -l app.kubernetes.io/instance=simplest -n default -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q Running; then
        echo -e "${GREEN}Jaeger готов${NC}"
        break
    fi
    echo "Ожидание... ($elapsed/$timeout сек)"
    sleep 5
    elapsed=$((elapsed + 5))
done

# Сборка Docker образов
echo -e "\n${YELLOW}Сборка Docker образов...${NC}"
echo "Сборка service-a..."
minikube image build -t service-a:latest services/service-a/

echo "Сборка service-b..."
minikube image build -t service-b:latest services/service-b/

# Развертывание сервисов
echo -e "\n${YELLOW}Развертывание сервисов...${NC}"
kubectl apply -f k8s/services.yaml

# Ожидание готовности подов
echo -e "\n${YELLOW}Ожидание готовности подов...${NC}"
kubectl wait --for=condition=ready pod -l app=service-a --timeout=120s
kubectl wait --for=condition=ready pod -l app=service-b --timeout=120s

echo -e "${GREEN}Сервисы готовы${NC}"

# Небольшая пауза для инициализации
echo -e "\n${YELLOW}Ожидание инициализации сервисов...${NC}"
sleep 5

# Генерация трейсов
echo -e "\n${YELLOW}Генерация трейсов...${NC}"

SERVICE_A_POD=$(kubectl get pods -l app=service-a -o jsonpath='{.items[0].metadata.name}')

if [ -z "$SERVICE_A_POD" ]; then
    echo -e "${RED}Ошибка: не найден pod service-a${NC}"
    exit 1
fi

echo "Выполнение запросов к service-a (который вызывает service-b)..."
SUCCESS=0
for i in {1..10}; do
    if kubectl exec $SERVICE_A_POD -- python -c "import urllib.request; urllib.request.urlopen('http://service-a:8080').read()" > /dev/null 2>&1; then
        SUCCESS=$((SUCCESS + 1))
        echo -n "."
    else
        echo -n "E"
    fi
    sleep 0.5
done
echo ""
echo -e "${GREEN}Выполнено запросов: $SUCCESS/10${NC}"

echo -e "\n${GREEN}Трейсы сгенерированы!${NC}"

# Информация о доступе
echo -e "\n=========================================="
echo -e "${GREEN}Развертывание завершено!${NC}"
echo -e "=========================================="
echo -e "\n${YELLOW}Для доступа к Jaeger UI выполните:${NC}"
echo "kubectl port-forward svc/simplest-query 16686:16686 -n default"
echo -e "\nЗатем откройте в браузере:"
echo -e "${GREEN}http://localhost:16686${NC}"
echo -e "\n${YELLOW}Для проверки работы сервисов:${NC}"
echo "kubectl exec $SERVICE_A_POD -- python -c \"import urllib.request; print(urllib.request.urlopen('http://service-a:8080').read().decode())\""
echo -e "\n${YELLOW}Для просмотра логов:${NC}"
echo "kubectl logs -l app=service-a"
echo "kubectl logs -l app=service-b"

