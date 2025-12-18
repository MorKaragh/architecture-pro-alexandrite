#!/bin/bash

set -e

# Цвета для вывода
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo "=========================================="
echo "Генерация трейсов"
echo "=========================================="

# Количество запросов (можно передать как аргумент)
NUM_REQUESTS=${1:-20}

# Получение pod service-a
SERVICE_A_POD=$(kubectl get pods -l app=service-a -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -z "$SERVICE_A_POD" ]; then
    echo -e "${RED}Ошибка: не найден pod service-a${NC}"
    echo "Убедитесь, что сервисы развернуты: kubectl get pods -l app=service-a"
    exit 1
fi

echo -e "${GREEN}Найден pod: $SERVICE_A_POD${NC}"
echo -e "${YELLOW}Выполнение $NUM_REQUESTS запросов...${NC}\n"

# Генерация трейсов
SUCCESS=0
FAILED=0

for i in $(seq 1 $NUM_REQUESTS); do
    if kubectl exec $SERVICE_A_POD -- python -c "import urllib.request; urllib.request.urlopen('http://service-a:8080').read()" > /dev/null 2>&1; then
        SUCCESS=$((SUCCESS + 1))
        echo -n "."
    else
        FAILED=$((FAILED + 1))
        echo -n "E"
    fi
    
    # Небольшая задержка между запросами
    sleep 0.5
done

echo -e "\n\n${GREEN}Готово!${NC}"
echo "Успешных запросов: $SUCCESS"
if [ $FAILED -gt 0 ]; then
    echo -e "${YELLOW}Неудачных запросов: $FAILED${NC}"
fi

echo -e "\n${YELLOW}Трейсы отправлены в Jaeger.${NC}"
echo "Для просмотра откройте Jaeger UI:"
echo "kubectl port-forward svc/simplest-query 16686:16686 -n observability"
echo "Затем откройте http://localhost:16686"

