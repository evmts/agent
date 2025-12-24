# Add Retry Logic to Streaming Client

## Priority: HIGH | Reliability

## Problem

Network failures in the streaming client result in silent event loss:

`runner/src/streaming.py:30-41`
```python
def _send_event(self, event: dict) -> bool:
    try:
        response = self.client.post(self.callback_url, json=event, timeout=30)
        return response.status_code == 200
    except Exception as e:
        logger.error(f"Failed to send event: {e}")
        return False  # Event is lost forever!
```

Critical events like `done`, `error`, and `tool_result` can disappear.

## Task

1. **Implement retry with exponential backoff:**
   ```python
   # runner/src/streaming.py

   import time
   from typing import Optional

   class StreamingClient:
       MAX_RETRIES = 5
       BASE_DELAY = 0.5  # seconds
       MAX_DELAY = 30.0  # seconds

       def _send_event_with_retry(self, event: dict) -> bool:
           """Send event with exponential backoff retry."""
           last_error: Optional[Exception] = None

           for attempt in range(self.MAX_RETRIES):
               try:
                   response = self.client.post(
                       self.callback_url,
                       json=event,
                       timeout=30
                   )
                   if response.status_code == 200:
                       return True
                   elif response.status_code >= 500:
                       # Server error, retry
                       last_error = Exception(f"Server error: {response.status_code}")
                   else:
                       # Client error, don't retry
                       logger.error(f"Client error {response.status_code}: {response.text}")
                       return False
               except httpx.TimeoutException as e:
                   last_error = e
                   logger.warning(f"Timeout on attempt {attempt + 1}")
               except httpx.NetworkError as e:
                   last_error = e
                   logger.warning(f"Network error on attempt {attempt + 1}: {e}")
               except Exception as e:
                   last_error = e
                   logger.error(f"Unexpected error: {e}")
                   return False

               # Exponential backoff with jitter
               if attempt < self.MAX_RETRIES - 1:
                   delay = min(self.BASE_DELAY * (2 ** attempt), self.MAX_DELAY)
                   jitter = delay * 0.1 * random.random()
                   time.sleep(delay + jitter)

           logger.error(f"Failed after {self.MAX_RETRIES} attempts: {last_error}")
           return False
   ```

2. **Prioritize critical events:**
   ```python
   CRITICAL_EVENTS = {'done', 'error', 'tool_result'}

   def send_event(self, event_type: str, **data) -> bool:
       event = {'type': event_type, 'task_id': self.task_id, **data}

       if event_type in self.CRITICAL_EVENTS:
           # More retries for critical events
           return self._send_event_with_retry(event, max_retries=10)
       return self._send_event_with_retry(event)
   ```

3. **Add event buffering for batch recovery:**
   ```python
   def __init__(self, callback_url: str, task_id: str):
       self.buffer: list[dict] = []
       self.buffer_max = 100

   def _buffer_event(self, event: dict):
       """Buffer failed events for potential recovery."""
       if len(self.buffer) >= self.buffer_max:
           self.buffer.pop(0)  # Drop oldest
       self.buffer.append(event)

   def flush_buffer(self) -> int:
       """Attempt to resend buffered events."""
       sent = 0
       remaining = []
       for event in self.buffer:
           if self._send_event_with_retry(event):
               sent += 1
           else:
               remaining.append(event)
       self.buffer = remaining
       return sent
   ```

4. **Add connection health check:**
   ```python
   def check_connection(self) -> bool:
       """Check if callback URL is reachable."""
       try:
           response = self.client.head(self.callback_url, timeout=5)
           return response.status_code < 500
       except Exception:
           return False
   ```

5. **Write tests:**
   ```python
   # runner/tests/test_streaming.py

   def test_retry_on_timeout(mocker):
       client = StreamingClient("http://example.com/callback", "task-123")

       # First two calls timeout, third succeeds
       mock_post = mocker.patch.object(client.client, 'post')
       mock_post.side_effect = [
           httpx.TimeoutException("timeout"),
           httpx.TimeoutException("timeout"),
           mocker.Mock(status_code=200),
       ]

       result = client.send_event("token", text="hello")

       assert result is True
       assert mock_post.call_count == 3

   def test_no_retry_on_client_error(mocker):
       client = StreamingClient("http://example.com/callback", "task-123")

       mock_post = mocker.patch.object(client.client, 'post')
       mock_post.return_value = mocker.Mock(status_code=400, text="Bad request")

       result = client.send_event("token", text="hello")

       assert result is False
       assert mock_post.call_count == 1  # No retry
   ```

## Acceptance Criteria

- [ ] Transient failures trigger retry with backoff
- [ ] Critical events get more retry attempts
- [ ] Client errors (4xx) don't retry
- [ ] Maximum retry limit prevents infinite loops
- [ ] Events are logged when dropped
- [ ] Unit tests cover retry scenarios
