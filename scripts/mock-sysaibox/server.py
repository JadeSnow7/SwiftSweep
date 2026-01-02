"""
Mock Sys AI Box Server for SwiftSweep Integration Testing
Run with: python3 server.py
"""

from flask import Flask, jsonify, request
from flask_cors import CORS
import uuid
import time

app = Flask(__name__)
CORS(app)

# Store device codes and their status
device_codes = {}

@app.route('/')
def index():
    return '''
    <html>
    <head><title>Sys AI Box Mock</title></head>
    <body style="font-family: -apple-system, sans-serif; padding: 40px; background: #1a1a2e; color: white;">
        <h1>🖥️ Sys AI Box Mock Server</h1>
        <p>This is a mock server for testing SwiftSweep integration.</p>
        <h2>Endpoints:</h2>
        <ul>
            <li><code>GET /api/v1/health</code> - Health check</li>
            <li><code>POST /api/v1/auth/device/start</code> - Start pairing</li>
            <li><code>GET /api/v1/auth/device/status</code> - Check status</li>
            <li><code>POST /api/v1/auth/device/token</code> - Get tokens</li>
        </ul>
        <h2>Active Device Codes:</h2>
        <div id="codes"></div>
        <script>
            setInterval(() => location.reload(), 5000);
        </script>
    </body>
    </html>
    '''

@app.route('/console')
def console():
    return '''
    <html>
    <head><title>Sys AI Box Console</title></head>
    <body style="font-family: -apple-system, sans-serif; padding: 40px; background: #0f0f23; color: white;">
        <h1>🎛️ Sys AI Box Console</h1>
        <p>Enter the code from SwiftSweep to authorize:</p>
        <form action="/approve" method="GET">
            <input name="code" placeholder="Enter code" style="padding: 10px; font-size: 18px;">
            <button type="submit" style="padding: 10px 20px; background: #0066ff; color: white; border: none; cursor: pointer;">
                Approve
            </button>
        </form>
    </body>
    </html>
    '''

@app.route('/approve')
def approve():
    code = request.args.get('code', '').upper()
    for device_code, data in device_codes.items():
        if data['user_code'] == code:
            device_codes[device_code]['status'] = 'authorized'
            return f'''
            <html>
            <body style="font-family: -apple-system, sans-serif; padding: 40px; background: #0f0f23; color: white;">
                <h1>✅ Device Authorized!</h1>
                <p>Code <code>{code}</code> has been approved.</p>
                <p>You can now return to SwiftSweep.</p>
            </body>
            </html>
            '''
    return f'''
    <html>
    <body style="font-family: -apple-system, sans-serif; padding: 40px; background: #0f0f23; color: white;">
        <h1>❌ Code Not Found</h1>
        <p>Code <code>{code}</code> was not found or has expired.</p>
        <a href="/console">Try again</a>
    </body>
    </html>
    '''

# API Endpoints

@app.route('/api/v1/health')
def health():
    return jsonify({
        "status": "healthy",
        "version": "1.0.0-mock"
    })

@app.route('/api/v1/version')
def version():
    return jsonify({
        "version": "1.0.0-mock",
        "build": "dev"
    })

@app.route('/api/v1/auth/device/start', methods=['POST'])
def device_start():
    device_code = str(uuid.uuid4())
    user_code = f"SWIFT-{uuid.uuid4().hex[:4].upper()}"
    
    device_codes[device_code] = {
        'user_code': user_code,
        'status': 'pending',
        'created': time.time(),
        'expires_in': 600
    }
    
    print(f"📱 New device pairing started: {user_code}")
    
    return jsonify({
        "device_code": device_code,
        "user_code": user_code,
        "verification_uri": "http://106.54.188.236:8080/console",
        "expires_in": 600,
        "interval": 5
    })

@app.route('/api/v1/auth/device/status')
def device_status():
    device_code = request.args.get('device_code')
    
    if device_code in device_codes:
        data = device_codes[device_code]
        # Check expiration
        if time.time() - data['created'] > data['expires_in']:
            return jsonify({"status": "expired"})
        return jsonify({"status": data['status']})
    
    return jsonify({"status": "pending"})

@app.route('/api/v1/auth/device/token', methods=['POST'])
def device_token():
    body = request.get_json() or {}
    device_code = body.get('device_code')
    
    if device_code in device_codes and device_codes[device_code]['status'] == 'authorized':
        # Generate tokens
        access_token = f"access_{uuid.uuid4().hex}"
        refresh_token = f"refresh_{uuid.uuid4().hex}"
        
        print(f"✅ Tokens issued for device: {device_codes[device_code]['user_code']}")
        
        return jsonify({
            "access_token": access_token,
            "refresh_token": refresh_token,
            "expires_in": 3600
        })
    
    return jsonify({"error": "not_authorized"}), 400

@app.route('/api/v1/auth/refresh', methods=['POST'])
def refresh():
    return jsonify({
        "access_token": f"access_{uuid.uuid4().hex}",
        "refresh_token": f"refresh_{uuid.uuid4().hex}",
        "expires_in": 3600
    })

@app.route('/api/v1/auth/revoke', methods=['POST'])
def revoke():
    return jsonify({"success": True})

if __name__ == '__main__':
    print("🚀 Mock Sys AI Box Server starting...")
    print("📍 URL: http://0.0.0.0:8080")
    print("📍 Console: http://106.54.188.236:8080/console")
    app.run(host='0.0.0.0', port=8080, debug=True)
