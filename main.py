from fastapi import FastAPI
import socket
import datetime
import psycopg2

app = FastAPI()

DB_CONFIG = {
    "host": "10.10.20.31",
    "database": "labapp",
    "user": "labuser",
    "password": "ariel"
}

@app.get("/health")
def health():
    return {
        "status": "healthy",
        "hostname": socket.gethostname(),
        "version": "1.0.0",
        "timestamp": datetime.datetime.utcnow().isoformat()
    }

@app.get("/api/status")
def status():
    return {"service": "app-01", "status": "running"}

@app.get("/api/users")
def users():
    return {"users": ["alice", "bob", "charlie"]}

@app.get("/api/metrics")
def metrics():
    return {"requests_total": 0, "uptime_seconds": 0}

@app.get("/api/db-check")
def db_check():
    try:
        conn = psycopg2.connect(**DB_CONFIG)
        cur = conn.cursor()
        cur.execute("SELECT version();")
        version = cur.fetchone()
        cur.close()
        conn.close()
        return {"database": "connected", "postgres_version": version[0]}
    except Exception as e:
        return {"database": "error", "detail": str(e)}
