# Actions: Workflow Parsing & Job Generation

<task_definition>
Implement a comprehensive GitHub Actions workflow parser that converts YAML workflow definitions into executable job graphs with dependency resolution, conditional execution, matrix strategies, and full compatibility with GitHub Actions syntax. This parser will generate optimized job execution plans with proper error handling and validation.
</task_definition>

<context_and_constraints>

<technical_requirements>

- **Language/Framework**: Zig with YAML parsing - https://ziglang.org/documentation/master/
- **Dependencies**: YAML parser, Actions data models from issue #25
- **Location**: `src/actions/workflow_parser.zig`, `src/actions/job_graph.zig`
- **Compatibility**: Full GitHub Actions workflow syntax support
- **Performance**: Fast parsing with efficient job graph generation
- **Memory**: Minimal allocations, explicit ownership patterns
- **Validation**: Comprehensive syntax and semantic validation

</technical_requirements>

<business_context>

Workflow parsing enables:

- **GitHub Compatibility**: Support existing GitHub Actions workflows without modification
- **Job Orchestration**: Complex job dependency graphs with parallel execution
- **Matrix Strategies**: Multiple job variations with different configurations
- **Conditional Logic**: Dynamic job execution based on context and conditions
- **Reusable Workflows**: Workflow composition and action marketplace integration
- **Developer Experience**: Clear error messages and validation feedback
- **CI/CD Flexibility**: Support for diverse build and deployment scenarios

This provides the intelligence layer that transforms static YAML into executable CI/CD pipelines.

</business_context>

</context_and_constraints>

<detailed_specifications>

<input>

GitHub Actions workflow syntax support:

1. **Basic Workflow Structure**:
   ```yaml
   name: CI
   on:
     push:
       branches: [ main, develop ]
       paths: [ 'src/**', '!docs/**' ]
     pull_request:
       types: [ opened, synchronize ]
     schedule:
       - cron: '0 2 * * *'
     workflow_dispatch:
       inputs:
         environment:
           description: 'Environment to deploy'
           required: true
           default: 'staging'
   
   env:
     NODE_VERSION: '18'
     CI: true
   
   jobs:
     test:
       runs-on: ubuntu-latest
       strategy:
         matrix:
           node: [16, 18, 20]
           os: [ubuntu-latest, windows-latest]
       steps:
         - uses: actions/checkout@v4
         - uses: actions/setup-node@v3
           with:
             node-version: ${{ matrix.node }}
         - run: npm ci
         - run: npm test
   ```

2. **Complex Job Dependencies**:
   ```yaml
   jobs:
     build:
       runs-on: ubuntu-latest
       outputs:
         version: ${{ steps.version.outputs.version }}
       steps:
         - id: version
           run: echo "version=1.2.3" >> $GITHUB_OUTPUT
   
     test:
       needs: build
       runs-on: ubuntu-latest
       strategy:
         matrix:
           test-type: [unit, integration, e2e]
       steps:
         - run: echo "Testing ${{ matrix.test-type }}"
   
     deploy:
       needs: [build, test]
       if: github.ref == 'refs/heads/main'
       runs-on: ubuntu-latest
       environment: production
       steps:
         - run: echo "Deploying version ${{ needs.build.outputs.version }}"
   ```

3. **Advanced Features**:
   - Reusable workflows and composite actions
   - Service containers and databases
   - Artifact upload/download
   - Environment protection rules
   - Concurrency controls

Expected parser operations:
```zig
// Parse workflow from YAML
const workflow = try WorkflowParser.parse(allocator, yaml_content, .{
    .validate_syntax = true,
    .resolve_includes = true,
    .expand_matrices = true,
});
defer workflow.deinit(allocator);

// Generate job execution graph
const job_graph = try JobGraphBuilder.build(allocator, &workflow, .{
    .trigger_event = .push,
    .context = execution_context,
});
defer job_graph.deinit(allocator);

// Get executable job plan
const execution_plan = try job_graph.getExecutionPlan(allocator);
defer execution_plan.deinit(allocator);
```

