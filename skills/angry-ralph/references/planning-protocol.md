# Planning Protocol: Decompose + Plan

Reference protocol for Phase 1 (DECOMPOSE) and Phase 2 (PLAN) of the angry-ralph workflow.

---

## Phase 1: DECOMPOSE

### Read and Analyze the Spec

1. Read the input spec file provided via the `@file.md` argument in its entirety.
2. Identify the core problem domain, target tech stack, key features, and any constraints stated in the spec.
3. Note ambiguities, missing details, and implicit assumptions that require clarification.

### Interview the User

4. Ask clarifying questions **one at a time** via `AskUserQuestion`. Do not batch multiple questions into a single prompt.
5. Focus each question on a single topic: a missing requirement, an ambiguous constraint, or a design decision that affects architecture.
6. Continue asking until all ambiguities identified in step 3 are resolved.
7. Write the full interview transcript (questions and answers) to `planning/angry-ralph-interview.md`.

### Determine Decomposition

8. Evaluate whether the spec requires splitting into multiple planning units. Apply these heuristics -- split when **any** of the following hold:
   - The spec spans **different domains** (e.g., frontend + backend + infrastructure).
   - Components are **independently deployable** (separate services, packages, or repos).
   - Components use **different tech stacks** (e.g., Python service + TypeScript UI).
   - A single planning unit would require an estimated **>500 lines of code**.

9. **If splitting**: create a planning unit manifest listing each unit with:
   - Unit name (kebab-case identifier)
   - Brief scope description (1-2 sentences)
   - Tech stack
   - Dependencies on other units (by name)
   - Dependency ordering (units with no dependencies first)

   Write the manifest to the top of `planning/angry-ralph-plan.md` under a `## Planning Units` header.

10. **If not splitting**: treat the entire spec as a single planning unit named after the project. Skip the manifest and proceed directly to Phase 2.

---

## Phase 2: PLAN

### Write the Implementation Plan

For each planning unit (or the single unit if no split), produce a detailed implementation plan with the following structure.

#### Architecture Overview

11. Write 2-3 sentences summarizing the overall architecture: what the system does, how components connect, and what the deployment model looks like.

#### Components and Responsibilities

12. List every component (module, service, class, script) with:
    - Name
    - Single-sentence responsibility
    - Public interface (key functions, endpoints, or exports)

#### Data Flow

13. Describe how data moves between components. Include:
    - Entry points (user input, API calls, file reads)
    - Transformation steps
    - Storage or persistence points
    - Output points (responses, file writes, side effects)

#### Error Handling Strategy

14. Define the error handling approach:
    - Error categories (validation, runtime, external service, transient)
    - Propagation strategy (throw, return Result, error codes)
    - User-facing error messages vs. internal logging
    - Retry policy for transient failures

#### Testing Strategy

15. Specify the testing approach for the entire plan:
    - Test framework and runner command (e.g., `pytest`, `npm test`, `go test ./...`)
    - Expected test coverage target (minimum 80% line coverage)
    - Test categories: unit tests, integration tests, end-to-end tests
    - What to mock vs. what to test against real implementations

### Section Breakdown

16. Divide the plan into numbered implementation sections. Mark each section with a header in this exact format:

    ```
    ## Section 1: <Name>
    ## Section 2: <Name>
    ## Section 3: <Name>
    ```

17. Each section must include:
    - **Scope**: what files and components this section creates or modifies.
    - **Dependencies**: which prior sections must be complete first.
    - **Test data contracts**: Each test specified as a YAML data contract with `input`, `expected_output` or `expected_error`. No language-specific syntax — the implementation subagent translates contracts into the project's test framework. Each contract must include:
      - Test name (becomes the test function name)
      - `input`: exact arguments/payloads
      - `expected_output` or `expected_error`: exact return value or error type+message
      - Runner command

      Example of a GOOD test contract:
      ```yaml
      test_login_rejects_invalid_password:
        input:
          function: auth.login
          args: ["alice", "wrong-password"]
        expected_error:
          type: AuthError
          message: "invalid credentials"
        run: pytest tests/test_auth.py::test_login_rejects_invalid_password
      ```

      Example of a BAD test spec (vague, allows stubs to pass):
      ```
      Test that login works correctly with invalid passwords.
      ```

      The implementation subagent MUST translate these contracts into real tests. The mechanical gates in Phase 5 verify that every contract's test function name exists in the test files.

    - **Acceptance criteria**: concrete conditions (all tests pass, specific behavior verified) that mark the section as complete.

18. Order sections so that foundational components (utilities, data models, core logic) come before components that depend on them (API layers, UI, orchestration).

### Write Output Files

19. Write the complete plan to `planning/angry-ralph-plan.md`.
20. Write a synthesized specification (incorporating all interview answers and resolved ambiguities) to `planning/angry-ralph-spec.md`. The synthesized spec serves as the single source of truth for all subsequent phases.

### Plan Quality Checklist

Before marking the plan as complete, verify:

- [ ] Every component listed in the architecture has at least one section that implements it.
- [ ] Every section has test data contracts with exact input/expected_output/expected_error (not prose descriptions).
- [ ] Section dependencies form a valid DAG (no circular dependencies).
- [ ] The test runner command is specified and consistent across all sections.
- [ ] Error handling strategy covers all component boundaries.
- [ ] The synthesized spec in `angry-ralph-spec.md` reflects all interview answers.
