# SIS 3 – Orders system as code (CAD, Fall 2026)

An order API in a container publishes an `OrderPlaced` event. EventBridge routes it to an SQS queue
(with a dead-letter queue), and an idempotent Lambda consumer stores each order once in DynamoDB.
Everything is described in CloudFormation / SAM templates – nothing is created in the console.

```
client -> ALB (public subnets) -> ECS Fargate orders-api x2 (private subnets)
       -> EventBridge bus -> rule OrderPlaced -> SQS queue (DLQ, maxReceiveCount 5)
       -> Lambda consumer (dedup key: orderId) -> DynamoDB
```

## Stacks
| Stack | Template | What it creates |
|---|---|---|
| `<prefix>-network` | `infra/network.yaml` | VPC, 2 public + 2 private subnets in 2 AZs, 1 NAT gateway |
| `<prefix>-data` | `infra/data.yaml` | DynamoDB table, EventBridge bus + rule, SQS queue + DLQ, Lambda consumer, alarms |
| `<prefix>-ecr` | `infra/ecr.yaml` | ECR repository: immutable tags, scan on push, lifecycle policy |
| `<prefix>-app` | `infra/app.yaml` | ECS cluster, Fargate service (2 tasks), ALB, execution role + task role, log group (14 days) |

Stacks are linked with CloudFormation exports (`<prefix>-network-VpcId`, `<prefix>-data-BusArn`, ...).

## Deploy (one command)
Requirements: AWS CLI, SAM CLI and Docker (AWS CloudShell has all three), region `ap-southeast-2`.

```bash
./deploy.sh sis3 dev
```
`prefix` (default `sis3`) names all stacks, so a second independent copy is just `./deploy.sh sis3b dev`.
`env` is `dev` or `prod` (task size comes from a mapping in `infra/app.yaml`).
The image tag is the git commit SHA (or a timestamp outside git) – never `latest`.

## Test
```bash
./test.sh sis3
```
Checks healthy targets, load balancing, a new order, a duplicate order (stored once),
a bad event (ends in the DLQ after 5 attempts and raises the DLQ alarm) and a 404.

## Lint
```bash
pip install --user cfn-lint && cfn-lint infra/*.yaml
```

## Delete
```bash
./destroy.sh sis3
```
The NAT gateway and the ALB cost about $2.5 per day – delete the stacks after the demo.

## No secrets
The templates contain no passwords or keys. The container and the Lambda function get temporary
credentials from their IAM roles.
