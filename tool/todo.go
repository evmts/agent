package tool

import (
	"encoding/json"
	"fmt"
	"sync"
)

const (
	TodoDescriptionWrite = `Use this tool to create and manage a structured task list for your current coding session. This helps you track progress, organize complex tasks, and demonstrate thoroughness to the user.
It also helps the user understand the progress of the task and overall progress of their requests.

## When to Use This Tool
Use this tool proactively in these scenarios:

1. Complex multi-step tasks - When a task requires 3 or more distinct steps or actions
2. Non-trivial and complex tasks - Tasks that require careful planning or multiple operations
3. User explicitly requests todo list - When the user directly asks you to use the todo list
4. User provides multiple tasks - When users provide a list of things to be done (numbered or comma-separated)
5. After receiving new instructions - Immediately capture user requirements as todos
6. When you start working on a task - Mark it as in_progress BEFORE beginning work. Ideally you should only have one todo as in_progress at a time
7. After completing a task - Mark it as completed and add any new follow-up tasks discovered during implementation

## When NOT to Use This Tool

Skip using this tool when:
1. There is only a single, straightforward task
2. The task is trivial and tracking it provides no organizational benefit
3. The task can be completed in less than 3 trivial steps
4. The task is purely conversational or informational

NOTE that you should not use this tool if there is only one trivial task to do. In this case you are better off just doing the task directly.

## Examples of When to Use the Todo List

<example>
User: I want to add a dark mode toggle to the application settings. Make sure you run the tests and build when you're done!
Assistant: I'll help add a dark mode toggle to your application settings. Let me create a todo list to track this implementation.
*Creates todo list with the following items:*
1. Creating dark mode toggle component in Settings page
2. Adding dark mode state management (context/store)
3. Implementing CSS-in-JS styles for dark theme
4. Updating existing components to support theme switching
5. Running tests and build process, addressing any failures or errors that occur
*Begins working on the first task*

<reasoning>
The assistant used the todo list because:
1. Adding dark mode is a multi-step feature requiring UI, state management, and styling changes
2. The user explicitly requested tests and build be run afterward
3. The assistant inferred that tests and build need to pass by adding "Ensure tests and build succeed" as the final task
</reasoning>
</example>

<example>
User: Help me rename the function getCwd to getCurrentWorkingDirectory across my project
Assistant: Let me first search through your codebase to find all occurrences of 'getCwd'.
*Uses grep or search tools to locate all instances of getCwd in the codebase*
Assistant: I've found 15 instances of 'getCwd' across 8 different files. Let me create a todo list to track these changes.
*Creates todo list with specific items for each file that needs updating*

<reasoning>
The assistant used the todo list because:
1. First, the assistant searched to understand the scope of the task
2. Upon finding multiple occurrences across different files, it determined this was a complex task with multiple steps
3. The todo list helps ensure every instance is tracked and updated systematically
4. This approach prevents missing any occurrences and maintains code consistency
</reasoning>
</example>


<example>
User: I need to implement these features for my e-commerce site: user registration, product catalog, shopping cart, and checkout flow.
Assistant: I'll help implement these features. First, let's add all the features to the todo list.
*Creates a todo list breaking down each feature into specific tasks based on the project architecture*
Assistant: Let's start with user registration. This will involve creating database models, API endpoints, and frontend forms that integrate with your existing authentication system.

<reasoning>
The assistant used the todo list because:
1. The user provided multiple complex features to implement in a comma separated list
2. The todo list helps organize these large features into manageable tasks
3. This approach allows for tracking progress across the entire implementation
</reasoning>
</example>

<example>
User: Can you help optimize my React application? It's rendering slowly and has performance issues.</user>
Assistant: I'll help optimize your React application. First, let me examine your codebase to identify potential performance bottlenecks.
*Reviews component structure, render patterns, state management, and data fetching*
Assistant: After analyzing your codebase, I've identified several performance issues. Let me create a todo list to track our optimization efforts.
*Creates todo list with items like: 1) Implementing memoization for expensive calculations in ProductList, 2) Adding virtualization for long lists in Dashboard, 3) Optimizing image loading in Gallery component, 4) Fixing state update loops in ShoppingCart, 5) Reviewing bundle size and implementing code splitting*
Let's start by implementing memoization for the expensive calculations in your ProductList component.</assistant>

<reasoning>
The assistant used the todo list because:
1. First, the assistant examined the codebase to identify specific performance issues
2. Based on this analysis, it identified multiple optimization opportunities
3. Performance optimization is a non-trivial task requiring multiple steps
4. The todo list helps methodically track improvements across different components
5. This systematic approach ensures all performance bottlenecks are addressed
</reasoning>
</example>

## Examples of When NOT to Use the Todo List

<example>
User: How do I print 'Hello World' in Python?
Assistant: In Python, you can print "Hello World" with this simple code:

python
print("Hello World")

This will output the text "Hello World" to the console when executed.</assistant>

<reasoning>
The assistant did not use the todo list because this is a single, trivial task that can be completed in one step. There's no need to track multiple tasks or steps for such a straightforward request.
</reasoning>
</example>

<example>
User: What does the git status command do?
Assistant: The git status command shows the current state of your working directory and staging area. It displays which changes have been staged, which haven't, and which files aren't being tracked by Git. This is a fundamental command for understanding the current state of your repository before making commits.

<reasoning>
The assistant did not use the todo list because this is an informational request with no actual coding task to complete. The user is simply asking for an explanation, not for the assistant to perform multiple steps or tasks.
</reasoning>
</example>

<example>
User: Can you add a comment to the calculateTotal function to explain what it does?
Assistant: Sure, let me add a comment to the calculateTotal function to explain what it does.
* Uses the Edit tool to add a comment to the calculateTotal function *

<reasoning>
The assistant did not use the todo list because this is a single, straightforward task confined to one location in the code. Adding a comment doesn't require tracking multiple steps or systematic organization.
</reasoning>
</example>

<example>
User: Run npm install for me and tell me what happens.
Assistant: I'll run the npm install command for you.

*Executes: npm install*

The command completed successfully. Here's the output:
[Output of npm install command]

All dependencies have been installed according to your package.json file.

<reasoning>
The assistant did not use the todo list because this is a single command execution with immediate results. There are no multiple steps to track or organize, making the todo list unnecessary for this straightforward task.
</reasoning>
</example>

## Task States and Management

1. **Task States**: Use these states to track progress:
   - pending: Task not yet started
   - in_progress: Currently working on (limit to ONE task at a time)
   - completed: Task finished successfully

   **IMPORTANT**: Task descriptions must have two forms:
   - content: The imperative form describing what needs to be done (e.g., "Run tests", "Build the project")
   - activeForm: The present continuous form shown during execution (e.g., "Running tests", "Building the project")

2. **Task Management**:
   - Update task status in real-time as you work
   - Mark tasks complete IMMEDIATELY after finishing (don't batch completions)
   - Exactly ONE task must be in_progress at any time (not less, not more)
   - Complete current tasks before starting new ones
   - Remove tasks that are no longer relevant from the list entirely

3. **Task Completion Requirements**:
   - ONLY mark a task as completed when you have FULLY accomplished it
   - If you encounter errors, blockers, or cannot finish, keep the task as in_progress
   - When blocked, create a new task describing what needs to be resolved
   - Never mark a task as completed if:
     - Tests are failing
     - Implementation is partial
     - You encountered unresolved errors
     - You couldn't find necessary files or dependencies

4. **Task Breakdown**:
   - Create specific, actionable items
   - Break complex tasks into smaller, manageable steps
   - Use clear, descriptive task names
   - Always provide both forms:
     - content: "Fix authentication bug"
     - activeForm: "Fixing authentication bug"

When in doubt, use this tool. Being proactive with task management demonstrates attentiveness and ensures you complete all requirements successfully.
`

	TodoDescriptionRead = `Use this tool to read the current to-do list for the session. This tool should be used proactively and frequently to ensure that you are aware of
the status of the current task list. You should make use of this tool as often as possible, especially in the following situations:
- At the beginning of conversations to see what's pending
- Before starting new tasks to prioritize work
- When the user asks about previous tasks or plans
- Whenever you're uncertain about what to do next
- After completing tasks to update your understanding of remaining work
- After every few messages to ensure you're on track

Usage:
- This tool takes in no parameters. So leave the input blank or empty. DO NOT include a dummy object, placeholder string or a key like "input" or "empty". LEAVE IT BLANK.
- Returns a list of todo items with their status, priority, and content
- Use this information to track progress and plan next steps
- If no todos exist yet, an empty list will be returned
`
)

