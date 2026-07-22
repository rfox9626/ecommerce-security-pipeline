import json
import os
import time
import boto3
from botocore.exceptions import ClientError
import redis

REDIS_HOST = os.environ.get("REDIS_HOST", "localhost")
REDIS_PORT = int(os.environ.get("REDIS_PORT", 6379))
AWS_REGION = os.environ.get("AWS_REGION", "us-east-2")

# Strip out any port if it was accidentally included in REDIS_HOST
raw_redis_host = os.environ.get("REDIS_HOST", "localhost")
if ":" in raw_redis_host:
    REDIS_HOST, parsed_port = raw_redis_host.rsplit(":", 1)
    REDIS_PORT = int(parsed_port)
else:
    REDIS_HOST = raw_redis_host

# 1. Initialize DynamoDB client outside handler to reuse connections across warm starts
dynamodb = boto3.resource("dynamodb", region_name=AWS_REGION)
table = dynamodb.Table("ecommerce-transactions-prod")
_redis_pool = None

def get_redis_pool():
    global _redis_pool
    if _redis_pool is None:
        _redis_pool = redis.ConnectionPool(
            host=REDIS_HOST,
            port=REDIS_PORT,
            connection_class=redis.SSLConnection,
            ssl_cert_reqs=None,
            db=0,
            decode_responses=True,
            socket_timeout=5.0,
            socket_connect_timeout=5.0,
        )
    return _redis_pool

def lambda_handler(event, context):
    print(f"Attempting to connect to Redis at {REDIS_HOST}:{REDIS_PORT} (SSL: True)...")
 
    # Initialize connection inside handler scope
    r = redis.Redis(connection_pool=get_redis_pool())

    # Quick debug dump of Redis keys
    try:
        ip_val = r.get("fail:ip:192.168.1.1")
        user_val = r.get("fail:user_id:user-456")
        ip_ttl = r.ttl("fail:ip:192.168.1.1")
        user_ttl = r.ttl("fail:user_id:user-456")
        print(f"DEBUG -> fail:ip:192.168.1.1 = {ip_val} (TTL: {ip_ttl})")
        print(f"DEBUG -> fail:user_id:user-456 = {user_val} (TTL: {user_ttl})")
    except Exception as e:
        print(f"Failed to fetch Redis keys: {e}")

    # This list will hold the IDs of messages that failed to process
    failed_message_ids = []

    # 1. Loop through the batch records delivered by SQS
    for record in event.get("Records", []):
        message_id = record["messageId"]

        try:
            # 2. Parse the payload body
            payload = json.loads(record["body"])

            # 3. Process your business logic
            print(f"Inbound PAYLOAD = {payload}")
            process_transaction_to_db(payload, r)

        except Exception as e:
            # 4. If ANY exception occurs, record this specific message ID as a failure
            print(f"Failed to process message {message_id}: {str(e)}")
            failed_message_ids.append(message_id)

    # 5. Format return payload for SQS partial batch failure handling
    batch_failures = [{"itemIdentifier": msg_id} for msg_id in failed_message_ids]

    return {"batchItemFailures": batch_failures}


def process_transaction_to_db(payload, r):
    user_id = payload.get("user_id")
    action = payload.get("action")
    taction_id = payload.get("transaction_id")
    ip_addr = payload.get("ip_address")
    status = payload.get("status")
    timestamp = payload.get("timestamp") or str(int(time.time() * 1000))

    if status == "fail":
        handle_failure(payload, r)
        return

    try:
        print(f"Attempting to write transaction {taction_id} to DynamoDB...")
        table.put_item(
            Item={
                "transaction_id": taction_id,
                "user_id": user_id,
                "action": action,
                "status": status,
                "ip_addr": ip_addr,
                "timestamp": timestamp,
            }
        )
        print(f"Successfully wrote transaction {taction_id} to DB!")

    except ClientError as e:
        print(f"[ERROR] Failed to write to DynamoDB: {e.response['Error']['Message']}")
        raise e
    except Exception as e:
        print(f"[ERROR] Unexpected error: {str(e)}")
        raise e


def put_in_pipeline(r, key):
    pipe = r.pipeline()
    pipe.incr(key)
    pipe.ttl(key)
    new_total, current_ttl = pipe.execute()
    return new_total, current_ttl


def handle_failure(event_data, r):
    ip = event_data.get("ip_address")
    user_id = event_data.get("user_id")

    ip_key = f"fail:ip:{ip}"
    user_key = f"fail:user_id:{user_id}"

    total_in_q, current_ttl = put_in_pipeline(r, ip_key)

    # If the key has no TTL (-1 means no TTL, -2 means doesn't exist)
    if current_ttl < 0:
        r.expire(ip_key, 300)

    if total_in_q >= 5:
        print(f"Key {ip_key} has too many ip failures in 5 minute interval")
        redis_key = f"block:ip:{ip}"
        r.set(redis_key, "blocked_ip", nx=True, ex=300)

    total_in_q, current_ttl = put_in_pipeline(r, user_key)

    if current_ttl < 0:
        r.expire(user_key, 300)

    if total_in_q >= 5:
        print(f"Key {user_key} has too many user_id failures in 5 minute interval")
        redis_key = f"block:user_id:{user_id}"
        r.set(redis_key, "blocked_user_id", nx=True, ex=300)
