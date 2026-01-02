# Mock Sys AI Box Server

This is a mock server for testing SwiftSweep's Sys AI Box integration.

## Quick Start

```bash
# Install dependencies
pip3 install -r requirements.txt

# Run server
python3 server.py
```

## Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/` | GET | Server info page |
| `/console` | GET | Web console for approving codes |
| `/api/v1/health` | GET | Health check |
| `/api/v1/auth/device/start` | POST | Start device pairing |
| `/api/v1/auth/device/status` | GET | Check pairing status |
| `/api/v1/auth/device/token` | POST | Exchange code for tokens |

## Testing Flow

1. Start the server
2. In SwiftSweep, go to Settings → Plugins → Sys AI Box
3. Enter URL: `http://your-server:8080`
4. Click "Test" to verify connection
5. Click "Pair Device" to start pairing
6. Open `http://your-server:8080/console` in browser
7. Enter the code shown in SwiftSweep
8. Click "Approve"
9. SwiftSweep should show "Paired" status
