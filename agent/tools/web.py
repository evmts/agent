"""
Web search and fetch tools.
"""
import re

import httpx


async def web_search(query: str, max_results: int = 5) -> str:
    """
    Search the web for information.

    Args:
        query: Search query
        max_results: Maximum number of results to return

    Returns:
        Search results with titles, URLs, and snippets

    Note:
        This is a placeholder. In production, integrate with:
        - Tavily API
        - SerpAPI
        - Brave Search API
        - Or another search provider
    """
    # Placeholder implementation
    # In production, replace with actual search API integration
    return f"""Web search placeholder for: "{query}"

To enable real web search, integrate one of:
- Tavily API (recommended for AI agents)
- SerpAPI
- Brave Search API

Set the appropriate API key in environment variables."""


async def web_fetch(url: str, extract_text: bool = True) -> str:
    """
    Fetch content from a URL.

    Args:
        url: URL to fetch
        extract_text: If True, extract text content; otherwise return raw HTML

    Returns:
        Page content or error message
    """
    try:
        async with httpx.AsyncClient(
            timeout=30.0,
            follow_redirects=True,
        ) as client:
            response = await client.get(url)
            response.raise_for_status()

            content_type = response.headers.get("content-type", "")

            if "text/html" in content_type and extract_text:
                # Basic text extraction
                html = response.text
                # Remove script and style tags
                html = re.sub(r"<script[^>]*>.*?</script>", "", html, flags=re.DOTALL)
                html = re.sub(r"<style[^>]*>.*?</style>", "", html, flags=re.DOTALL)
                # Remove HTML tags
                text = re.sub(r"<[^>]+>", " ", html)
                # Clean up whitespace
                text = re.sub(r"\s+", " ", text).strip()

                # Truncate if too long
                if len(text) > 10000:
                    text = text[:10000] + "\n...(truncated)"

                return f"Content from {url}:\n\n{text}"
            else:
                content = response.text[:10000]
                if len(response.text) > 10000:
                    content += "\n...(truncated)"
                return content

    except httpx.HTTPStatusError as e:
        return f"HTTP error fetching {url}: {e.response.status_code}"
    except Exception as e:
        return f"Error fetching {url}: {str(e)}"
