# Lambda API Project

**Live API:** https://x9xy59quyh.execute-api.eu-central-1.amazonaws.com/quote
**Live demo page:** https://ralso11.github.io/lambda-api-project/

📖 Want the full, beginner-friendly walkthrough of every step, command,
and decision made in this project? See
[PROJECT_GUIDE.md](./PROJECT_GUIDE.md).

## What is this project, in one sentence?

A tiny serverless API — visit a URL, get back a random quote as JSON —
built entirely with code (Terraform) and deployed automatically through
a CI/CD pipeline, with a small demo webpage on top to display it nicely.

## Why this project exists

This is the second project in a small portfolio series (the first being
[terraform-cicd-project](https://github.com/Ralso11/terraform-cicd-project)),
built specifically to learn **serverless architecture** — a different,
heavily in-demand AWS pattern from the first project's static-site setup.

Two new concepts this project adds on top of the first:
1. **Serverless compute (AWS Lambda):** code that only runs exactly when
   triggered, with no server sitting idle in between.
2. **Least-privilege IAM in practice:** writing a custom, scoped
   permissions policy by hand — and dealing with the real trial-and-error
   that comes with it (see Problems & Fixes).

## Architecture

```
Browser → GitHub Pages (demo page) → fetch() → API Gateway → Lambda → JSON response
```

- **AWS Lambda** — a small Python function that picks a random quote and
  returns it. Only runs (and is only billed) for the exact moment it's
  triggered.
- **API Gateway** — the public "front door" that turns an HTTP request
  (`GET /quote`) into a trigger for the Lambda function.
- **IAM role (for the Lambda function itself)** — grants the function
  permission to run and write logs, nothing more.
- **CORS configuration** — a browser security rule that had to be
  explicitly allowed on the API, so a webpage hosted somewhere else
  (GitHub Pages) is permitted to call it.
- **GitHub Pages** — hosts the small demo frontend for free, completely
  separate from AWS.

## Problems & fixes — quick reference

| Problem | Why it happened | How it was fixed |
|---|---|---|
| Several `AccessDenied` errors during `terraform plan`/`apply` (`ListRolePolicies`, `ListVersionsByFunction`, `GetFunctionCodeSigningConfig`, etc.) | A custom, tightly-scoped IAM policy was written by hand for the deploying user, but AWS Lambda performs many undocumented internal "read check" calls that a hand-written policy easily misses | Kept a tightly-scoped custom policy only for the highest-risk part (IAM role creation + S3 state access), and used AWS's managed `AWSLambda_FullAccess` + `AmazonAPIGatewayAdministrator` policies for Lambda/API Gateway themselves — a deliberate, defensible real-world tradeoff (see PROJECT_GUIDE.md for the full reasoning) |
| GitHub Pages didn't show the frontend folder as an option | GitHub Pages' "deploy from a branch" only supports the repo root or a folder literally named `docs` — not any custom name | Renamed the `frontend/` folder to `docs/` |
| A repeated terminal paste got main.tf/providers.tf/variables.tf overwritten as empty files | A stuck terminal loop kept re-running the same heredoc paste, catching some files mid-write | Verified each file individually with `cat`, and rewrote only the ones that came back empty |

## How to reproduce this project

1. Install Git and Terraform.
2. Create a GitHub repo, clone it locally.
3. Write the Lambda function code (`lambda/handler.py`).
4. Write Terraform files (`providers.tf`, `variables.tf`, `main.tf`,
   `outputs.tf`, `backend.tf` pointing at a shared state bucket).
5. Create a dedicated IAM user for deployment. Consider: managed
   policies for the service itself (Lambda, API Gateway), a tightly
   scoped custom policy for IAM role creation and state bucket access.
6. Store the keys as GitHub Secrets, set up a protected `production`
   environment with required reviewers.
7. Write the GitHub Actions pipeline (`plan` always runs, `apply` waits
   for approval).
8. Push, approve, and test the live API URL from the pipeline output.
9. (Optional) Add CORS to the API and a small static frontend, hosted
   free via GitHub Pages.

## What's next (possible future additions)

- [ ] Add a second route (e.g. `POST /quotes` to add new quotes,
      backed by DynamoDB).
- [ ] Add request throttling / a usage plan on API Gateway.
- [ ] Add automated tests for the Lambda function before deploy.
