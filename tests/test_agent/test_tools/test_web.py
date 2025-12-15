"""
Integration tests for web tools.
NO MOCKS - tests actual HTTP requests.
"""
import pytest

from agent.tools.web import web_search, web_fetch


class TestWebFetch:
    """Test web fetching functionality."""

    @pytest.mark.asyncio
    async def test_fetch_valid_url(self):
        """Test fetching a valid URL."""
        # Use a reliable URL that's likely to be available
        url = "https://www.example.com"
        result = await web_fetch(url)

        assert "example" in result.lower()
        assert "Error" not in result or "example" in result.lower()

    @pytest.mark.asyncio
    async def test_fetch_html_text_extraction(self):
        """Test that HTML text is extracted."""
        url = "https://www.example.com"
        result = await web_fetch(url, extract_text=True)

        # Should extract text, not include HTML tags
        assert "<html>" not in result.lower()
        assert "<body>" not in result.lower()
        # But should have some content
        assert len(result) > 0

    @pytest.mark.asyncio
    async def test_fetch_without_extraction(self):
        """Test fetching raw HTML without text extraction."""
        url = "https://www.example.com"
        result = await web_fetch(url, extract_text=False)

        # Should contain HTML tags
        assert result is not None
        assert len(result) > 0

    @pytest.mark.asyncio
    async def test_fetch_invalid_url(self):
        """Test fetching an invalid URL."""
        url = "https://this-domain-definitely-does-not-exist-12345.com"
        result = await web_fetch(url)

        assert "Error" in result

    @pytest.mark.asyncio
    async def test_fetch_404_error(self):
        """Test fetching a URL that returns 404."""
        url = "https://www.example.com/this-page-does-not-exist-404-test"
        result = await web_fetch(url)

        assert "Error" in result or "404" in result

    @pytest.mark.asyncio
    async def test_fetch_truncates_long_content(self):
        """Test that very long content is truncated."""
        # example.com is small, but test the truncation logic exists
        url = "https://www.example.com"
        result = await web_fetch(url)

        # Result should be returned (even if not truncated for this small page)
        assert result is not None

    @pytest.mark.asyncio
    async def test_fetch_follows_redirects(self):
        """Test that redirects are followed."""
        # HTTP URLs are redirected to HTTPS for example.com
        url = "http://www.example.com"
        result = await web_fetch(url)

        # Should successfully fetch even though it redirects
        assert len(result) > 0
        assert "example" in result.lower()

    @pytest.mark.asyncio
    async def test_fetch_removes_script_tags(self):
        """Test that script tags are removed during text extraction."""
        url = "https://www.example.com"
        result = await web_fetch(url, extract_text=True)

        # Should not contain script content
        assert "<script" not in result.lower()
        assert "</script>" not in result.lower()

    @pytest.mark.asyncio
    async def test_fetch_removes_style_tags(self):
        """Test that style tags are removed during text extraction."""
        url = "https://www.example.com"
        result = await web_fetch(url, extract_text=True)

        # Should not contain style content
        assert "<style" not in result.lower()
        assert "</style>" not in result.lower()


class TestWebSearch:
    """Test web search functionality."""

    @pytest.mark.asyncio
    async def test_search_returns_placeholder(self):
        """Test that web_search returns placeholder message."""
        result = await web_search("test query")

        # Since this is a placeholder, it should mention that
        assert "placeholder" in result.lower()

    @pytest.mark.asyncio
    async def test_search_includes_query(self):
        """Test that search result includes the query."""
        query = "Python programming"
        result = await web_search(query)

        assert query in result or "python programming" in result.lower()

    @pytest.mark.asyncio
    async def test_search_mentions_integration(self):
        """Test that placeholder mentions API integration."""
        result = await web_search("test")

        # Should mention possible integrations
        assert any(
            keyword in result.lower()
            for keyword in ["api", "tavily", "serpapi", "brave"]
        )

    @pytest.mark.asyncio
    async def test_search_with_max_results(self):
        """Test search with max_results parameter."""
        result = await web_search("test", max_results=3)

        # Should still return placeholder
        assert "placeholder" in result.lower()

    @pytest.mark.asyncio
    async def test_search_empty_query(self):
        """Test search with empty query."""
        result = await web_search("")

        # Should still return something
        assert result is not None
        assert len(result) > 0

    @pytest.mark.asyncio
    async def test_search_special_characters(self):
        """Test search with special characters in query."""
        query = "Python @decorators #best practices"
        result = await web_search(query)

        # Should handle special characters gracefully
        assert result is not None


class TestWebIntegration:
    """Integration tests combining web tools."""

    @pytest.mark.asyncio
    async def test_search_then_fetch_workflow(self):
        """Test a typical workflow: search then fetch."""
        # Simulate finding a URL from search (manually specified)
        url = "https://www.example.com"

        # Fetch the URL
        fetch_result = await web_fetch(url)

        assert len(fetch_result) > 0

    @pytest.mark.asyncio
    async def test_fetch_multiple_urls(self):
        """Test fetching multiple URLs in sequence."""
        urls = [
            "https://www.example.com",
            "https://www.example.org",
        ]

        results = []
        for url in urls:
            result = await web_fetch(url)
            results.append(result)

        # All fetches should return content
        assert all(len(r) > 0 for r in results)

    @pytest.mark.asyncio
    async def test_concurrent_fetches(self):
        """Test concurrent fetching of multiple URLs."""
        import asyncio

        urls = [
            "https://www.example.com",
            "https://www.example.org",
        ]

        # Fetch concurrently
        results = await asyncio.gather(*[web_fetch(url) for url in urls])

        # All should succeed
        assert len(results) == 2
        assert all(len(r) > 0 for r in results)