</input>

<expected_output>

Complete workflow parsing system providing:

1. **YAML Parser**: Full GitHub Actions syntax support with validation
2. **Job Graph Builder**: Dependency resolution and execution planning
3. **Matrix Expansion**: Strategy matrix expansion into individual jobs
4. **Context Resolution**: Expression evaluation and variable substitution
5. **Conditional Evaluation**: Dynamic job inclusion based on conditions
6. **Validation Engine**: Comprehensive syntax and semantic validation
7. **Error Reporting**: Detailed error messages with line numbers and suggestions
8. **Optimization**: Job graph optimization for parallel execution

Core parser architecture:
```zig
const WorkflowParser = struct {
    allocator: std.mem.Allocator,
    options: ParseOptions,
    
    pub fn parse(allocator: std.mem.Allocator, yaml_content: []const u8, options: ParseOptions) !ParsedWorkflow;
    
    const ParseOptions = struct {
        validate_syntax: bool = true,
        resolve_includes: bool = false,
        expand_matrices: bool = true,
        max_matrix_combinations: u32 = 256,
    };
};

const ParsedWorkflow = struct {
    name: []const u8,
    triggers: []const WorkflowTrigger,
    env: std.StringHashMap([]const u8),
    jobs: std.StringHashMap(Job),
    defaults: ?WorkflowDefaults,
    concurrency: ?ConcurrencyConfig,
    
    pub fn deinit(self: *ParsedWorkflow, allocator: std.mem.Allocator) void;
    pub fn validate(self: *const ParsedWorkflow, allocator: std.mem.Allocator) !ValidationResult;
};

const JobGraphBuilder = struct {
    pub fn build(allocator: std.mem.Allocator, workflow: *const ParsedWorkflow, context: ExecutionContext) !JobGraph;
};

const JobGraph = struct {
    nodes: []const JobNode,
    edges: []const JobDependency,
    
    pub fn getExecutionPlan(self: *const JobGraph, allocator: std.mem.Allocator) !ExecutionPlan;
    pub fn getParallelJobs(self: *const JobGraph, allocator: std.mem.Allocator) ![][]const JobNode;
    pub fn validateDependencies(self: *const JobGraph) !void;
};

const ExecutionPlan = struct {
    phases: []const ExecutionPhase,
    total_jobs: u32,
    estimated_duration: ?u32,
    
    const ExecutionPhase = struct {
        jobs: []const JobExecution,
        dependencies_satisfied: bool,
        can_run_parallel: bool,
    };
};
```

</expected_output>

<implementation_steps>

**CRITICAL**: Follow TDD approach. Build on Actions data models. Run `zig build && zig build test` after EVERY change.

**CRITICAL**: Zero tolerance for test failures. Any failing tests indicate YOU caused a regression.

<phase_1>
<title>Phase 1: YAML Parser Foundation (TDD)</title>

1. **Create workflow parser module structure**
   ```bash
   mkdir -p src/actions
   touch src/actions/workflow_parser.zig
   touch src/actions/job_graph.zig
   touch src/actions/expressions.zig
   ```

