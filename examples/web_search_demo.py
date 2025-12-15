#!/usr/bin/env python3
"""
Demo script showing the web search functionality.

This demonstrates how to:
1. Use web search with default provider (DuckDuckGo)
2. Use web search with API keys (Tavily, SerpAPI)
3. Configure different search providers
4. Handle search results
"""

import asyncio
import os
import sys
from pathlib import Path

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from agent.tools.web import web_search, WebSearchProvider


async def demo_basic_search():
    """Demonstrate basic web search without API keys."""
    print("\n" + "=" * 80)
    print("1. BASIC WEB SEARCH (DuckDuckGo - No API Key Required)")
    print("=" * 80)

    query = "Python asyncio tutorial"
    print(f"\nSearching for: '{query}'")
    print("-" * 80)

    result = await web_search(query, max_results=3)
    print(result)


async def demo_provider_selection():
    """Demonstrate explicit provider selection."""
    print("\n" + "=" * 80)
    print("2. EXPLICIT PROVIDER SELECTION")
    print("=" * 80)

    query = "machine learning"
    print(f"\nSearching for: '{query}' using DuckDuckGo")
    print("-" * 80)

    result = await web_search(
        query,
        max_results=2,
        provider=WebSearchProvider.DUCKDUCKGO
    )
    print(result)


async def demo_tavily_search():
    """Demonstrate Tavily API search (if API key is set)."""
    print("\n" + "=" * 80)
    print("3. TAVILY API SEARCH")
    print("=" * 80)

    tavily_key = os.getenv("TAVILY_API_KEY")

    if not tavily_key:
        print("\nTAVILY_API_KEY not set. Skipping Tavily demo.")
        print("To use Tavily, set the environment variable:")
        print("  export TAVILY_API_KEY='your-api-key-here'")
        print("\nGet your API key at: https://tavily.com/")
        return

    query = "latest AI developments"
    print(f"\nSearching for: '{query}' using Tavily API")
    print("-" * 80)

    result = await web_search(
        query,
        max_results=3,
        provider=WebSearchProvider.TAVILY
    )
    print(result)


async def demo_serp_search():
    """Demonstrate SerpAPI search (if API key is set)."""
    print("\n" + "=" * 80)
    print("4. SERPAPI SEARCH")
    print("=" * 80)

    serp_key = os.getenv("SERP_API_KEY")

    if not serp_key:
        print("\nSERP_API_KEY not set. Skipping SerpAPI demo.")
        print("To use SerpAPI, set the environment variable:")
        print("  export SERP_API_KEY='your-api-key-here'")
        print("\nGet your API key at: https://serpapi.com/")
        return

    query = "weather forecast"
    print(f"\nSearching for: '{query}' using SerpAPI")
    print("-" * 80)

    result = await web_search(
        query,
        max_results=3,
        provider=WebSearchProvider.SERP
    )
    print(result)


async def demo_auto_provider():
    """Demonstrate automatic provider selection based on available API keys."""
    print("\n" + "=" * 80)
    print("5. AUTOMATIC PROVIDER SELECTION")
    print("=" * 80)

    print("\nThe web_search function automatically selects the best available provider:")
    print("  1. Tavily (if TAVILY_API_KEY is set)")
    print("  2. SerpAPI (if SERP_API_KEY is set)")
    print("  3. DuckDuckGo (fallback, no API key needed)")

    print("\nCurrent configuration:")
    print(f"  TAVILY_API_KEY: {'✓ Set' if os.getenv('TAVILY_API_KEY') else '✗ Not set'}")
    print(f"  SERP_API_KEY: {'✓ Set' if os.getenv('SERP_API_KEY') else '✗ Not set'}")

    query = "Python web scraping"
    print(f"\nSearching for: '{query}' (auto-selecting provider)")
    print("-" * 80)

    result = await web_search(query, max_results=3)
    print(result)


async def demo_various_queries():
    """Demonstrate different types of search queries."""
    print("\n" + "=" * 80)
    print("6. VARIOUS SEARCH QUERY EXAMPLES")
    print("=" * 80)

    queries = [
        "how to install Python",
        "best practices REST API design",
        "what is Docker",
    ]

    for query in queries:
        print(f"\nSearching for: '{query}'")
        print("-" * 40)
        result = await web_search(query, max_results=2)
        print(result)
        await asyncio.sleep(1)  # Be nice to the search provider


async def main():
    """Run all demos."""
    print("=" * 80)
    print("WEB SEARCH TOOL DEMONSTRATION")
    print("=" * 80)
    print("\nThis demo shows how to use the web search functionality with different")
    print("providers and configurations.")

    try:
        # Run all demos
        await demo_basic_search()
        await demo_provider_selection()
        await demo_tavily_search()
        await demo_serp_search()
        await demo_auto_provider()
        await demo_various_queries()

        print("\n" + "=" * 80)
        print("DEMO COMPLETE")
        print("=" * 80)
        print("\nKey Points:")
        print("  • DuckDuckGo works out of the box (no API key needed)")
        print("  • Tavily and SerpAPI require API keys but provide better results")
        print("  • Provider is auto-selected based on available API keys")
        print("  • All results are formatted consistently")
        print("\nFor more information, see: agent/tools/web.py")

    except KeyboardInterrupt:
        print("\n\nDemo interrupted by user.")
    except Exception as e:
        print(f"\n\nError during demo: {e}")
        raise


if __name__ == "__main__":
    asyncio.run(main())
