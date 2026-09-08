# The Complete Guide to This Project
### (Written so anyone, even with zero background, can understand it)

This is the second project in a small portfolio series. It assumes you
already understand the very basics covered in the first project's guide
(Git, GitHub, Terraform, CI/CD) — if any of those feel unfamiliar, read
that guide first. This one focuses on what's *new* here: serverless
computing and hands-on IAM permission scoping.

---

## Part 1 — What is "serverless," really?

Normally, running code online means renting a server that's "on" all the
time, waiting for requests — like leaving a shop open 24/7 even if no
customers show up all night. You pay for that shop being open, whether
anyone visits or not.

**Serverless (AWS Lambda) works differently:** your code sits completely
inactive until the exact moment someone requests it. AWS then
instantly "spins it up," runs it, returns the result, and shuts it back
down — all in a fraction of a second. You're only ever billed for that
tiny slice of actual execution time, not for idle waiting.

This is ideal for small, spiky, or infrequent workloads — like a small
API that might get a handful of requests a day.

## Part 2 — What this project builds

In one sentence: **visit a specific web address, and instead of a
webpage, you get back a random quote as structured data (JSON)** —
generated fresh, on demand, by a tiny piece of code that only exists for
that moment.

```
Browser  ->  GitHub Pages (demo page)
                    |
                    | fetch() — a JavaScript request
                    v
              API Gateway  (the "front door")
                    |
                    | triggers
                    v
                 Lambda  (runs the Python code, returns a quote)
```

### Why an API Gateway in front of Lambda, instead of connecting directly?

Lambda functions aren't directly reachable from the internet by default
— they need something to translate a normal web request (a URL, an HTTP
method like GET) into a Lambda "trigger event." API Gateway is that
translator. It's also where you'd add things like rate limiting,
API keys, or multiple routes later, without touching the Lambda code
itself.

## Part 3 — The Terraform files, explained

Same four-file pattern as project 1, plus one new file:

| File | What's new here vs project 1 |
|---|---|
| `providers.tf` | Adds a second provider, `archive` — a small helper that automatically zips up the Lambda code into the format AWS requires |
| `variables.tf` | Same purpose (reusable settings), nothing new conceptually |
| `main.tf` | The big one — see below |
| `outputs.tf` | Prints the live API URL after deploying, instead of a website address |
| `backend.tf` | Reuses the *same* shared state bucket from project 1, but with a different `key` (like a separate folder inside it), so each project's memory stays independent |

### `main.tf`, piece by piece

**Packaging the code:**
```hcl
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/../lambda/handler.py"
  output_path = "${path.module}/lambda.zip"
}
```
AWS Lambda expects code as a zip file, not a raw `.py` file. This
automatically zips it every time it changes, so you never do this
manually.

**The IAM role the function runs as:**
```hcl
resource "aws_iam_role" "lambda_exec" {
  name = "${var.project_name}-lambda-role"
  assume_role_policy = jsonencode({ ... "Service" = "lambda.amazonaws.com" ... })
}
```
Every Lambda function needs an *identity* to run as — this role is that
identity. The `assume_role_policy` specifically says "only the Lambda
service itself is allowed to use this identity," so nothing else in AWS
could impersonate it.

