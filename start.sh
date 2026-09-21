#!/bin/bash
# Start backend + tunnel, restart on crash
while true; do
  # Check backend
  if ! curl -s http://localhost:8080/health > /dev/null 2>&1; then
    cd ~/WarpVPN/backend && source venv/bin/activate
    python -m uvicorn main:app --host 0.0.0.0 --port 8080 &
    sleep 3
  fi
  
  # Start tunnel (dies every ~10 min on quick tunnel, so restart)
  /tmp/cloudflared tunnel --url http://localhost:8080 --protocol http2 2>&1 | grep --line-buffered 'trycloudflare.com' &
  CF_PID=$!
  wait $CF_PID 2>/dev/null
  sleep 5
done
