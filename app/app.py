"""
Demo K8s API - Lightweight Flask API for Kubernetes deployment lifecycle demonstration.
Supports health/readiness probes and configurable failure simulation.
"""
from flask import Flask, jsonify
import os

app = Flask(__name__)

APP_VERSION = os.getenv("APP_VERSION", "1.0")
SIMULATE_FAILURE = os.getenv("SIMULATE_FAILURE", "false").lower() == "true"


@app.route("/")
def home():
    return jsonify({"message": "Demo K8s API Running", "version": APP_VERSION})


@app.route("/health")
def health():
    """Liveness probe — returns 200 if process is alive."""
    if SIMULATE_FAILURE:
        return jsonify({"status": "unhealthy", "version": APP_VERSION}), 500
    return jsonify({"status": "healthy", "version": APP_VERSION})


@app.route("/ready")
def ready():
    """Readiness probe — returns 200 if ready to serve traffic."""
    if SIMULATE_FAILURE:
        return jsonify({"ready": False, "version": APP_VERSION}), 503
    return jsonify({"ready": True, "version": APP_VERSION})


@app.route("/version")
def version():
    return jsonify({"version": APP_VERSION})


if __name__ == "__main__":
    port = int(os.getenv("PORT", 5000))
    app.run(host="0.0.0.0", port=port)