**Its one permission:**
```hcl
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
```
This grants exactly one thing: permission to write logs to CloudWatch
(AWS's logging service), so you can debug it later. Nothing more —
another example of least privilege.

**The function itself:**
```hcl
resource "aws_lambda_function" "quote_api" {
  handler = "handler.handler"
  runtime = "python3.12"
  ...
}
```
`handler.handler` means: "in the file `handler.py`, call the function
named `handler`." This has to match exactly what's in your code.

**API Gateway + connecting it to Lambda:**
```hcl
resource "aws_apigatewayv2_api" "quote_api" { ... }
resource "aws_apigatewayv2_integration" "lambda" { ... }
resource "aws_apigatewayv2_route" "get_quote" {
  route_key = "GET /quote"
  ...
}
resource "aws_apigatewayv2_stage" "default" { auto_deploy = true }
```
This creates the public API, connects it to the Lambda function, and
defines that visiting `/quote` with a `GET` request is what triggers it.
`auto_deploy = true` means changes go live automatically — no separate
manual publish step.

**The final permission — the one that's easy to forget:**
```hcl
resource "aws_lambda_permission" "api_gw" {
  action    = "lambda:InvokeFunction"
  principal = "apigateway.amazonaws.com"
  source_arn = "${aws_apigatewayv2_api.quote_api.execution_arn}/*/*"
}
```
Without this, API Gateway would try to call the Lambda function and get
refused — the exact same "key exists but isn't registered with the
lock" issue from project 1's CloudFront/S3 bug. This time, it was
included correctly from the start, having learned that lesson already.

## Part 4 — The IAM permissions story (the real learning moment)

This is worth reading carefully, because it's the most realistic
"engineering judgment" part of this whole project.

### What we tried first: a fully custom, scoped policy

The instinct was: write a custom IAM policy that lists exactly the
actions needed (create this Lambda, create this IAM role, read/write
this state bucket) and nothing else — the "textbook correct" approach.

### What actually happened

Every time the pipeline ran, it failed with a **new** `AccessDenied`
error — not because the policy was wrong, but because Terraform (and
AWS Lambda specifically) performs many small, undocumented "read check"
API calls behind the scenes to keep its records in sync
(`ListRolePolicies`, `ListVersionsByFunction`,
`GetFunctionCodeSigningConfig`, and more). None of these are obviously
listed anywhere as "required" — you only discover them one at a time,
by hitting the error.

### The decision: a pragmatic, real-world tradeoff

Instead of continuing to chase permissions one at a time indefinitely,
the fix was to split the approach by **actual risk level**:

- **For Lambda and API Gateway:** use AWS's own managed policies
  (`AWSLambda_FullAccess`, `AmazonAPIGatewayAdministrator`). These
  services are naturally *contained* — having full access to manage
  Lambda functions or API Gateway configurations cannot be used to
  escalate privileges or affect anything outside those services.
- **For IAM (creating roles) and S3 (state storage):** kept a tightly
  scoped custom policy. This matters because IAM is the one area where
  broad access is genuinely dangerous — broad IAM permissions could let
  someone create new users, grant themselves admin rights, or otherwise
  escalate privileges well beyond the project's intended scope.

**The principle:** least privilege matters most exactly where the risk
of misuse is highest. Being pragmatic about lower-risk, naturally
contained services (using their managed policies) while staying strict
about genuinely dangerous permissions (IAM) is a real, defensible
engineering decision — not a shortcut. This is worth saying explicitly
in an interview if asked about this project.

## Part 5 — CORS, explained simply

After deploying, the demo webpage (hosted on GitHub Pages) needed to
call the API (hosted on AWS) — two completely different addresses
talking to each other. Browsers have a built-in security rule called
**CORS (Cross-Origin Resource Sharing)** that blocks a webpage from
calling an API on a different domain, *unless* that API explicitly says
"yes, I allow requests from other websites."

The fix was adding this to the API Gateway resource:
```hcl
cors_configuration {
  allow_origins = ["*"]
  allow_methods = ["GET"]
  allow_headers = ["content-type"]
}
```
This says "any website (`*`) may make GET requests to this API." Using
`*` (any origin) is reasonable here because this API is public,
read-only, and requires no login — a real API handling private data
would instead restrict `allow_origins` to one specific, trusted domain.

## Part 6 — GitHub Pages, and the folder-naming gotcha

GitHub Pages is a free way to host a static webpage directly from a
GitHub repo — no AWS, no separate hosting needed for something this
simple.

**The gotcha hit:** GitHub Pages' "deploy from a branch" option only
supports hosting from the repo's root folder, or a folder specifically
named `docs` — not any custom name. The frontend was first placed in a
folder called `frontend/`, which GitHub Pages didn't recognize as an
option at all. The fix was simply renaming the folder to `docs/` using
`git mv` (which renames a file/folder while preserving its Git history,
unlike deleting and recreating it).

## Part 7 — A terminal mishap, and how it was safely recovered

At one point, pasting a large multi-line command into a stuck terminal
caused it to loop, and a few `.tf` files ended up silently emptied out
mid-write. Rather than panicking or assuming everything was broken, each
file was individually checked with `cat <filename>` — most were
untouched, and only the two that came back genuinely empty needed to be
rewritten from the known-correct content. This is a good habit worth
repeating: when something goes wrong, verify precisely what broke before
assuming the worst or redoing everything from scratch.

## Part 8 — Command/concept glossary (new items vs project 1)

| Term | Plain-language meaning |
|---|---|
| Lambda function | A small piece of code that runs only when triggered, with no server running in between |
| Handler | The specific function inside your code that AWS calls when the Lambda is triggered |
| API Gateway | A managed "front door" that turns web requests into Lambda triggers |
| IAM role (vs IAM user) | A role is an *identity a service can assume* (like Lambda "wearing" this identity to act); a user is a *human or system with its own login credentials* |
| CORS | A browser security rule that blocks cross-website requests unless the target API explicitly allows them |
| `git mv` | Renames a file or folder while keeping its Git history intact |
| Managed policy vs custom policy | A managed policy is pre-written by AWS for a whole service; a custom policy is one you write yourself, scoped to exactly what you need |

## Part 9 — How to explain this project in an interview

> "I built a serverless API using AWS Lambda and API Gateway, fully
> defined as Terraform code and deployed through a GitHub Actions
> pipeline with a manual approval gate — reusing the same shared state
> approach as an earlier project. While setting up least-privilege IAM
> permissions by hand, I hit a series of AccessDenied errors from
> AWS Lambda's undocumented internal permission checks. Rather than
> chasing each one indefinitely, I made a deliberate tradeoff: use AWS's
> managed policies for the naturally contained services (Lambda, API
> Gateway), and keep a tightly scoped custom policy specifically for
> IAM role creation, since that's where broad access is actually risky.
> I also added CORS support and a small static frontend hosted on GitHub
> Pages to demonstrate the API visually."

That story demonstrates real engineering judgment, not just "I followed
the steps" — which is exactly what interviewers are listening for.

---

*This document, together with the repo's README.md, covers everything
needed to fully understand, explain, and rebuild this project.*

## Part 11 - Monitoring: the missing DevOps piece, added after the fact

Every project in this portfolio covered Infrastructure as Code and
CI/CD - but none had monitoring, the third core piece of "DevOps"
(build it, deploy it safely, and watch it run). This section covers
what was added to close that gap.

### CloudWatch Dashboard

A dashboard is just a saved, visual arrangement of metrics. This one
has three widgets, each pulling directly from metrics AWS Lambda
already tracks automatically - no extra code needed in the function
itself:

```hcl
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_body = jsonencode({
    widgets = [
      { title = "Lambda Invocations", ... },
      { title = "Lambda Errors", ... },
      { title = "Lambda Duration (ms)", ... }
    ]
  })
}
```

`dashboard_body` is written as JSON (via `jsonencode`) because
CloudWatch's dashboard format is JSON natively - Terraform is just
passing that structure through.

### CloudWatch Alarm

```hcl
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  comparison_operator = "GreaterThanThreshold"
  metric_name          = "Errors"
  namespace            = "AWS/Lambda"
  threshold            = 0
  alarm_actions        = [aws_sns_topic.alerts.arn]
}
```

This watches the same "Errors" metric shown on the dashboard, checking
every 5 minutes (`period = 300`). `threshold = 0` combined with
`GreaterThanThreshold` means "trigger on any error at all, even one" -
a deliberately sensitive setting appropriate for a small demo API.
`alarm_actions` is what actually connects the alarm to a real
notification - without it, the alarm would just sit there, visible
but silent.

### SNS: the notification itself

```hcl
resource "aws_sns_topic" "alerts" { ... }
resource "aws_sns_topic_subscription" "email_alert" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}
```

SNS (Simple
EOF#

## Part 11 - Monitoring: the missing DevOps piece, added after the fact

Every project in this portfolio covered Infrastructure as Code and
CI/CD - but none had monitoring, the third core piece of "DevOps"
(build it, deploy it safely, and watch it run). This section covers
what was added to close that gap.

### CloudWatch Dashboard

A dashboard is just a saved, visual arrangement of metrics. This one
has three widgets, each pulling directly from metrics AWS Lambda
already tracks automatically - no extra code needed in the function
itself:

```hcl
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_body = jsonencode({
    widgets = [
      { title = "Lambda Invocations", ... },
      { title = "Lambda Errors", ... },
      { title = "Lambda Duration (ms)", ... }
    ]
  })
}
```

`dashboard_body` is written as JSON (via `jsonencode`) because
CloudWatch's dashboard format is JSON natively - Terraform is just
passing that structure through.

### CloudWatch Alarm

```hcl
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  comparison_operator = "GreaterThanThreshold"
  metric_name          = "Errors"
  namespace            = "AWS/Lambda"
  threshold            = 0
  alarm_actions        = [aws_sns_topic.alerts.arn]
}
```

This watches the same "Errors" metric shown on the dashboard, checking
every 5 minutes (`period = 300`). `threshold = 0` combined with
`GreaterThanThreshold` means "trigger on any error at all, even one" -
a deliberately sensitive setting appropriate for a small demo API.
`alarm_actions` is what actually connects the alarm to a real
notification - without it, the alarm would just sit there, visible
but silent.

### SNS: the notification itself

```hcl
resource "aws_sns_topic" "alerts" { ... }
resource "aws_sns_topic_subscription" "email_alert" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}
```

SNS (Simple Notification Service) is AWS's general-purpose
"broadcast a message" system. A "topic" is the channel; a
"subscription" is one specific way of receiving messages sent to it -
here, email. AWS requires a one-time human confirmation click before
an email subscription actually starts delivering, as a spam-prevention
measure - the alarm would otherwise silently have no real destination.

### Keeping the email address private

`alert_email` was deliberately given no default value in
`variables.tf`, and its real value was never written into any file in
the repository. Instead, it was stored as a GitHub Secret
(`ALERT_EMAIL`) and passed into Terraform via a specially-named
environment variable in the pipeline:

```yaml
env:
  TF_VAR_alert_email: ${{ secrets.ALERT_EMAIL }}
```

Terraform automatically looks for environment variables prefixed
`TF_VAR_` and maps them to matching variable names - so
`TF_VAR_alert_email` fills `var.alert_email` without that value ever
appearing in code, commit history, or logs.

### Proving it actually works, not just deploying it

Rather than trust that the alarm would work once deployed, it was
tested for real:
1. The Lambda function's code was temporarily replaced with a version
   that always throws an exception.
2. That broken version was deployed through the normal pipeline.
3. The API was called several times via `curl`, generating real
   errors.
4. Within a few minutes, the alarm fired and a real email arrived.
5. The original, working code was restored and redeployed.
6. The API was called once more to confirm it was healthy again.

This is a meaningfully different (and better) standard than "the
Terraform apply succeeded" - it's proof the entire alerting chain
(metric to alarm to SNS to inbox) actually functions, which is the
part that would matter in a real incident.

### The IAM gap this revealed

Deploying the monitoring resources initially failed with
`AccessDenied` on both `SNS:CreateTopic` and
`cloudwatch:PutDashboard` - the `lambda-deployer` IAM user had never
needed those permissions before, since monitoring was new territory
for this project. Fixed by attaching two AWS managed policies,
`AmazonSNSFullAccess` and `CloudWatchFullAccess` - the same "managed
policy for a naturally contained service" reasoning used throughout
this portfolio, since neither service can be used to escalate
privileges beyond itself.

## Part 12 - Explaining this addition in an interview

> "After building several projects covering infrastructure as code and
> CI/CD, I realized none of them actually monitored anything - so I
> added a CloudWatch dashboard, an error alarm, and an SNS email
> notification to my serverless API project. I didn't just deploy it
> and assume it worked - I deliberately broke the function, triggered
> real errors, and confirmed I actually received the alarm email,
> before reverting and redeploying the working version. I also made
> sure the alert email itself was never stored in code, passing it
> through as a GitHub Secret instead."

That's a genuinely complete demonstration of the full DevOps loop -
build, deploy safely, and know when something breaks.
