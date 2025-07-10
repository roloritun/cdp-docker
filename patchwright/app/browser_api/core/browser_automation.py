"""
Core browser automation functionality.
This module provides the main browser automation class that integrates all functionality.
"""
import asyncio
import logging
import os
import traceback
from typing import Dict, List, Tuple, Optional, Any

from fastapi import APIRouter, Body, HTTPException
from patchright.async_api import async_playwright, Browser, Page

from browser_api.models.dom_models import DOMState, DOMElementNode
from browser_api.models.result_models import BrowserActionResult

class BrowserAutomation:
    def __init__(self):
        self.router = APIRouter()
        self.browser: Browser = None
        self.pages: List[Page] = []
        self.current_page_index: int = 0
        self.current_frame = None
        self.logger = logging.getLogger("browser_automation")
        self.include_attributes = ["id", "href", "src", "alt", "aria-label", "placeholder", "name", "role", "title", "value"]
        self.screenshot_dir = os.path.join(os.getcwd(), "screenshots")
        os.makedirs(self.screenshot_dir, exist_ok=True)
        
        # Register routes
        self.router.on_startup.append(self.startup)
        self.router.on_shutdown.append(self.shutdown)
        
        # We'll register specific routes in main.py after importing all action modules
        
    async def startup(self):
        """Initialize the browser instance on startup"""
        try:
            print("🚀 Starting browser initialization...")
            
            # Wait for display to be ready
            print("⏳ Waiting for display server...")
            await self._wait_for_display()
            
            print("📺 Display server ready, starting Playwright...")
            
            # Set environment variables to suppress Google API key warnings
            os.environ['GOOGLE_API_KEY'] = 'not_needed'
            os.environ['GOOGLE_DEFAULT_CLIENT_ID'] = 'not_needed'
            os.environ['GOOGLE_DEFAULT_CLIENT_SECRET'] = 'not_needed'
            
            playwright = await async_playwright().start()
            print("✅ Patchright started, launching browser...")
            
            # Use non-headless mode for VNC visibility with slower timeouts
            cdp_port = os.getenv('CHROME_DEBUGGING_PORT', '9222')
            print(f"🔧 Configuring Chrome with CDP on port {cdp_port}")
            launch_options = {
                "headless": False,
                "timeout": 120000,  # Increase timeout to 2 minutes
                "args": [
                    "--no-sandbox",
                    "--disable-dev-shm-usage",
                    "--disable-gpu",
                    "--disable-web-security",
                    "--disable-features=VizDisplayCompositor",
                    f"--remote-debugging-port={cdp_port}",  # Enable CDP on port 9222
                    "--remote-debugging-address=0.0.0.0",  # Allow external connections
                    f"--display={os.getenv('DISPLAY', ':99')}",  # Use environment variable for display
                    "--disable-infobars",  # Suppress info bars including sandbox warning
                    "--disable-logging",  # Suppress logging messages
                    "--silent",  # Suppress warnings
                    "--no-default-browser-check",  # Suppress default browser check
                    "--disable-default-apps",  # Prevent default app warnings
                    "--disable-background-timer-throttling",  # Performance flags
                    "--disable-renderer-backgrounding",
                    "--disable-backgrounding-occluded-windows",
                    "--disable-ipc-flooding-protection"
                ]
            }
            
            try:
                self.browser = await playwright.chromium.launch(**launch_options)
                print("✅ Browser launched successfully")
                print(f"🌐 CDP should be available at: http://localhost:{cdp_port}")
            except Exception as browser_error:
                print(f"❌ Failed to launch browser: {browser_error}")
                # Try with minimal options (headless fallback)
                print("🔄 Retrying with headless mode...")
                launch_options = {
                    "headless": True,
                    "timeout": 90000,
                    "args": [
                        "--no-sandbox", 
                        "--disable-dev-shm-usage",
                        f"--remote-debugging-port={cdp_port}",  # Still enable CDP in headless mode
                        "--remote-debugging-address=0.0.0.0",
                        "--disable-infobars",  # Suppress info bars including sandbox warning
                        "--disable-logging",  # Suppress logging messages
                        "--silent",  # Suppress warnings
                        "--no-default-browser-check",  # Suppress default browser check
                        "--disable-default-apps"  # Prevent default app warnings
                    ]
                }
                self.browser = await playwright.chromium.launch(**launch_options)
                print("✅ Browser launched in headless mode")

            try:
                # Check if browser already has pages
                existing_pages = self.browser.contexts[0].pages if self.browser.contexts else []
                if existing_pages:
                    self.pages = existing_pages
                    self.current_page_index = 0
                    print(f"✅ Found {len(existing_pages)} existing page(s)")
                else:
                    raise Exception("No existing pages found")
            except Exception as page_error:
                print(f"📄 Creating new page... ({page_error})")
                context = await self.browser.new_context()
                page = await context.new_page()
                self.pages.append(page)
                self.current_page_index = 0
                print("✅ New page created successfully")
                
            print("🎉 Browser initialization completed successfully")
                
        except Exception as e:
            print(f"❌ Browser startup error: {str(e)}")
            traceback.print_exc()
            # Don't raise here - let the service start without browser for debugging
            print("⚠️ Browser failed to start, but API will still be available for debugging")
            
    async def _wait_for_display(self, max_attempts=30):
        """Wait for the display server to be ready"""
        import subprocess
        
        display = os.getenv('DISPLAY', ':99')
        for attempt in range(max_attempts):
            try:
                # Check if display is available
                result = subprocess.run(['xdpyinfo', '-display', display], 
                                      capture_output=True, timeout=5)
                if result.returncode == 0:
                    print(f"✅ Display {display} is ready")
                    return
            except (subprocess.TimeoutExpired, subprocess.CalledProcessError, FileNotFoundError):
                pass
            
            if attempt < max_attempts - 1:
                print(f"⏳ Display {display} not ready, waiting... (attempt {attempt + 1}/{max_attempts})")
                await asyncio.sleep(2)
        
        print(f"⚠️ Display {display} may not be ready, proceeding anyway...")
            
    async def shutdown(self):
        """Clean up browser instance on shutdown"""
        if self.browser:
            await self.browser.close()

    async def get_current_page(self) -> Page:
        """Get the current active page"""
        if not self.pages:
            raise HTTPException(status_code=500, detail="No browser pages available")
        return self.pages[self.current_page_index]
        
    async def get_current_context(self):
        """Get the current context (page or frame) for interactions"""
        if self.current_frame:
            return self.current_frame
        return await self.get_current_page()

    async def get_updated_browser_state(self, action_name: str = "action") -> Tuple[DOMState, str, str, Dict[str, Any]]:
        """Get updated browser state after an action
        
        Returns:
            Tuple containing:
            - DOM state
            - Screenshot base64
            - Formatted elements string
            - Metadata dictionary
        """
        # This method should be implemented in dom_handler.py
        # For now, we'll provide a placeholder implementation
        return None, "", "", {}
        
    def build_action_result(self, success: bool, message: str, dom_state: Optional[DOMState],
                        screenshot_base64: str, elements: str, metadata: Dict[str, Any],
                        error: str = "", content: Any = None) -> BrowserActionResult:
        """Build a standardized action result
        
        Args:
            success: Whether the action was successful
            message: Message describing the result
            dom_state: Current DOM state
            screenshot_base64: Base64 encoded screenshot
            elements: Formatted string of interactive elements
            metadata: Additional metadata
            error: Error message if any
            content: Additional content to return
            
        Returns:
            BrowserActionResult object
        """
        # This should also be implemented in a separate module
        # For now, we'll provide a placeholder implementation
        result = BrowserActionResult(
            success=success,
            message=message,
            error=error,
            content=content
        )
        
        if dom_state:
            result.url = dom_state.url
            result.title = dom_state.title
            result.elements = elements
            result.screenshot_base64 = screenshot_base64
            result.pixels_above = dom_state.pixels_above
            result.pixels_below = dom_state.pixels_below
            
            # Add metadata
            if metadata:
                result.element_count = metadata.get("element_count", 0)
                result.interactive_elements = metadata.get("interactive_elements", [])
                result.viewport_width = metadata.get("viewport_width")
                result.viewport_height = metadata.get("viewport_height")
                
        return result
