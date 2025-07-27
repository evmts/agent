# Deploy Plue Application to AWS with Terraform

Create a complete Terraform infrastructure setup to deploy the Plue application (git wrapper with web UI and REST API) to AWS. The application consists of a PostgreSQL database, Zig-based API server, and React web frontend.

## Architecture Overview

The deployment should include:
- VPC with public and private subnets across multiple AZs
- RDS PostgreSQL instance in private subnets
- ECS Fargate for running containerized services
- Application Load Balancer for routing traffic
- EFS for persistent file storage (git repositories)
- ECR for Docker image registry
- Secrets Manager for sensitive configuration

## Directory Structure

Reorganize the project as follows:

```
plue/
├── infra/
│   ├── docker/
│   │   ├── docker-compose.yml
│   │   ├── Dockerfile
│   │   └── Dockerfile.healthcheck
│   ├── environments/
│   │   ├── dev/
│   │   │   ├── main.tf
│   │   │   ├── outputs.tf
│   │   │   ├── providers.tf
│   │   │   ├── variables.tf
│   │   │   └── versions.tf
│   │   └── production/
│   │       ├── main.tf
│   │       ├── outputs.tf
│   │       ├── providers.tf
│   │       ├── variables.tf
│   │       └── versions.tf
│   ├── modules/
│   │   ├── network/
│   │   │   ├── main.tf
│   │   │   ├── outputs.tf
│   │   │   ├── variables.tf
│   │   │   └── versions.tf
│   │   ├── database/
│   │   │   ├── main.tf
│   │   │   ├── outputs.tf
│   │   │   ├── variables.tf
│   │   │   └── versions.tf
│   │   ├── api-server/
│   │   │   ├── main.tf
│   │   │   ├── outputs.tf
│   │   │   ├── variables.tf
│   │   │   └── versions.tf
│   │   ├── web-app/
│   │   │   ├── main.tf
│   │   │   ├── outputs.tf
│   │   │   ├── variables.tf
│   │   │   └── versions.tf
│   │   ├── storage/
│   │   │   ├── main.tf
│   │   │   ├── outputs.tf
│   │   │   ├── variables.tf
│   │   │   └── versions.tf
│   │   └── load-balancer/
│   │       ├── main.tf
│   │       ├── outputs.tf
│   │       ├── variables.tf
│   │       └── versions.tf
│   └── README.md
```

## Implementation Requirements

### 1. Move Docker Files
- Move `Dockerfile`, `Dockerfile.healthcheck`, and `docker-compose.yml` to `infra/docker/`
- Update any references to these files in the codebase

### 2. Network Module (`modules/network/`)
- Create VPC with CIDR 10.0.0.0/16
- 2 public subnets and 2 private subnets across different AZs
- Internet Gateway and NAT Gateway for outbound traffic
- Route tables and associations

### 3. Database Module (`modules/database/`)
- RDS PostgreSQL 16 instance (db.t3.micro for cost efficiency)
- Place in private subnets with security group allowing access from ECS tasks
- Enable automated backups with 7-day retention
- Create subnet group for multi-AZ deployment readiness

### 4. Storage Module (`modules/storage/`)
- EFS filesystem for storing git repositories
- Mount targets in each private subnet
- Security group allowing NFS access from ECS tasks
- Access points for different environments

### 5. API Server Module (`modules/api-server/`)
- ECS task definition for the Zig API server
- Fargate service with desired count of 1
- Environment variables from Secrets Manager
- EFS volume mount for git repository storage
- Health check configuration
- Auto-scaling policies (min: 1, max: 3)

### 6. Web App Module (`modules/web-app/`)
- ECS task definition for the React frontend
- Fargate service with desired count of 1
- Environment variables for API endpoint
- Health check configuration
- Auto-scaling policies (min: 1, max: 3)

### 7. Load Balancer Module (`modules/load-balancer/`)
- Application Load Balancer in public subnets
- Target groups for API (port 8000) and web (port 80)
- Path-based routing rules:
  - `/api/*` → API server target group
  - `/*` → Web app target group
- SSL certificate (use ACM or self-signed for dev)

### 8. Environment Configurations
- **Dev environment**: Minimal resources, single instance of each service
- **Production environment**: Multi-AZ RDS, higher ECS task resources, CloudWatch alarms

### 9. Database Migration
- Create a one-time ECS task for database migrations
- Run after RDS is created but before services start
- Use the Python migration script from `scripts/migrate.py`

### 10. Infrastructure README
Create `infra/README.md` with:
- Mermaid diagram showing AWS architecture
- Prerequisites (AWS CLI, Terraform, Docker)
- Step-by-step deployment instructions
- Environment variable documentation
- Troubleshooting guide
- Cost estimates

## Technical Specifications

### Terraform Requirements
- Use Terraform 1.5+ with AWS provider 5.0+
- Implement remote state backend (S3 + DynamoDB)
- Use data sources for AMIs and availability zones
- Tag all resources consistently

### Security Requirements
- All secrets in AWS Secrets Manager
- Least-privilege IAM roles for ECS tasks
- Security groups with minimal required access
- Enable VPC flow logs
- No hardcoded credentials

### Monitoring and Logging
- CloudWatch log groups for ECS tasks
- Basic CloudWatch alarms for service health
- Enable Container Insights for ECS

### Cost Optimization
- Use Fargate Spot for dev environment
- Set up lifecycle policies for ECR images
- Use single NAT Gateway for dev environment

## Deliverables

1. Complete Terraform module structure with all files
2. Working configurations for both dev and production environments
3. Comprehensive README with architecture diagram
4. All Docker files moved to new location
5. Updated references in the codebase to new Docker file locations

## Comment Guidelines

Follow the comment philosophy from CLAUDE.md:
- Only add comments that provide context or explain WHY
- Document AWS-specific constraints or requirements
- Explain non-obvious configuration choices
- Never comment what the code clearly shows

Begin by analyzing the current docker-compose.yml to understand service dependencies and requirements, then implement the Terraform infrastructure accordingly.