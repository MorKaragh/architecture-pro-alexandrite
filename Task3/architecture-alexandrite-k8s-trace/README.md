# Jaeger в Minikube с сервисами

## Описание
Развертывание Jaeger в Minikube с двумя сервисами, которые:
1. Взаимодействуют между собой
2. Отправляют трейсы в Jaeger

## Требования
- Minikube
- kubectl
- Docker

## Быстрый старт (автоматический)

Для автоматического развертывания всего и генерации трейсов используйте скрипт:

```bash
./deploy.sh
```

Скрипт автоматически:
1. Проверит и запустит Minikube (если нужно)
2. Установит Jaeger Operator
3. Развернет Jaeger
4. Соберет Docker образы сервисов
5. Развернет сервисы
6. Сгенерирует 10 трейсов

## Ручная установка

### 1. Запуск Minikube 
```bash
minikube start --addons=ingress 
```
Ingress нужен для вызовов

### 2. Установка cert-manager (опционально, если нужен)
```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.3/cert-manager.yaml
```

### 3. Развертывание Jaeger
```bash
kubectl create namespace observability
kubectl create -f https://github.com/jaegertracing/jaeger-operator/releases/download/v1.51.0/jaeger-operator.yaml -n observability
kubectl apply -f k8s/jaeger-instance.yaml
```

### 4. Сборка и деплой сервисов
```bash
# Настройка Docker для Minikube
eval $(minikube docker-env)

# Сборка образов
minikube image build -t service-a:latest services/service-a/
minikube image build -t service-b:latest services/service-b/

# Развертывание
kubectl apply -f k8s/services.yaml
```

## Генерация трейсов

После развертывания для генерации дополнительных трейсов используйте:

```bash
./generate-traces.sh [количество]
```

По умолчанию генерируется 20 трейсов. Можно указать другое количество:
```bash
./generate-traces.sh 50  # сгенерирует 50 трейсов
```

## Проверка работы

### Доступ к Jaeger UI
```bash
kubectl port-forward svc/simplest-query 16686:16686 -n default
```
Откройте в браузере: http://localhost:16686

В Jaeger UI:
1. Выберите сервис `service-a` в выпадающем списке
2. Нажмите "Find Traces"
3. Вы увидите все трейсы, включая вызовы service-b

### Тестирование сервисов
```bash
# Вызов service-a, который вызывает service-b
SERVICE_A_POD=$(kubectl get pods -l app=service-a -o jsonpath='{.items[0].metadata.name}')
kubectl exec $SERVICE_A_POD -- python -c "import urllib.request; print(urllib.request.urlopen('http://service-a:8080').read().decode())"
```

### Просмотр логов
```bash
# Логи service-a
kubectl logs -l app=service-a -f

# Логи service-b
kubectl logs -l app=service-b -f
```

## Структура проекта
- `services/service-a/` - Исходный код service-a (Python + Flask + OpenTelemetry)
- `services/service-b/` - Исходный код service-b (Python + Flask + OpenTelemetry)
- `k8s/services.yaml` - Конфигурация Kubernetes для сервисов
- `k8s/jaeger-instance.yaml` - Конфигурация Jaeger
- `deploy.sh` - Скрипт автоматического развертывания
- `generate-traces.sh` - Скрипт генерации трейсов

## Как работает трейсинг

1. **Service-A** получает HTTP запрос → FlaskInstrumentor создает span
2. **Service-A** вызывает **Service-B** через HTTP → RequestsInstrumentor передает trace context в заголовках и создает span
3. **Service-B** получает запрос → FlaskInstrumentor извлекает trace context и создает дочерний span
4. Оба сервиса отправляют трейсы в Jaeger через UDP (порт 6831)
5. Весь вызов попадает в один трейс с несколькими span'ами

## Очистка

Для удаления всех развернутых ресурсов:

```bash
kubectl delete -f k8s/services.yaml
kubectl delete -f k8s/jaeger-instance.yaml
kubectl delete namespace observability
```