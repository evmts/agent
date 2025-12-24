-- Migration: Fix workflow_definitions.plan config format
--
-- Changes config from:    {"config": {"cmd": "..."}}
-- To:                     {"config": {"data": {"cmd": "..."}}}
--
-- This matches the StepConfig struct in plan.zig which expects:
--   pub const StepConfig = struct {
--       data: std.json.Value,
--   };

-- Update all workflow definitions to wrap step config in {data: ...}
UPDATE workflow_definitions
SET plan = jsonb_set(
    plan,
    '{steps}',
    (
        SELECT jsonb_agg(
            CASE
                -- If config doesn't have 'data' key, wrap it
                WHEN NOT (step->'config' ? 'data') THEN
                    jsonb_set(
                        step,
                        '{config}',
                        jsonb_build_object('data', step->'config')
                    )
                -- Otherwise leave it as is
                ELSE step
            END
        )
        FROM jsonb_array_elements(plan->'steps') AS step
    )
)
WHERE EXISTS (
    -- Only update rows that have steps with unwrapped config
    SELECT 1
    FROM jsonb_array_elements(plan->'steps') AS step
    WHERE NOT (step->'config' ? 'data')
);
