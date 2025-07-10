#!/usr/bin/env python3
"""
Simple API server for Patchright browser automation
Provides endpoints for browser-use and other automation libraries
"""

import os
from typing import Dict
from fastapi import FastAPI, HTTPException
try:
    from patchright.async_api import async_playwright
except ImportError:
    from playwright.async_api import async_playwright
import uvicorn

app = FastAPI(title="Patchright CDP API", version="1.0.0")

# Global browser instance
browser = None
page = None

@app.on_startup
async def startup_event():
    """Initialize browser on startup"""
    global browser, page
    try:
        playwright = await async_playwright().start()
        browser = await playwright.chromium.connect_over_cdp("http://localhost:9222")
        print("Connected to Patchright browser via CDP")
    except Exception as e:
        print(f"Failed to connect to browser: {e}")

@app.on_shutdown
async def shutdown_event():
    """Cleanup browser on shutdown"""
    global browser
    if browser:
        await browser.close()

@app.get("/")
async def root():
    """Health check endpoint"""
    return {"status": "ok", "service": "Patchright CDP API"}

@app.get("/browser/status")
async def browser_status():
    """Check browser status"""
    global browser
    if not browser:
        raise HTTPException(status_code=503, detail="Browser not connected")
    
    try:
        contexts = browser.contexts
        return {
            "connected": True,
            "contexts": len(contexts),
            "cdp_endpoint": "http://localhost:9222"
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/browser/new_page")
async def new_page():
    """Create a new page"""
    global browser, page
    if not browser:
        raise HTTPException(status_code=503, detail="Browser not connected")
    
    try:
        context = await browser.new_context()
        page = await context.new_page()
        return {"page_id": id(page), "url": page.url}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/browser/navigate")
async def navigate(data: Dict[str, str]):
    """Navigate to URL"""
    global page
    if not page:
        raise HTTPException(status_code=400, detail="No page available")
    
    url = data.get("url")
    if not url:
        raise HTTPException(status_code=400, detail="URL required")
    
    try:
        await page.goto(url)
        return {"success": True, "url": page.url}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/cdp/info")
async def cdp_info():
    """Get CDP connection info"""
    return {
        "cdp_endpoint": "http://localhost:9222",
        "websocket_debugger_url": "ws://localhost:9222/devtools/browser",
        "version_info_url": "http://localhost:9222/json/version"
    }

if __name__ == "__main__":
    port = int(os.getenv("API_PORT", 8000))
    uvicorn.run(app, host="0.0.0.0", port=port)
