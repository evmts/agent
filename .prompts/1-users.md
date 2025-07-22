# Init cli

## Task Definition

Initialize the postgres database access object in zig

## Context & Constraints

### Technical Requirements

- **Language/Framework**: Zig - https://ziglang.org/documentation/master/
- **Dependencies**: zig pg library https://github.com/karlseguin/pg.zig , Docker
- **Performance**: n/a
- **Compatibility**: n/a

### Business Context

This is a brand new repo that will build an application named plue. This is a git wrapper application modeled after graphite and gitea.

## Detailed Specifications

### Input

I will give you the sql specs and your job is to implement the entire data access object

### Expected Output

I expect working setup in docker that given postgres credentials spins up our zig app and connects to postgres.

### Steps

There are many steps to this task that should be followed. **IMPORTANT** Never move on to the next step until you have verified the previous step worked and have emoji conventional committed the change. Each step has substeps.

## Step 0: Docker

### Context

We currently have a native app that spins up with the `run` command of our zig cli (written with zig clap in previous prompt). This native app is using webui to run a native zig app. The app itself is a solid.js spa.

Take Action: Read the build.zig to see how we build it

### Substeps

1. Add Dockerfile

Let's try using alpine

```docker
FROM alpine:3.13 as builder

RUN apk update && \
    apk add \
        curl \
        xz

ARG ZIGVER
RUN mkdir -p /deps
WORKDIR /deps
RUN curl https://ziglang.org/deps/zig+llvm+lld+clang-$(uname -m)-linux-musl-$ZIGVER.tar.xz  -O && \
    tar xf zig+llvm+lld+clang-$(uname -m)-linux-musl-$ZIGVER.tar.xz && \
    mv zig+llvm+lld+clang-$(uname -m)-linux-musl-$ZIGVER/ local/

FROM alpine:3.13
RUN apk --no-cache add \
      libc-dev \
      xz \
      samurai \
      git \
      cmake \
      py3-pip \
      perl-utils \
      jq \
      curl && \
    pip3 install s3cmd


// FINISH ME
...
COPY --from=builder /deps/local/ /deps/local/
...
```

This Dockerfile should replace FINISHME with building the zig project completely in a builder stage followed by a 2nd and 3rd stage. The 2nd stage should expose the spa src/gui/dist as a web app. The 3rd stage should expose the zig cli.

Add a docker-compose to run our docker app. It should spin up 4 services

1. Postgres
2. A placeholder for what will later be a api server (currently doesn't exist)
3. The web app

Verify the entire docker-compose spins up as expected. To do this you should add a healthcheck to postgres. And the api server should run a simple python script in scripts/\* that verifies the spa is rendering. Try to make this test as simple as possible by inspecting the html and verifying mostly headers like that the title is Plue (fix if title is not plue)

4. Lastly reread the prompt and look at your code and do a self code review.
5. Polish and fix the things you see in code review improving the code before committing
6. Verify the app still works as expected
7. Once this is working please emoji conventionalcommit

## Step 1: Install minimal crud server

- Read CLAUDE.md in full to remind yourself of best practices
- Read httpz README.md https://github.com/karlseguin/http.zig?tab=readme-ov-file
- Install dependency and add to build.zig
- Add minimal httpz server via the cli clap app
- Add simple unit tests for it and verify the tests pass
- Add it to docker-compose replacing our previous placeholder
- Verify server returns hello world in our python script healthcheck

After verifying all services spin up successfully again emoji conventional commit

- Lastly reread the prompt and look at your code and do a self code review.
- Polish and fix the things you see in code review improving the code before committing
- Verify the app still works as expected
- Once this is working please emoji conventionalcommit

## Step 2: Add Postgres database

- Read zig pg.zig README.md https://github.com/karlseguin/pg.zig
- zig fetch to install this dependency. We are using stable release
- Read zig pg.zig examples (Linked in README.md)
- Implement a basic hello world database. Setup python scripts to handle database migrations and stuff
- Add a DataAccessObject struct. It should connect to database with init. Don't pass allocator into constructor. Instead pass allocator in on individual methods if they need one so we are explicit. Add this rule to CLAUDE.md actually as a best practice.
- Add basic crud functionality for reading and writing a name to the users table in the database
- Add unit tests in same file e2e testing this feature. To run these tests you will need the database running so go ahead and add our tests as a target in the docker-compose
- Add a docker-compose step that runs db migrations
- Lastly reread the prompt and look at your code and do a self code review.
- Polish and fix the things you see in code review improving the code before committing
- Verify the app still works as expected
- Once this is working please emoji conventionalcommit

## Step 3: Connect db to server

- Connect the hello world db to the server. Allow user to change their name
- Update unit tests and healthcheck
- Verify in a health check that we can both read and write to this db through the server healthcheck

- Lastly reread the prompt and look at your code and do a self code review.
- Polish and fix the things you see in code review improving the code before committing
- Verify the app still works as expected
- Once this is working please emoji conventionalcommit

## Code Style & Architecture

### Design Patterns

- Write idiomatic performant zig according to CLAUDE.md
- Keep file structure flat with all cmds just in cmd
- Make commmands easily testable and agnostic to the cli application logic keep all cli specific logic in the main entrypoint

### Code Organization

```
project/
├── build.zig
├── CLAUDE.md
├── CONTRIBUTING.md
|-- scripts/*.py
|-- Dockerfile and docker-compose.yml
├── src/
│   ├── main.zig
│   ├── commands/
    |-- database/
    |-- server/
```

### Success criteria

All steps completed with pr in production ready state
No hacks or workarounds
