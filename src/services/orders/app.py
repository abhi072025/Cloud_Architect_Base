import os
import json
import pyodbc
from flask import Flask, jsonify, request

app = Flask(__name__)

SQL_SERVER = os.getenv("SQL_SERVER")
SQL_DB = os.getenv("SQL_DB", "ordersdb")
SQL_USER = os.getenv("SQL_USER", "sqladminuser")
SQL_PASSWORD = os.getenv("SQL_PASSWORD")
SQL_DRIVER = "{ODBC Driver 18 for SQL Server}"

def get_conn():
    conn_str = f"DRIVER={SQL_DRIVER};SERVER={SQL_SERVER};DATABASE={SQL_DB};UID={SQL_USER};PWD={SQL_PASSWORD};Encrypt=yes;TrustServerCertificate=no;Connection Timeout=30;"
    return pyodbc.connect(conn_str)

@app.route("/healthz")
def health():
    return jsonify({"status": "ok"}), 200

@app.route("/orders", methods=["GET"])
def list_orders():
    conn = get_conn()
    cur = conn.cursor()
    cur.execute("IF OBJECT_ID('dbo.orders', 'U') IS NULL CREATE TABLE dbo.orders (id INT IDENTITY(1,1) PRIMARY KEY, item NVARCHAR(100), qty INT);")
    cur.execute("SELECT TOP 50 id, item, qty FROM dbo.orders ORDER BY id DESC;")
    rows = cur.fetchall()
    conn.close()
    return jsonify([{"id": r[0], "item": r[1], "qty": r[2]} for r in rows]), 200

@app.route("/orders", methods=["POST"])
def create_order():
    payload = request.get_json(force=True)
    item = payload.get("item")
    qty = int(payload.get("qty", 1))
    conn = get_conn()
    cur = conn.cursor()
    cur.execute("INSERT INTO dbo.orders (item, qty) VALUES (?, ?);", (item, qty))
    conn.commit()
    conn.close()
    return jsonify({"status": "created"}), 201

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)