2. **Write tests for basic YAML parsing**
   ```zig
   test "parses basic workflow structure" {
       const allocator = testing.allocator;
       
       const yaml_content = 
           \\name: Test Workflow
           \\on: push
           \\jobs:
           \\  test:
           \\    runs-on: ubuntu-latest
           \\    steps:
           \\      - name: Checkout
           \\        uses: actions/checkout@v4
           \\      - name: Test
           \\        run: echo "Hello"
       ;
       
       const workflow = try WorkflowParser.parse(allocator, yaml_content, .{});
       defer workflow.deinit(allocator);
       
       try testing.expectEqualStrings("Test Workflow", workflow.name);
       try testing.expect(workflow.triggers.len == 1);
       try testing.expect(workflow.jobs.contains("test"));
       
       const test_job = workflow.jobs.get("test").?;
       try testing.expectEqualStrings("ubuntu-latest", test_job.runs_on);
       try testing.expectEqual(@as(usize, 2), test_job.steps.len);
   }
   
   test "parses complex trigger configurations" {
       const allocator = testing.allocator;
       
       const yaml_content = 
           \\on:
           \\  push:
           \\    branches: [main, develop]
           \\    paths: ['src/**', '!docs/**']
           \\  pull_request:
           \\    types: [opened, synchronize]
           \\  schedule:
           \\    - cron: '0 2 * * *'
           \\  workflow_dispatch:
           \\    inputs:
           \\      environment:
           \\        description: 'Target environment'
           \\        required: true
           \\        default: 'staging'
       ;
       
       const workflow = try WorkflowParser.parse(allocator, yaml_content, .{});
       defer workflow.deinit(allocator);
       
       try testing.expect(workflow.triggers.len == 4);
       
       // Verify push trigger
       var found_push = false;
       for (workflow.triggers) |trigger| {
           if (trigger == .push) {
               try testing.expect(trigger.push.branches.len == 2);
               try testing.expectEqualStrings("main", trigger.push.branches[0]);
               try testing.expect(trigger.push.paths.len == 2);
               found_push = true;
           }
       }
       try testing.expect(found_push);
   }
   ```

3. **Implement basic YAML parsing with proper error handling**
4. **Add trigger configuration parsing**
5. **Test malformed YAML handling and error reporting**

</phase_1>

<phase_2>
<title>Phase 2: Job Definition Parsing (TDD)</title>

1. **Write tests for job parsing**
   ```zig
   test "parses job with strategy matrix" {
       const allocator = testing.allocator;
       
       const yaml_content = 
           \\jobs:
           \\  test:
           \\    runs-on: ubuntu-latest
           \\    strategy:
           \\      matrix:
           \\        node: [16, 18, 20]
           \\        os: [ubuntu-latest, windows-latest]
           \\      fail-fast: false
           \\    steps:
           \\      - uses: actions/setup-node@v3
           \\        with:
           \\          node-version: ${{ matrix.node }}
       ;
       
       const workflow = try WorkflowParser.parse(allocator, yaml_content, .{ .expand_matrices = false });
       defer workflow.deinit(allocator);
       
       const test_job = workflow.jobs.get("test").?;
       try testing.expect(test_job.strategy != null);
       
       const strategy = test_job.strategy.?;
       try testing.expect(strategy.matrix.contains("node"));
       try testing.expect(strategy.matrix.contains("os"));
       try testing.expectEqual(false, strategy.fail_fast);
       
       const node_values = strategy.matrix.get("node").?;
       try testing.expectEqual(@as(usize, 3), node_values.len);
   }
   
   test "parses job dependencies and outputs" {
       const allocator = testing.allocator;
       
       const yaml_content = 
           \\jobs:
           \\  build:
           \\    runs-on: ubuntu-latest
           \\    outputs:
           \\      version: ${{ steps.version.outputs.version }}
           \\      artifact-id: ${{ steps.upload.outputs.artifact-id }}
           \\    steps:
           \\      - id: version
           \\        run: echo "version=1.2.3" >> $GITHUB_OUTPUT
           \\  
           \\  test:
           \\    needs: build
           \\    runs-on: ubuntu-latest
           \\    steps:
           \\      - run: echo "Version is ${{ needs.build.outputs.version }}"
           \\
           \\  deploy:
           \\    needs: [build, test]
           \\    if: github.ref == 'refs/heads/main'
           \\    runs-on: ubuntu-latest
           \\    steps:
           \\      - run: echo "Deploying"
       ;
       
       const workflow = try WorkflowParser.parse(allocator, yaml_content, .{});
       defer workflow.deinit(allocator);
       
       const build_job = workflow.jobs.get("build").?;
       try testing.expect(build_job.outputs.contains("version"));
       try testing.expect(build_job.outputs.contains("artifact-id"));
       
       const test_job = workflow.jobs.get("test").?;
       try testing.expect(test_job.needs.len == 1);
       try testing.expectEqualStrings("build", test_job.needs[0]);
       
       const deploy_job = workflow.jobs.get("deploy").?;
       try testing.expect(deploy_job.needs.len == 2);
       try testing.expect(deploy_job.if_condition != null);
   }
   ```

