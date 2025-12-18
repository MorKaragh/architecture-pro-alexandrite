#!/usr/bin/env python3
"""
Service A - вызывает Service B и отправляет трейсы в Jaeger
"""
import os
import requests
from flask import Flask, jsonify
from opentelemetry import trace
from opentelemetry.exporter.jaeger.thrift import JaegerExporter
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.sdk.resources import Resource
from opentelemetry.instrumentation.flask import FlaskInstrumentor
from opentelemetry.instrumentation.requests import RequestsInstrumentor

# Настройка OpenTelemetry
resource = Resource.create({"service.name": "service-a"})
trace.set_tracer_provider(TracerProvider(resource=resource))

# Jaeger exporter
jaeger_exporter = JaegerExporter(
    agent_host_name=os.getenv("JAEGER_AGENT_HOST", "simplest-agent"),
    agent_port=int(os.getenv("JAEGER_AGENT_PORT", "6831")),
)

# Добавляем span processor
span_processor = BatchSpanProcessor(jaeger_exporter)
trace.get_tracer_provider().add_span_processor(span_processor)

# Создаем Flask приложение
app = Flask(__name__)

# Инструментируем Flask и requests
FlaskInstrumentor().instrument_app(app)
RequestsInstrumentor().instrument()

tracer = trace.get_tracer(__name__)

# URL service-b
SERVICE_B_URL = os.getenv("SERVICE_B_URL", "http://service-b:8080")


@app.route("/", methods=["GET"])
def index():
    """Главный endpoint service-a, который вызывает service-b"""
    # FlaskInstrumentor автоматически создаст span для этого запроса
    # RequestsInstrumentor автоматически передаст trace context в HTTP заголовках
    
    try:
        # Вызываем service-b - trace context будет автоматически передан
        # RequestsInstrumentor создаст span для этого HTTP запроса
        response = requests.get(SERVICE_B_URL, timeout=5)
        
        if response.status_code == 200:
            result = response.json()
            return jsonify({
                "service": "service-a",
                "status": "success",
                "service_b_response": result
            }), 200
        else:
            return jsonify({
                "service": "service-a",
                "status": "error",
                "error": f"Service B returned {response.status_code}"
            }), response.status_code
            
    except Exception as e:
        return jsonify({
            "service": "service-a",
            "status": "error",
            "error": str(e)
        }), 500


@app.route("/health", methods=["GET"])
def health():
    """Health check endpoint"""
    return jsonify({"status": "healthy", "service": "service-a"}), 200


if __name__ == "__main__":
    port = int(os.getenv("PORT", "8080"))
    app.run(host="0.0.0.0", port=port, debug=False)

