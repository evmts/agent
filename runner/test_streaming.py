"""
Tests for streaming.py retry logic.
"""

import pytest
from unittest.mock import Mock, patch, call
import httpx

from streaming import StreamingClient, CRITICAL_EVENTS


@pytest.fixture
def client():
    """Create a StreamingClient for testing."""
    return StreamingClient(callback_url="http://test.example.com/callback", task_id="test-task-123")


@pytest.fixture
def mock_response():
    """Create a mock HTTP response."""
    response = Mock()
    response.status_code = 200
    return response


class TestRetryLogic:
    """Test retry logic for network failures."""

    def test_success_on_first_try(self, client, mock_response):
        """Event succeeds immediately, no retries needed."""
        with patch.object(client.client, 'post', return_value=mock_response) as mock_post:
            result = client.send_done()

            assert result is True
            assert mock_post.call_count == 1

    def test_retry_on_timeout(self, client):
        """Timeout errors trigger retry with exponential backoff."""
        mock_response = Mock()
        mock_response.status_code = 200

        with patch.object(client.client, 'post') as mock_post:
            # First 2 attempts timeout, third succeeds
            mock_post.side_effect = [
                httpx.TimeoutException("Request timeout"),
                httpx.TimeoutException("Request timeout"),
                mock_response
            ]

            with patch('time.sleep') as mock_sleep:
                result = client.send_done()

                assert result is True
                assert mock_post.call_count == 3
                # Verify exponential backoff (base 0.5s)
                assert mock_sleep.call_count == 2
                # First retry: ~0.5s + jitter
                first_delay = mock_sleep.call_args_list[0][0][0]
                assert 0.5 <= first_delay <= 0.5 * 1.25
                # Second retry: ~1.0s + jitter
                second_delay = mock_sleep.call_args_list[1][0][0]
                assert 1.0 <= second_delay <= 1.0 * 1.25

    def test_retry_on_network_error(self, client):
        """Network errors trigger retry."""
        mock_response = Mock()
        mock_response.status_code = 200

        with patch.object(client.client, 'post') as mock_post:
            mock_post.side_effect = [
                httpx.NetworkError("Connection reset"),
                mock_response
            ]

            with patch('time.sleep'):
                result = client.send_error("test error")

                assert result is True
                assert mock_post.call_count == 2

    def test_retry_on_connect_error(self, client):
        """Connect errors trigger retry."""
        mock_response = Mock()
        mock_response.status_code = 200

        with patch.object(client.client, 'post') as mock_post:
            mock_post.side_effect = [
                httpx.ConnectError("Connection refused"),
                mock_response
            ]

            with patch('time.sleep'):
                result = client.send_done()

                assert result is True
                assert mock_post.call_count == 2

    def test_retry_on_5xx_errors(self, client):
        """5xx server errors trigger retry."""
        error_response = Mock()
        error_response.status_code = 503

        success_response = Mock()
        success_response.status_code = 200

        with patch.object(client.client, 'post') as mock_post:
            mock_post.side_effect = [
                error_response,
                error_response,
                success_response
            ]

            with patch('time.sleep'):
                result = client.send_done()

                assert result is True
                assert mock_post.call_count == 3

    def test_no_retry_on_4xx_errors(self, client):
        """4xx client errors do not trigger retry."""
        error_response = Mock()
        error_response.status_code = 400

        with patch.object(client.client, 'post', return_value=error_response) as mock_post:
            result = client.send_done()

            assert result is False
            # Only one attempt, no retries
            assert mock_post.call_count == 1

    def test_no_retry_on_404(self, client):
        """404 errors do not trigger retry."""
        error_response = Mock()
        error_response.status_code = 404

        with patch.object(client.client, 'post', return_value=error_response) as mock_post:
            result = client.send_token("hello")

            assert result is False
            assert mock_post.call_count == 1

    def test_max_retries_normal_event(self, client):
        """Normal events max out at 5 retries."""
        with patch.object(client.client, 'post') as mock_post:
            # Always timeout
            mock_post.side_effect = httpx.TimeoutException("Request timeout")

            with patch('time.sleep'):
                result = client.send_token("hello")

                assert result is False
                # 1 initial attempt + 5 retries = 6 total
                assert mock_post.call_count == 6

    def test_max_retries_critical_event(self, client):
        """Critical events (done, error, tool_end) max out at 10 retries."""
        with patch.object(client.client, 'post') as mock_post:
            # Always timeout
            mock_post.side_effect = httpx.TimeoutException("Request timeout")

            with patch('time.sleep'):
                result = client.send_done()

                assert result is False
                # 1 initial attempt + 10 retries = 11 total
                assert mock_post.call_count == 11

    def test_critical_events_defined(self):
        """Verify critical events are correctly identified."""
        assert 'done' in CRITICAL_EVENTS
        assert 'error' in CRITICAL_EVENTS
        assert 'tool_end' in CRITICAL_EVENTS
        # Non-critical events
        assert 'token' not in CRITICAL_EVENTS
        assert 'tool_start' not in CRITICAL_EVENTS

    def test_exponential_backoff_caps_at_max(self, client):
        """Verify backoff delay caps at 30 seconds."""
        with patch.object(client.client, 'post') as mock_post:
            mock_post.side_effect = httpx.TimeoutException("Request timeout")

            with patch('time.sleep') as mock_sleep:
                client.send_done()

                # Check that later retries have delay capped at ~30s
                delays = [call_args[0][0] for call_args in mock_sleep.call_args_list]
                # After enough retries, delay should cap at max_delay (30s) + jitter (7.5s)
                assert all(d <= 30.0 * 1.25 for d in delays)
                # Later delays should be close to max
                if len(delays) >= 6:
                    assert delays[-1] >= 30.0

    def test_jitter_prevents_thundering_herd(self, client):
        """Verify jitter adds randomness to prevent thundering herd."""
        with patch.object(client.client, 'post') as mock_post:
            mock_post.side_effect = [
                httpx.TimeoutException("Request timeout"),
                httpx.TimeoutException("Request timeout"),
                Mock(status_code=200)
            ]

            with patch('time.sleep') as mock_sleep:
                client.send_done()

                delays = [call_args[0][0] for call_args in mock_sleep.call_args_list]
                # First delay: base 0.5s with up to 25% jitter (0.5 to 0.625)
                assert 0.5 <= delays[0] <= 0.625
                # Second delay: base 1.0s with up to 25% jitter (1.0 to 1.25)
                assert 1.0 <= delays[1] <= 1.25

    def test_tool_end_is_critical(self, client):
        """tool_end events should get critical retry count."""
        with patch.object(client.client, 'post') as mock_post:
            mock_post.side_effect = httpx.TimeoutException("Request timeout")

            with patch('time.sleep'):
                result = client.send_tool_end(tool_id="tool-123", state="success")

                assert result is False
                # Critical event: 11 attempts total
                assert mock_post.call_count == 11

    def test_logging_on_retry_success(self, client, caplog):
        """Verify logging when retry succeeds."""
        mock_response = Mock()
        mock_response.status_code = 200

        with patch.object(client.client, 'post') as mock_post:
            mock_post.side_effect = [
                httpx.TimeoutException("Request timeout"),
                mock_response
            ]

            with patch('time.sleep'):
                with caplog.at_level('INFO'):
                    client.send_done()

                    # Should log success after retry
                    assert "succeeded on attempt 2" in caplog.text

    def test_logging_on_retry_exhaustion(self, client, caplog):
        """Verify logging when retries are exhausted."""
        with patch.object(client.client, 'post') as mock_post:
            mock_post.side_effect = httpx.TimeoutException("Request timeout")

            with patch('time.sleep'):
                with caplog.at_level('ERROR'):
                    client.send_token("test")

                    # Should log final failure
                    assert "failed after" in caplog.text
                    assert "attempts" in caplog.text

    def test_all_public_methods_use_retry(self, client):
        """Verify all public send methods use the retry logic."""
        mock_response = Mock()
        mock_response.status_code = 200

        with patch.object(client.client, 'post') as mock_post:
            mock_post.side_effect = [
                httpx.TimeoutException("timeout"),
                mock_response
            ]

            with patch('time.sleep'):
                # Should retry and succeed
                result = client.send_log("info", "test message")
                assert result is True
                assert mock_post.call_count == 2


class TestShouldRetry:
    """Test the retry decision logic."""

    def test_retry_5xx_errors(self, client):
        """All 5xx status codes should trigger retry."""
        for status in [500, 502, 503, 504, 599]:
            assert client._should_retry(None, status_code=status)

    def test_no_retry_4xx_errors(self, client):
        """All 4xx status codes should not trigger retry."""
        for status in [400, 401, 403, 404, 422, 499]:
            assert not client._should_retry(None, status_code=status)

    def test_retry_timeout_exception(self, client):
        """TimeoutException should trigger retry."""
        error = httpx.TimeoutException("timeout")
        assert client._should_retry(error)

    def test_retry_network_error(self, client):
        """NetworkError should trigger retry."""
        error = httpx.NetworkError("network error")
        assert client._should_retry(error)

    def test_retry_connect_error(self, client):
        """ConnectError should trigger retry."""
        error = httpx.ConnectError("connection refused")
        assert client._should_retry(error)

    def test_no_retry_other_exceptions(self, client):
        """Other exceptions should not trigger retry."""
        error = ValueError("some other error")
        assert not client._should_retry(error)