// TodoInfo represents a single todo item
type TodoInfo struct {
	Content    string `json:"content"`
	Status     string `json:"status"`
	ActiveForm string `json:"activeForm"`
}

// TodoStorage manages todo lists per session
type TodoStorage struct {
	mu    sync.RWMutex
	todos map[string][]TodoInfo // sessionID -> todos
}

var globalTodoStorage = &TodoStorage{
	todos: make(map[string][]TodoInfo),
}

// Get retrieves todos for a session
func (ts *TodoStorage) Get(sessionID string) []TodoInfo {
	ts.mu.RLock()
	defer ts.mu.RUnlock()

	if todos, ok := ts.todos[sessionID]; ok {
		// Return a copy to prevent external modification
		result := make([]TodoInfo, len(todos))
		copy(result, todos)
		return result
	}
	return []TodoInfo{}
}

// Update updates todos for a session
func (ts *TodoStorage) Update(sessionID string, todos []TodoInfo) {
	ts.mu.Lock()
	defer ts.mu.Unlock()

	// Store a copy
	todosCopy := make([]TodoInfo, len(todos))
	copy(todosCopy, todos)
	ts.todos[sessionID] = todosCopy
}

// TodoWriteTool creates the todo write tool
func TodoWriteTool() *ToolDefinition {
	return &ToolDefinition{
		ID:          "todowrite",
		Name:        "TodoWrite",
		Description: TodoDescriptionWrite,
		InputSchema: map[string]interface{}{
			"type": "object",
			"properties": map[string]interface{}{
				"todos": map[string]interface{}{
					"type":        "array",
					"description": "The updated todo list",
					"items": map[string]interface{}{
						"type": "object",
						"properties": map[string]interface{}{
							"content": map[string]interface{}{
								"type":        "string",
								"description": "Brief description of the task",
								"minLength":   1,
							},
							"status": map[string]interface{}{
								"type":        "string",
								"description": "Current status of the task: pending, in_progress, completed",
								"enum":        []string{"pending", "in_progress", "completed"},
							},
							"activeForm": map[string]interface{}{
								"type":        "string",
								"description": "Present continuous form of the task (e.g., 'Running tests')",
								"minLength":   1,
							},
						},
						"required": []string{"content", "status", "activeForm"},
					},
				},
			},
			"required": []string{"todos"},
		},
		Execute: executeTodoWrite,
	}
}