2. **Implement job definition parsing**
3. **Add strategy matrix parsing**
4. **Test job outputs and dependencies**

</phase_2>

<phase_3>
<title>Phase 3: Matrix Strategy Expansion (TDD)</title>

1. **Write tests for matrix expansion**
   ```zig
   test "expands matrix strategy into individual jobs" {
       const allocator = testing.allocator;
       
       const yaml_content = 
           \\jobs:
           \\  test:
           \\    strategy:
           \\      matrix:
           \\        node: [16, 18]
           \\        os: [ubuntu-latest, windows-latest]
           \\    runs-on: ${{ matrix.os }}
           \\    steps:
           \\      - uses: actions/setup-node@v3
           \\        with:
           \\          node-version: ${{ matrix.node }}
       ;
       
       const workflow = try WorkflowParser.parse(allocator, yaml_content, .{ .expand_matrices = true });
       defer workflow.deinit(allocator);
       
       // Should create 4 jobs: 2 node versions × 2 OS
       const expanded_jobs = try workflow.getExpandedJobs(allocator);
       defer allocator.free(expanded_jobs);
       
       try testing.expectEqual(@as(usize, 4), expanded_jobs.len);
       
       // Verify job names and matrix values
       var combinations = std.StringHashMap(bool).init(allocator);
       defer combinations.deinit();
       
       for (expanded_jobs) |job| {
           const matrix_key = try std.fmt.allocPrint(allocator, "{s}-{s}", .{
               job.matrix_context.get("node").?,
               job.matrix_context.get("os").?,
           });
           defer allocator.free(matrix_key);
           
           try combinations.put(matrix_key, true);
           
           // Verify matrix values are substituted
           try testing.expect(std.mem.indexOf(u8, job.runs_on, "matrix.") == null);
       }
       
       // Should have all combinations
       try testing.expect(combinations.contains("16-ubuntu-latest"));
       try testing.expect(combinations.contains("16-windows-latest"));
       try testing.expect(combinations.contains("18-ubuntu-latest"));
       try testing.expect(combinations.contains("18-windows-latest"));
   }
   
   test "handles matrix include and exclude configurations" {
       const allocator = testing.allocator;
       
       const yaml_content = 
           \\jobs:
           \\  test:
           \\    strategy:
           \\      matrix:
           \\        node: [16, 18, 20]
           \\        os: [ubuntu-latest, windows-latest]
           \\        exclude:
           \\          - node: 16
           \\            os: windows-latest
           \\        include:
           \\          - node: 14
           \\            os: ubuntu-latest
           \\            experimental: true
       ;
       
       const expanded_jobs = try MatrixExpander.expand(allocator, job_definition);
       defer allocator.free(expanded_jobs);
       
       // 3×2 - 1 excluded + 1 included = 6 jobs
       try testing.expectEqual(@as(usize, 6), expanded_jobs.len);
       
       // Verify exclusion worked
       var found_excluded = false;
       for (expanded_jobs) |job| {
           if (std.mem.eql(u8, job.matrix_context.get("node").?, "16") and
               std.mem.eql(u8, job.matrix_context.get("os").?, "windows-latest")) {
               found_excluded = true;
           }
       }
       try testing.expect(!found_excluded);
       
       // Verify inclusion worked
       var found_included = false;
       for (expanded_jobs) |job| {
           if (job.matrix_context.contains("experimental")) {
               found_included = true;
               try testing.expectEqualStrings("true", job.matrix_context.get("experimental").?);
           }
       }
       try testing.expect(found_included);
   }
   ```

