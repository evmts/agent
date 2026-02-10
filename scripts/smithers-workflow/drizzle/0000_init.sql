CREATE TABLE IF NOT EXISTS `input` (
    `run_id` text PRIMARY KEY NOT NULL
);
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS `discover` (
    `run_id` text NOT NULL,
    `node_id` text NOT NULL,
    `iteration` integer NOT NULL DEFAULT 0,
    `tickets` text NOT NULL,
    `reasoning` text,
    `completion_estimate` text,
    PRIMARY KEY(`run_id`, `node_id`, `iteration`)
);
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS `research` (
    `run_id` text NOT NULL,
    `node_id` text NOT NULL,
    `iteration` integer NOT NULL DEFAULT 0,
    `ticket_id` text NOT NULL,
    `reference_files` text,
    `external_docs` text,
    `reference_code` text,
    `existing_implementation` text,
    `context_file_path` text,
    `summary` text,
    PRIMARY KEY(`run_id`, `node_id`, `iteration`)
);
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS `plan` (
    `run_id` text NOT NULL,
    `node_id` text NOT NULL,
    `iteration` integer NOT NULL DEFAULT 0,
    `ticket_id` text NOT NULL,
    `implementation_steps` text,
    `files_to_create` text,
    `files_to_modify` text,
    `tests_to_write` text,
    `docs_to_update` text,
    `risks` text,
    `plan_file_path` text,
    PRIMARY KEY(`run_id`, `node_id`, `iteration`)
);
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS `implement` (
    `run_id` text NOT NULL,
    `node_id` text NOT NULL,
    `iteration` integer NOT NULL DEFAULT 0,
    `ticket_id` text NOT NULL,
    `files_created` text,
    `files_modified` text,
    `commit_messages` text,
    `what_was_done` text,
    `tests_written` text,
    `docs_updated` text,
    `all_tests_passing` integer,
    `test_output` text,
    PRIMARY KEY(`run_id`, `node_id`, `iteration`)
);
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS `validate` (
    `run_id` text NOT NULL,
    `node_id` text NOT NULL,
    `iteration` integer NOT NULL DEFAULT 0,
    `ticket_id` text NOT NULL,
    `zig_tests_passed` integer,
    `playwright_tests_passed` integer,
    `build_succeeded` integer,
    `lint_passed` integer,
    `all_passed` integer,
    `failing_summary` text,
    `full_output` text,
    PRIMARY KEY(`run_id`, `node_id`, `iteration`)
);
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS `review` (
    `run_id` text NOT NULL,
    `node_id` text NOT NULL,
    `iteration` integer NOT NULL DEFAULT 0,
    `ticket_id` text NOT NULL,
    `reviewer` text,
    `approved` integer,
    `issues` text,
    `test_coverage` text,
    `code_quality` text,
    `feedback` text,
    PRIMARY KEY(`run_id`, `node_id`, `iteration`)
);
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS `review_fix` (
    `run_id` text NOT NULL,
    `node_id` text NOT NULL,
    `iteration` integer NOT NULL DEFAULT 0,
    `ticket_id` text NOT NULL,
    `fixes_made` text,
    `false_positive_comments` text,
    `commit_messages` text,
    `all_issues_resolved` integer,
    `summary` text,
    PRIMARY KEY(`run_id`, `node_id`, `iteration`)
);
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS `report` (
    `run_id` text NOT NULL,
    `node_id` text NOT NULL,
    `iteration` integer NOT NULL DEFAULT 0,
    `ticket_id` text NOT NULL,
    `ticket_title` text,
    `status` text,
    `summary` text,
    `files_changed` integer,
    `tests_added` integer,
    `review_rounds` integer,
    `struggles` text,
    `time_spent` text,
    `lessons_learned` text,
    PRIMARY KEY(`run_id`, `node_id`, `iteration`)
);
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS `output` (
    `run_id` text NOT NULL,
    `node_id` text NOT NULL,
    `iteration` integer NOT NULL DEFAULT 0,
    `tickets_completed` text,
    `total_iterations` integer,
    `summary` text,
    PRIMARY KEY(`run_id`, `node_id`, `iteration`)
);
