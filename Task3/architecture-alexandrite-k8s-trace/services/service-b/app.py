#!/usr/bin/env python3
"""
Service B - простой сервис, который возвращает ответ и отправляет трейсы в Jaeger
"""
import os
from flask import Flask, jsonify
from opentelemetry import trace
from opentelemetry.exporter.jaeger.thrift import JaegerExporter
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.sdk.resources import Resource
from opentelemetry.instrumentation.flask import FlaskInstrumentor

# Настройка OpenTelemetry
resource = Resource.create({"service.name": "service-b"})
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

# Инструментируем Flask
FlaskInstrumentor().instrument_app(app)

tracer = trace.get_tracer(__name__)


@app.route("/", methods=["GET"])
def index():
    """Главный endpoint service-b"""
    with tracer.start_as_current_span("service-b-handler") as span:
        span.set_attribute("http.method", "GET")
        span.set_attribute("http.route", "/")
        span.set_attribute("http.status_code", 200)
        
        return jsonify({
            "service": "service-b",
            "status": "success",
            "message": "Hello from service-b!"
        }), 200


@app.route("/health", methods=["GET"])
def health():
    """Health check endpoint"""
    return jsonify({"status": "healthy", "service": "service-b"}), 200


if __name__ == "__main__":
    port = int(os.getenv("PORT", "8080"))
    app.run(host="0.0.0.0", port=port, debug=False)