2. **Implement matrix strategy expansion**
3. **Add matrix include/exclude support**
4. **Test matrix variable substitution**

</phase_3>

<phase_4>
<title>Phase 4: Expression Evaluation and Context (TDD)</title>

1. **Write tests for expression evaluation**
   ```zig
   test "evaluates GitHub context expressions" {
       const allocator = testing.allocator;
       
       const context = ExecutionContext{
           .github = .{
               .ref = "refs/heads/main",
               .sha = "abc123def456",
               .actor = "user123",
               .event_name = "push",
           },
           .env = std.StringHashMap([]const u8).init(allocator),
           .vars = std.StringHashMap([]const u8).init(allocator),
       };
       defer context.deinit();
       
       const expr_evaluator = ExpressionEvaluator.init(allocator, &context);
       
       // Test simple context access
       const ref_result = try expr_evaluator.evaluate("github.ref");
       try testing.expectEqualStrings("refs/heads/main", ref_result);
       
       // Test conditional expressions
       const cond_result = try expr_evaluator.evaluate("github.ref == 'refs/heads/main'");
       try testing.expect(cond_result.boolean);
       
       // Test complex expressions
       const complex_result = try expr_evaluator.evaluate("startsWith(github.ref, 'refs/heads/') && github.actor != 'dependabot'");
       try testing.expect(complex_result.boolean);
   }
   
   test "substitutes expressions in workflow content" {
       const allocator = testing.allocator;
       
       const template = "Version: ${{ env.VERSION }}, Branch: ${{ github.ref }}";
       const context = ExecutionContext{
           .env = blk: {
               var env = std.StringHashMap([]const u8).init(allocator);
               try env.put("VERSION", "1.2.3");
               break :blk env;
           },
           .github = .{
               .ref = "refs/heads/develop",
           },
       };
       defer context.deinit();
       
       const substituted = try ExpressionEvaluator.substitute(allocator, template, &context);
       defer allocator.free(substituted);
       
       try testing.expectEqualStrings("Version: 1.2.3, Branch: refs/heads/develop", substituted);
   }
   ```

2. **Implement GitHub Actions expression parser**
3. **Add context variable substitution**
4. **Test complex conditional expressions**

</phase_4>

<phase_5>
<title>Phase 5: Job Graph Construction and Dependency Resolution (TDD)</title>

1. **Write tests for job graph construction**
   ```zig
   test "builds job dependency graph correctly" {
       const allocator = testing.allocator;
       
       const workflow = try createTestWorkflow(allocator, 
           \\jobs:
           \\  build:
           \\    runs-on: ubuntu-latest
           \\    steps: [{run: "make build"}]
           \\  test-unit:
           \\    needs: build
           \\    runs-on: ubuntu-latest  
           \\    steps: [{run: "make test-unit"}]
           \\  test-integration:
           \\    needs: build
           \\    runs-on: ubuntu-latest
           \\    steps: [{run: "make test-integration"}]
           \\  deploy:
           \\    needs: [test-unit, test-integration]
           \\    runs-on: ubuntu-latest
           \\    steps: [{run: "make deploy"}]
       );
       defer workflow.deinit(allocator);
       
       const job_graph = try JobGraphBuilder.build(allocator, &workflow, test_context);
       defer job_graph.deinit(allocator);
       
       try testing.expectEqual(@as(usize, 4), job_graph.nodes.len);
       
       // Verify dependency edges
       const build_node = job_graph.getNode("build").?;
       const test_unit_node = job_graph.getNode("test-unit").?;
       const test_integration_node = job_graph.getNode("test-integration").?;
       const deploy_node = job_graph.getNode("deploy").?;
       
       // Build should have no dependencies
       try testing.expectEqual(@as(usize, 0), build_node.dependencies.len);
       
       // Test jobs should depend on build
       try testing.expectEqual(@as(usize, 1), test_unit_node.dependencies.len);
       try testing.expectEqualStrings("build", test_unit_node.dependencies[0]);
       
       // Deploy should depend on both test jobs
       try testing.expectEqual(@as(usize, 2), deploy_node.dependencies.len);
   }
   
   test "detects circular dependencies" {
       const allocator = testing.allocator;
       
       const workflow = try createTestWorkflow(allocator,
           \\jobs:
           \\  job-a:
           \\    needs: job-b
           \\    runs-on: ubuntu-latest
           \\    steps: [{run: "echo a"}]
           \\  job-b:
           \\    needs: job-c
           \\    runs-on: ubuntu-latest
           \\    steps: [{run: "echo b"}]
           \\  job-c:
           \\    needs: job-a
           \\    runs-on: ubuntu-latest
           \\    steps: [{run: "echo c"}]
       );
       defer workflow.deinit(allocator);
       
       try testing.expectError(error.CircularDependency, 
           JobGraphBuilder.build(allocator, &workflow, test_context));
   }
   ```

