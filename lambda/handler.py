import json
import random

QUOTES = [
    "Simplicity is the ultimate sophistication.",
    "Done is better than perfect.",
    "The best way to predict the future is to invent it.",
    "Code is like humor. When you have to explain it, it's bad.",
    "First, solve the problem. Then, write the code.",
]


def handler(event, context):
    raise Exception("Intentional test error to verify the CloudWatch alarm")

    quote = random.choice(QUOTES)
    return {
        "statusCode": 200,
        "headers": {
            "Content-Type": "application/json"
        },
        "body": json.dumps({"quote": quote})
    }
