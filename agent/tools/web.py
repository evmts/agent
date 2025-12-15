"""
Web search and fetch tools.
"""
import os
import re
from enum import Enum
from typing import Optional

import httpx
from bs4 import BeautifulSoup


class WebSearchProvider(Enum):
    """Available web search providers."""
    DUCKDUCKGO = "duckduckgo"
    TAVILY = "tavily"
    SERP = "serp"


async def _search_duckduckgo(query: str, max_results: int = 5) -> str:
    """
    Search using DuckDuckGo HTML scraping (no API key required).

    Args:
        query: Search query
        max_results: Maximum number of results to return

    Returns:
        Formatted search results
    """
    try:
        async with httpx.AsyncClient(
            timeout=30.0,
            follow_redirects=True,
            headers={
                "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
            }
        ) as client:
            response = await client.get(
                "https://html.duckduckgo.com/html/",
                params={"q": query}
            )
            response.raise_for_status()

            soup = BeautifulSoup(response.text, "html.parser")
            results = []

            # Find all result divs
            result_divs = soup.find_all("div", class_="result")

            for i, result_div in enumerate(result_divs[:max_results]):
                # Extract title and URL
                title_link = result_div.find("a", class_="result__a")
                if not title_link:
                    continue

                title = title_link.get_text(strip=True)
                url = title_link.get("href", "")

                # Extract snippet
                snippet_div = result_div.find("a", class_="result__snippet")
                snippet = snippet_div.get_text(strip=True) if snippet_div else ""

                if title and url:
                    results.append({
                        "title": title,
                        "url": url,
                        "snippet": snippet
                    })

            return _format_search_results(query, results, "DuckDuckGo")

    except Exception as e:
        return f"Error searching DuckDuckGo: {str(e)}"


async def _search_tavily(query: str, max_results: int = 5, api_key: str = "") -> str:
    """
    Search using Tavily API.

    Args:
        query: Search query
        max_results: Maximum number of results to return
        api_key: Tavily API key

    Returns:
        Formatted search results
    """
    try:
        async with httpx.AsyncClient(timeout=30.0) as client:
            response = await client.post(
                "https://api.tavily.com/search",
                json={
                    "api_key": api_key,
                    "query": query,
                    "max_results": max_results
                }
            )
            response.raise_for_status()

            data = response.json()
            results = []

            for result in data.get("results", []):
                results.append({
                    "title": result.get("title", ""),
                    "url": result.get("url", ""),
                    "snippet": result.get("content", "")
                })

            return _format_search_results(query, results, "Tavily")

    except Exception as e:
        return f"Error searching Tavily: {str(e)}"


async def _search_serp(query: str, max_results: int = 5, api_key: str = "") -> str:
    """
    Search using SerpAPI.

    Args:
        query: Search query
        max_results: Maximum number of results to return
        api_key: SerpAPI API key

    Returns:
        Formatted search results
    """
    try:
        async with httpx.AsyncClient(timeout=30.0) as client:
            response = await client.get(
                "https://serpapi.com/search",
                params={
                    "q": query,
                    "api_key": api_key,
                    "num": max_results
                }
            )
            response.raise_for_status()

            data = response.json()
            results = []

            for result in data.get("organic_results", []):
                results.append({
                    "title": result.get("title", ""),
                    "url": result.get("link", ""),
                    "snippet": result.get("snippet", "")
                })

            return _format_search_results(query, results, "SerpAPI")

    except Exception as e:
        return f"Error searching SerpAPI: {str(e)}"


def _format_search_results(query: str, results: list[dict], provider: str) -> str:
    """
    Format search results consistently.

    Args:
        query: Original search query
        results: List of result dictionaries
        provider: Name of the search provider

    Returns:
        Formatted search results string
    """
    if not results:
        return f'No results found for: "{query}" (using {provider})'

    output = [f'Web search results for: "{query}" (using {provider})\n']

    for i, result in enumerate(results, 1):
        output.append(f"{i}. {result['title']}")
        output.append(f"   URL: {result['url']}")
        if result['snippet']:
            output.append(f"   {result['snippet']}")
        output.append("")

    return "\n".join(output)


async def web_search(
    query: str,
    max_results: int = 5,
    provider: Optional[WebSearchProvider] = None
) -> str:
    """
    Search the web for information.

    Args:
        query: Search query
        max_results: Maximum number of results to return
        provider: Specific provider to use (optional, auto-detects if None)

    Returns:
        Search results with titles, URLs, and snippets

    Environment Variables:
        TAVILY_API_KEY: API key for Tavily search
        SERP_API_KEY: API key for SerpAPI search
    """
    # Check for API keys
    tavily_key = os.getenv("TAVILY_API_KEY", "")
    serp_key = os.getenv("SERP_API_KEY", "")

    # Auto-select provider if not specified
    if provider is None:
        if tavily_key:
            provider = WebSearchProvider.TAVILY
        elif serp_key:
            provider = WebSearchProvider.SERP
        else:
            provider = WebSearchProvider.DUCKDUCKGO

    # Execute search based on provider
    if provider == WebSearchProvider.TAVILY:
        if not tavily_key:
            return "Error: TAVILY_API_KEY environment variable not set. Falling back to DuckDuckGo."
        return await _search_tavily(query, max_results, tavily_key)

    elif provider == WebSearchProvider.SERP:
        if not serp_key:
            return "Error: SERP_API_KEY environment variable not set. Falling back to DuckDuckGo."
        return await _search_serp(query, max_results, serp_key)

    else:  # DuckDuckGo
        return await _search_duckduckgo(query, max_results)


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