2. **Implement job graph construction**
3. **Add dependency validation and cycle detection**
4. **Test complex dependency scenarios**

</phase_5>

<phase_6>
<title>Phase 6: Execution Plan Generation (TDD)</title>

1. **Write tests for execution planning**
   ```zig
   test "generates optimal execution plan" {
       const allocator = testing.allocator;
       
       const job_graph = try createTestJobGraph(allocator, complex_workflow);
       defer job_graph.deinit(allocator);
       
       const execution_plan = try job_graph.getExecutionPlan(allocator);
       defer execution_plan.deinit(allocator);
       
       // Verify execution phases
       try testing.expect(execution_plan.phases.len >= 3);
       
       // Phase 1: Jobs with no dependencies
       const phase1 = execution_plan.phases[0];
       try testing.expect(phase1.can_run_parallel);
       try testing.expect(containsJob(phase1.jobs, "build"));
       
       // Phase 2: Jobs depending on phase 1
       const phase2 = execution_plan.phases[1];
       try testing.expect(phase2.can_run_parallel);
       try testing.expect(containsJob(phase2.jobs, "test-unit"));
       try testing.expect(containsJob(phase2.jobs, "test-integration"));
       
       // Final phase: Jobs depending on previous phases
       const final_phase = execution_plan.phases[execution_plan.phases.len - 1];
       try testing.expect(containsJob(final_phase.jobs, "deploy"));
   }
   ```

2. **Implement execution plan generation**
3. **Add parallelization optimization**
4. **Test execution plan validation**

</phase_6>

<phase_7>
<title>Phase 7: Validation and Error Reporting (TDD)</title>

1. **Write tests for workflow validation**
2. **Implement comprehensive validation rules**
3. **Add detailed error reporting with line numbers**
4. **Test edge cases and malformed workflows**

</phase_7>

</implementation_steps>

</detailed_specifications>

<quality_assurance>

<testing_requirements>

- **YAML Compatibility**: Test with real GitHub Actions workflows
- **Matrix Expansion**: Large matrix combinations and performance testing
- **Expression Evaluation**: Complex GitHub Actions expressions and functions
- **Graph Algorithms**: Dependency resolution and cycle detection
- **Memory Management**: Large workflow parsing without memory leaks
- **Error Handling**: Comprehensive error scenarios and recovery

</testing_requirements>

<success_criteria>

1. **All tests pass**: Complete workflow parsing functionality
2. **GitHub compatibility**: Support 95%+ of GitHub Actions syntax
3. **Performance**: Parse complex workflows in under 100ms
4. **Memory efficiency**: Minimal allocation overhead
5. **Error reporting**: Clear, actionable error messages
6. **Validation**: Comprehensive syntax and semantic validation
7. **Graph optimization**: Efficient parallel execution planning

</success_criteria>

</quality_assurance>

<reference_implementations>

- **GitHub Actions**: Official workflow syntax specification
- **act**: Local GitHub Actions runner implementation
- **nektos/act**: Docker-based GitHub Actions emulator
- **GitLab CI**: Pipeline parsing and job generation patterns

</reference_implementations>