#!/bin/bash
set -e

echo "=== End-to-End Workflow Test ==="
echo ""

# Check if server is running
echo "1. Checking server health..."
if curl -sf http://localhost:4000/health > /dev/null; then
    echo "✅ Server is running"
else
    echo "❌ Server is not running. Start with:"
    echo "   DATABASE_URL=\"postgresql://postgres:password@localhost:54321/plue?sslmode=disable\" WATCHER_ENABLED=false ./zig-out/bin/server-zig"
    exit 1
fi

# Test workflow parsing
echo ""
echo "2. Testing workflow parser..."
PARSE_RESULT=$(curl -s -X POST 'http://localhost:4000/api/workflows/parse' \
  -H 'Content-Type: application/json' \
  -d '{
    "source": "from plue import workflow, push\n\n@workflow(triggers=[push()])\ndef test_e2e(ctx):\n    ctx.run(name=\"echo\", cmd=\"echo hello world\")\n    return ctx.success()"
  }')

if echo "$PARSE_RESULT" | jq -e '.valid == true' > /dev/null; then
    echo "✅ Workflow parsing works"
    echo "   Workflow name: $(echo "$PARSE_RESULT" | jq -r '.name')"
    echo "   Steps: $(echo "$PARSE_RESULT" | jq -r '.step_count')"
    echo "   Triggers: $(echo "$PARSE_RESULT" | jq -r '.trigger_count')"
else
    echo "❌ Workflow parsing failed:"
    echo "$PARSE_RESULT" | jq '.'
    exit 1
fi

# Check database has workflow definitions
echo ""
echo "3. Checking database for test workflows..."
docker exec plue-postgres-1 psql -U postgres -d plue -t -c "SELECT COUNT(*) FROM workflow_definitions;" | tr -d ' '
TEST_WF_COUNT=$(docker exec plue-postgres-1 psql -U postgres -d plue -t -c "SELECT COUNT(*) FROM workflow_definitions WHERE name='test-ci';" | tr -d ' ')
if [ "$TEST_WF_COUNT" -gt 0 ]; then
    echo "✅ Test workflow 'test-ci' found in database"
else
    echo "⚠️  No 'test-ci' workflow found. Inserting test workflow..."
    docker exec plue-postgres-1 psql -U postgres -d plue -c "
    INSERT INTO workflow_definitions (repository_id, name, file_path, triggers, plan, content_hash, parsed_at)
    VALUES (
        1,
        'test-ci',
        '.plue/workflows/ci.py',
        '[{\"type\":\"push\"}]'::jsonb,
        '{\"steps\":[{\"id\":\"step_1\",\"name\":\"echo\",\"type\":\"shell\",\"config\":{\"cmd\":\"echo test\"}}]}'::jsonb,
        'test-hash',
        NOW()
    )
    ON CONFLICT (repository_id, name) DO UPDATE SET
        plan = EXCLUDED.plan,
        updated_at = NOW();
    "
    echo "✅ Test workflow inserted"
fi

# Check runner pool
echo ""
echo "4. Checking runner pool status..."
RUNNER_COUNT=$(docker exec plue-postgres-1 psql -U postgres -d plue -t -c "SELECT COUNT(*) FROM standby_runners WHERE claimed_at IS NULL;" | tr -d ' ')
echo "   Available runners: $RUNNER_COUNT"
if [ "$RUNNER_COUNT" -eq 0 ]; then
    echo "⚠️  No standby runners available. Workflow execution will use cold start."
fi

echo ""
echo "=== Summary ==="
echo "✅ Server: Running"
echo "✅ Workflow Parser: Working"
echo "✅ Database: Connected"
echo "⚠️  Workflow Execution: Blocked by authentication (known issue)"
echo ""
echo "Next steps:"
echo "1. Implement test auth bypass or mock session injection"
echo "2. Test actual workflow execution with queue and runner"
echo "3. Verify SSE streaming"
