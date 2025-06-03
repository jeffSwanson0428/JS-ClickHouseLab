"""
generate_and_ingest_synthetic_logs.py - Generates and loads synthetic log data into Clickhouse.

This script reads in several command-line args, for configuring the Clickhouse_connect client to your database
and specifying the amount of synthetic logs to insert.

Arguments:
    --host:         Clickhouse server host (default: localhost)
    --port:         Clickhouse server http port (default: 8123)
    --username:     Clickhouse username (default: default)
    --password:     Clickhouse password (defaut: "")
    --database:     Clickhouse database name (default: default)
    --table:        Clickhouse table name (default: logs)
    --batch_size:   Number of records to insert into Clickhouse per batch (default: 100000)
    --batches:      Number of batches to insert into Clickhouse (default: 10)

Example usage:
    python3 generate_and_ingest_synthetic_logs.py --host 127.0.0.1 --port 8123
"""
import clickhouse_connect
import argparse
import random
from clickhouse_connect.driver.client import Client
from faker import Faker
from typing import List, Tuple
from datetime import datetime, timedelta

# Used for synthetic log generation
HOSTS = ["laptop-85.turner-daniel.info","email-29.hill-little.info","laptop-63.pena-spencer.com","email-05.hernandez-anderson.com",
         "srv-67.morris-edwards.com","web-32.harris-griffin.com","email-33.orozco-walters.com","desktop-71.thomas-anderson.info",
         "lt-13.chavez-phillips.com","srv-31.cunningham-rodriguez.com","desktop-34.gonzalez-thompson.net","email-28.clark-watkins.com",
         "srv-60.kennedy-andrews.com","lt-11.gallagher-palmer.com","desktop-51.turner-black.net","email-24.gonzalez-hawkins.com",
         "laptop-33.gonzalez-cox.net","laptop-45.miller-black.com","email-94.orr-contreras.com","laptop-39.brown-nelson.net",
         "desktop-69.gonzalez-kirk.org","db-39.ramirez-kennedy.com","desktop-77.johnson-gomez.com","desktop-63.jackson-patrick.info",
         "email-89.baird-mercado.info","lt-63.rosales-meadows.info","laptop-74.jenkins-weber.com","email-83.carter-reyes.com",
         "email-48.wagner-mcclain.com","srv-56.jackson-washington.com","desktop-46.cordova-hamilton.com"
]
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
    parser.add_argument('--batch_size', default=100000, help='Number of records per batch')
    parser.add_argument('--batches', default=10, help='Number of batches to insert')
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
    days_window = 30
    now = datetime.now()
    window_end = now - timedelta(days=batch_idx * days_window)
    window_start = window_end - timedelta(days=days_window)

    for _ in range(batch_size):
        # Originally intended on using Faker to create the entire record, but opted for random.choice to keep some of the query result sizes manageable
        records.append(
            (
                f.date_time_between(start_date=window_start, end_date=window_end),
                random.choice(SERVICES),
                random.choice(HOSTS),
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
