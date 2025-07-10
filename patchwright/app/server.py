#!/usr/bin/env python3
"""
FastAPI server for Patchright browser automation
Provides REST API endpoints for browser-use and other automation libraries
"""

import os
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse
import uvicorn
import logging

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(
    title="Patchright CDP API",
    description="Browser automation API using Patchright with CDP",
    version="1.0.0"
)

# Configuration
CDP_URL = f"http://localhost:{os.getenv('CDP_PORT', '9222')}"
API_PORT = int(os.getenv('CDP_API_PORT', '8080'))

@app.get("/")
async def root():
    """Health check endpoint"""
    return {
        "status": "running",
        "service": "Patchright CDP API",
        "cdp_url": CDP_URL,
        "version": "1.0.0"
    }

@app.get("/health")
async def health_check():
    """Detailed health check"""
    try:
        import httpx
        # Test CDP connection
        async with httpx.AsyncClient() as client:
            response = await client.get(f"{CDP_URL}/json/version")
            cdp_info = response.json()
        
        return {
            "status": "healthy",
            "cdp_connected": True,
            "cdp_info": cdp_info,
            "api_port": API_PORT
        }
    except Exception as e:
        return {
            "status": "unhealthy",
            "cdp_connected": False,
            "error": str(e),
            "api_port": API_PORT
        }

@app.get("/cdp/info")
async def get_cdp_info():
    """Get CDP connection information"""
    try:
        import httpx
        async with httpx.AsyncClient() as client:
            # Get version info
            version_response = await client.get(f"{CDP_URL}/json/version")
            version_info = version_response.json()
            
            # Get available tabs/pages
            tabs_response = await client.get(f"{CDP_URL}/json")
            tabs_info = tabs_response.json()
            
        return {
            "cdp_url": CDP_URL,
            "version": version_info,
            "tabs": tabs_info
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to get CDP info: {str(e)}")

@app.post("/cdp/new_tab")
async def create_new_tab():
    """Create a new browser tab"""
    try:
        import httpx
        async with httpx.AsyncClient() as client:
            response = await client.put(f"{CDP_URL}/json/new")
            tab_info = response.json()
        
        return {
            "status": "success",
            "tab": tab_info
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to create new tab: {str(e)}")

@app.delete("/cdp/close_tab/{tab_id}")
async def close_tab(tab_id: str):
    """Close a browser tab"""
    try:
        import httpx
        async with httpx.AsyncClient() as client:
            await client.delete(f"{CDP_URL}/json/close/{tab_id}")
        
        return {
            "status": "success",
            "message": f"Tab {tab_id} closed"
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to close tab: {str(e)}")

@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    """Global exception handler"""
    logger.error(f"Global exception: {exc}")
    return JSONResponse(
        status_code=500,
        content={"detail": f"Internal server error: {str(exc)}"}
    )

if __name__ == "__main__":
    uvicorn.run(
        "server:app",
        host="0.0.0.0",
        port=API_PORT,
        log_level="info",
        reload=False
    )