// TodoReadTool creates the todo read tool
func TodoReadTool() *ToolDefinition {
	return &ToolDefinition{
		ID:          "todoread",
		Name:        "TodoRead",
		Description: TodoDescriptionRead,
		InputSchema: map[string]interface{}{
			"type":       "object",
			"properties": map[string]interface{}{},
		},
		Execute: executeTodoRead,
	}
}

func executeTodoWrite(params map[string]interface{}, ctx ToolContext) (ToolResult, error) {
	todosParam, ok := params["todos"]
	if !ok {
		return ToolResult{}, fmt.Errorf("todos parameter is required")
	}

	// Parse todos array
	todosJSON, err := json.Marshal(todosParam)
	if err != nil {
		return ToolResult{}, fmt.Errorf("failed to marshal todos: %v", err)
	}

	var todos []TodoInfo
	if err := json.Unmarshal(todosJSON, &todos); err != nil {
		return ToolResult{}, fmt.Errorf("failed to parse todos: %v", err)
	}

	// Validate todos
	for i, todo := range todos {
		if todo.Content == "" {
			return ToolResult{}, fmt.Errorf("todo %d: content is required", i)
		}
		if todo.ActiveForm == "" {
			return ToolResult{}, fmt.Errorf("todo %d: activeForm is required", i)
		}
		if todo.Status != "pending" && todo.Status != "in_progress" && todo.Status != "completed" {
			return ToolResult{}, fmt.Errorf("todo %d: invalid status '%s' (must be pending, in_progress, or completed)", i, todo.Status)
		}
	}

	// Update storage
	globalTodoStorage.Update(ctx.SessionID, todos)

	// Count non-completed todos
	nonCompletedCount := 0
	for _, todo := range todos {
		if todo.Status != "completed" {
			nonCompletedCount++
		}
	}

	// Format output
	outputJSON, _ := json.MarshalIndent(todos, "", "  ")

	return ToolResult{
		Title:  fmt.Sprintf("%d todos", nonCompletedCount),
		Output: string(outputJSON),
		Metadata: map[string]interface{}{
			"todos": todos,
		},
	}, nil
}

func executeTodoRead(params map[string]interface{}, ctx ToolContext) (ToolResult, error) {
	todos := globalTodoStorage.Get(ctx.SessionID)

	// Count non-completed todos
	nonCompletedCount := 0
	for _, todo := range todos {
		if todo.Status != "completed" {
			nonCompletedCount++
		}
	}

	// Format output
	outputJSON, _ := json.MarshalIndent(todos, "", "  ")

	return ToolResult{
		Title:  fmt.Sprintf("%d todos", nonCompletedCount),
		Output: string(outputJSON),
		Metadata: map[string]interface{}{
			"todos": todos,
		},
	}, nil
}
