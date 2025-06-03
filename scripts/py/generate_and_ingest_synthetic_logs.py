import clickhouse_connect
import argparse
import random
from clickhouse_connect.driver.client import Client
from faker import Faker
from typing import List, Tuple
from datetime import datetime, timedelta

# Used for synthetic log generation
SERVICES = [
    'identity','auth-service','billing','delivery-manager','log-streaming-manager',
    'log-streaming-operator','cdn-edge-node','analytics-engine','session_manager',
    'order_processor','client-billing-database',
]
LOG_LEVELS = ['Info','Debug','Warn','Error','Critical']
MESSAGES = [
    'User login successful','Configuration reloaded','Auth token has expired','Service started',
    'Unhandled exception in request handler','Database connection timeout after 3000ms',
    'Received heartbeat','Retrying failed request','Log level changed to DEBUG via override'
]

def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description='Generate and insert synthetic logs into ClickHouse.')
    parser.add_argument('--host', default='localhost', help='ClickHouse server host')
    parser.add_argument('--port', type=int, default=8123, help='ClickHouse server http port')
    parser.add_argument('--username', default='default', help='ClickHouse username')
    parser.add_argument('--password', default='', help='ClickHouse password')
    parser.add_argument('--database', default='default', help='ClickHouse database')
    parser.add_argument('--table', default='logs', help='ClickHouse table name')
    parser.add_argument('--batch_size', default=10000, help='Number of records per batch')
    parser.add_argument('--batches', default=100, help='Number of batches to insert')
    return parser.parse_args()

def init_client(args: argparse.Namespace) -> Client:
    return clickhouse_connect.get_client(
        host=args.host,
        port=args.port,
        username=args.username,
        password=args.password,
        database=args.database
    )

def generate_synthetic_records_batch(f: Faker, batch_size: int, batch_idx: int) -> List[Tuple[datetime, str, str, str, str]]:
    records = []

    # Due to the tables partition on the timestamp column, we must limit the range on the values as to not violate 
    # the max_partitions_per_insert_block' setting in clickhouse.
    # I opted to handle this by using a 30 day window per batch of records
    # Generating the window dynamically based on batch index allows for a better distribution of dates in the synthetic data
    days_window = 30
    now = datetime.now()
    window_end = now - timedelta(days=batch_idx * days_window)
    window_start = window_end - timedelta(days=days_window)

    for _ in range(batch_size):
        records.append(
            (
                f.date_time_between(start_date=window_start, end_date=window_end),
                random.choice(SERVICES),
                f.hostname(),
                random.choice(LOG_LEVELS),
                random.choice(MESSAGES)
            )
        )
    return records

def main():
    args = parse_args()
    client = init_client(args)
    batches = args.batches
    batch_size = args.batch_size
    fake = Faker()
    columns = ['timestamp', 'service_name', 'host', 'log_level', 'message']

    for i in range(batches):
        records = generate_synthetic_records_batch(fake, batch_size, i)
        client.insert(
            table=args.table,
            column_names=columns,
            data=records
        )
        print(f'>>> Inserted batch {i+1} of {batches}')

    print('>>> All records inserted successfully.')
    return

if __name__ == '__main__':
    main()
