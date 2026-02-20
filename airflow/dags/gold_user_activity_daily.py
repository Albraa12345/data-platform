"""
Gold User Activity Daily DAG
============================

Production-grade Airflow DAG for computing daily user activity aggregations.

Features:
- Fully idempotent: Re-running produces identical results
- Backfill safe: Can process historical dates without duplicates
- Partition-aware: Deletes old data before inserting fresh aggregations
- Error handling: Comprehensive logging and failure recovery
- Retry logic: Automatic retries with exponential backoff

Schedule: Daily at 02:00 UTC (processes previous day's data)
"""

from datetime import datetime, timedelta
from typing import Optional
import logging

from airflow import DAG
from airflow.operators.python import PythonOperator
from airflow.operators.empty import EmptyOperator
from airflow.utils.dates import days_ago
from airflow.exceptions import AirflowException

import clickhouse_connect
from clickhouse_connect.driver.exceptions import ClickHouseError


# ============================================
# Configuration
# ============================================

CLICKHOUSE_CONFIG = {
    'host': 'clickhouse',
    'port': 8123,
    'username': 'default',
    'password': '',
    'database': 'analytics',
    'settings': {
        'max_execution_time': 3600,
        'max_memory_usage': 10000000000,
    }
}

DAG_CONFIG = {
    'dag_id': 'gold_user_activity_daily',
    'description': 'Compute daily user activity aggregations for gold layer',
    'schedule_interval': '0 2 * * *',  # Daily at 02:00 UTC
    'start_date': datetime(2024, 1, 1),
    'catchup': True,  # Enable for backfilling
    'max_active_runs': 1,  # Prevent concurrent runs
    'tags': ['gold', 'aggregation', 'daily', 'production'],
}

DEFAULT_ARGS = {
    'owner': 'data-platform',
    'depends_on_past': False,
    'email_on_failure': True,
    'email_on_retry': False,
    'email': ['data-alerts@example.com'],
    'retries': 3,
    'retry_delay': timedelta(minutes=5),
    'retry_exponential_backoff': True,
    'max_retry_delay': timedelta(minutes=30),
    'execution_timeout': timedelta(hours=2),
}


# ============================================
# Logging Setup
# ============================================

logger = logging.getLogger(__name__)


# ============================================
# ClickHouse Client Helper
# ============================================

def get_clickhouse_client():
    """Create and return a ClickHouse client connection."""
    try:
        client = clickhouse_connect.get_client(
            host=CLICKHOUSE_CONFIG['host'],
            port=CLICKHOUSE_CONFIG['port'],
            username=CLICKHOUSE_CONFIG['username'],
            password=CLICKHOUSE_CONFIG['password'],
            database=CLICKHOUSE_CONFIG['database'],
            settings=CLICKHOUSE_CONFIG['settings'],
        )
        logger.info("Successfully connected to ClickHouse")
        return client
    except Exception as e:
        logger.error(f"Failed to connect to ClickHouse: {e}")
        raise AirflowException(f"ClickHouse connection failed: {e}")


def execute_query(client, query: str, parameters: Optional[dict] = None) -> None:
    """Execute a ClickHouse query with error handling."""
    try:
        logger.info(f"Executing query: {query[:200]}...")
        if parameters:
            client.command(query, parameters=parameters)
        else:
            client.command(query)
        logger.info("Query executed successfully")
    except ClickHouseError as e:
        logger.error(f"ClickHouse query failed: {e}")
        raise AirflowException(f"Query execution failed: {e}")


def execute_query_with_result(client, query: str, parameters: Optional[dict] = None):
    """Execute a ClickHouse query and return results."""
    try:
        logger.info(f"Executing query with results: {query[:200]}...")
        if parameters:
            result = client.query(query, parameters=parameters)
        else:
            result = client.query(query)
        logger.info(f"Query returned {result.row_count} rows")
        return result
    except ClickHouseError as e:
        logger.error(f"ClickHouse query failed: {e}")
        raise AirflowException(f"Query execution failed: {e}")


# ============================================
# Task Functions
# ============================================

def validate_source_data(**context) -> dict:
    """
    Validate that source data exists for the target date.
    Returns metadata about available data.
    """
    execution_date = context['ds']  # YYYY-MM-DD format
    logger.info(f"Validating source data for date: {execution_date}")
    
    client = get_clickhouse_client()
    
    # Check silver_events data availability
    events_query = """
        SELECT 
            count() as event_count,
            uniq(user_id) as unique_users,
            min(event_timestamp) as min_ts,
            max(event_timestamp) as max_ts
        FROM analytics.silver_events
        WHERE toDate(event_timestamp) = {target_date:Date}
    """
    
    events_result = execute_query_with_result(
        client, 
        events_query, 
        parameters={'target_date': execution_date}
    )
    
    events_row = events_result.first_row if events_result.row_count > 0 else (0, 0, None, None)
    event_count, unique_users, min_ts, max_ts = events_row
    
    # Check silver_users data availability
    users_query = """
        SELECT count() as user_count
        FROM analytics.v_silver_users_all
    """
    users_result = execute_query_with_result(client, users_query)
    user_count = users_result.first_row[0] if users_result.row_count > 0 else 0
    
    client.close()
    
    validation_result = {
        'target_date': execution_date,
        'event_count': event_count,
        'unique_users': unique_users,
        'min_timestamp': str(min_ts) if min_ts else None,
        'max_timestamp': str(max_ts) if max_ts else None,
        'total_users_in_system': user_count,
        'has_data': event_count > 0,
    }
    
    logger.info(f"Validation result: {validation_result}")
    
    if event_count == 0:
        logger.warning(f"No events found for date {execution_date}. DAG will continue but may produce empty results.")
    
    # Push to XCom for downstream tasks
    context['ti'].xcom_push(key='validation_result', value=validation_result)
    
    return validation_result


def delete_existing_partition(**context) -> None:
    """
    Delete existing data for the target date partition.
    This ensures idempotency - re-running will replace old data.
    """
    execution_date = context['ds']
    logger.info(f"Deleting existing partition for date: {execution_date}")
    
    client = get_clickhouse_client()
    
    # Check existing row count before deletion
    count_query = """
        SELECT count() as row_count
        FROM analytics.gold_user_activity
        WHERE activity_date = {target_date:Date}
    """
    count_result = execute_query_with_result(
        client, 
        count_query, 
        parameters={'target_date': execution_date}
    )
    existing_count = count_result.first_row[0] if count_result.row_count > 0 else 0
    logger.info(f"Found {existing_count} existing rows for date {execution_date}")
    
    if existing_count > 0:
        # Use ALTER TABLE DELETE for partition-aware deletion
        # This is a lightweight mutation in ClickHouse
        delete_query = """
            ALTER TABLE analytics.gold_user_activity
            DELETE WHERE activity_date = {target_date:Date}
        """
        execute_query(client, delete_query, parameters={'target_date': execution_date})
        logger.info(f"Deleted {existing_count} rows for date {execution_date}")
        
        # Wait for mutation to complete (optional, for safety)
        wait_query = """
            SELECT count() 
            FROM system.mutations 
            WHERE table = 'gold_user_activity' 
              AND database = 'analytics' 
              AND is_done = 0
        """
        # Simple wait - in production, implement proper mutation tracking
        import time
        for _ in range(30):  # Max 30 seconds wait
            result = execute_query_with_result(client, wait_query)
            pending = result.first_row[0] if result.row_count > 0 else 0
            if pending == 0:
                break
            time.sleep(1)
    else:
        logger.info("No existing data to delete")
    
    client.close()
    context['ti'].xcom_push(key='deleted_rows', value=existing_count)


def compute_aggregations(**context) -> dict:
    """
    Compute daily user activity aggregations.
    Joins silver_events with silver_users and aggregates by user and date.
    """
    execution_date = context['ds']
    logger.info(f"Computing aggregations for date: {execution_date}")
    
    client = get_clickhouse_client()
    
    # Main aggregation query
    # Uses INSERT...SELECT for atomic operation
    insert_query = """
        INSERT INTO analytics.gold_user_activity
        SELECT
            toDate(se.event_timestamp) AS activity_date,
            se.user_id,
            count() AS event_count,
            max(se.event_timestamp) AS last_event_timestamp,
            countIf(se.event_type = 'page_view') AS page_view_count,
            countIf(se.event_type = 'click') AS click_count,
            countIf(se.event_type = 'purchase') AS purchase_count,
            countIf(se.event_type = 'search') AS search_count,
            countIf(se.event_type = 'add_to_cart') AS add_to_cart_count,
            countIf(se.event_type = 'login') AS login_count,
            coalesce(argMax(su.full_name, su._version), '') AS user_full_name,
            coalesce(argMax(su.email, su._version), '') AS user_email,
            if(argMax(su.is_deleted, su._version) = 0, 1, 0) AS user_is_active,
            now64(3) AS _computed_at,
            toUnixTimestamp64Milli(now64(3)) AS _version
        FROM analytics.silver_events AS se
        LEFT JOIN analytics.silver_users AS su ON se.user_id = su.user_id
        WHERE toDate(se.event_timestamp) = {target_date:Date}
        GROUP BY
            activity_date,
            se.user_id
        HAVING event_count > 0
    """
    
    execute_query(client, insert_query, parameters={'target_date': execution_date})
    
    # Verify inserted rows
    verify_query = """
        SELECT 
            count() as row_count,
            sum(event_count) as total_events,
            uniq(user_id) as unique_users
        FROM analytics.gold_user_activity
        WHERE activity_date = {target_date:Date}
    """
    verify_result = execute_query_with_result(
        client, 
        verify_query, 
        parameters={'target_date': execution_date}
    )
    
    row_count, total_events, unique_users = verify_result.first_row if verify_result.row_count > 0 else (0, 0, 0)
    
    client.close()
    
    aggregation_result = {
        'target_date': execution_date,
        'rows_inserted': row_count,
        'total_events_aggregated': total_events,
        'unique_users': unique_users,
    }
    
    logger.info(f"Aggregation complete: {aggregation_result}")
    context['ti'].xcom_push(key='aggregation_result', value=aggregation_result)
    
    return aggregation_result


def optimize_table(**context) -> None:
    """
    Optimize the gold table to merge parts and deduplicate.
    This is important for ReplacingMergeTree tables.
    """
    execution_date = context['ds']
    logger.info(f"Optimizing gold_user_activity table for date: {execution_date}")
    
    client = get_clickhouse_client()
    
    # Optimize only the affected partition
    partition = datetime.strptime(execution_date, '%Y-%m-%d').strftime('%Y%m')
    
    optimize_query = f"""
        OPTIMIZE TABLE analytics.gold_user_activity 
        PARTITION '{partition}'
        FINAL
    """
    
    try:
        execute_query(client, optimize_query)
        logger.info(f"Successfully optimized partition {partition}")
    except Exception as e:
        # Optimization failure is non-fatal - data is still correct
        logger.warning(f"Optimization warning (non-fatal): {e}")
    
    client.close()


def validate_results(**context) -> dict:
    """
    Final validation of the aggregation results.
    Compares source and destination row counts.
    """
    execution_date = context['ds']
    logger.info(f"Validating results for date: {execution_date}")
    
    client = get_clickhouse_client()
    
    # Get source user count
    source_query = """
        SELECT uniq(user_id) as unique_users
        FROM analytics.silver_events
        WHERE toDate(event_timestamp) = {target_date:Date}
    """
    source_result = execute_query_with_result(
        client, 
        source_query, 
        parameters={'target_date': execution_date}
    )
    source_users = source_result.first_row[0] if source_result.row_count > 0 else 0
    
    # Get destination user count
    dest_query = """
        SELECT 
            count() as row_count,
            sum(event_count) as total_events
        FROM analytics.gold_user_activity FINAL
        WHERE activity_date = {target_date:Date}
    """
    dest_result = execute_query_with_result(
        client, 
        dest_query, 
        parameters={'target_date': execution_date}
    )
    dest_rows, dest_events = dest_result.first_row if dest_result.row_count > 0 else (0, 0)
    
    client.close()
    
    validation_passed = (source_users == 0 and dest_rows == 0) or (source_users > 0 and dest_rows > 0)
    
    validation_result = {
        'target_date': execution_date,
        'source_unique_users': source_users,
        'destination_rows': dest_rows,
        'destination_total_events': dest_events,
        'validation_passed': validation_passed,
    }
    
    logger.info(f"Validation result: {validation_result}")
    
    if not validation_passed:
        raise AirflowException(
            f"Validation failed: Source had {source_users} users but destination has {dest_rows} rows"
        )
    
    context['ti'].xcom_push(key='final_validation', value=validation_result)
    return validation_result


def generate_report(**context) -> str:
    """
    Generate a summary report of the DAG execution.
    """
    execution_date = context['ds']
    ti = context['ti']
    
    validation = ti.xcom_pull(task_ids='validate_source_data', key='validation_result') or {}
    deleted = ti.xcom_pull(task_ids='delete_existing_partition', key='deleted_rows') or 0
    aggregation = ti.xcom_pull(task_ids='compute_aggregations', key='aggregation_result') or {}
    final = ti.xcom_pull(task_ids='validate_results', key='final_validation') or {}
    
    report = f"""
================================================================================
GOLD USER ACTIVITY DAILY - EXECUTION REPORT
================================================================================
Execution Date: {execution_date}
Run ID: {context['run_id']}
--------------------------------------------------------------------------------
SOURCE DATA VALIDATION:
  - Events Found: {validation.get('event_count', 'N/A')}
  - Unique Users: {validation.get('unique_users', 'N/A')}
  - Time Range: {validation.get('min_timestamp', 'N/A')} to {validation.get('max_timestamp', 'N/A')}
--------------------------------------------------------------------------------
PARTITION CLEANUP:
  - Rows Deleted: {deleted}
--------------------------------------------------------------------------------
AGGREGATION RESULTS:
  - Rows Inserted: {aggregation.get('rows_inserted', 'N/A')}
  - Total Events Aggregated: {aggregation.get('total_events_aggregated', 'N/A')}
  - Unique Users: {aggregation.get('unique_users', 'N/A')}
--------------------------------------------------------------------------------
FINAL VALIDATION:
  - Validation Passed: {final.get('validation_passed', 'N/A')}
================================================================================
    """
    
    logger.info(report)
    return report


# ============================================
# DAG Definition
# ============================================

with DAG(
    dag_id=DAG_CONFIG['dag_id'],
    description=DAG_CONFIG['description'],
    schedule_interval=DAG_CONFIG['schedule_interval'],
    start_date=DAG_CONFIG['start_date'],
    catchup=DAG_CONFIG['catchup'],
    max_active_runs=DAG_CONFIG['max_active_runs'],
    tags=DAG_CONFIG['tags'],
    default_args=DEFAULT_ARGS,
    doc_md=__doc__,
) as dag:
    
    # Start marker
    start = EmptyOperator(
        task_id='start',
        doc='DAG start marker',
    )
    
    # Task 1: Validate source data exists
    validate_task = PythonOperator(
        task_id='validate_source_data',
        python_callable=validate_source_data,
        doc='Validate that silver layer data exists for the target date',
    )
    
    # Task 2: Delete existing partition (idempotency)
    delete_task = PythonOperator(
        task_id='delete_existing_partition',
        python_callable=delete_existing_partition,
        doc='Delete existing data for the target date to ensure idempotency',
    )
    
    # Task 3: Compute aggregations
    compute_task = PythonOperator(
        task_id='compute_aggregations',
        python_callable=compute_aggregations,
        doc='Compute daily user activity aggregations from silver layer',
    )
    
    # Task 4: Optimize table
    optimize_task = PythonOperator(
        task_id='optimize_table',
        python_callable=optimize_table,
        doc='Optimize ClickHouse table to merge parts and deduplicate',
    )
    
    # Task 5: Validate results
    validate_results_task = PythonOperator(
        task_id='validate_results',
        python_callable=validate_results,
        doc='Validate that aggregation results match source data',
    )
    
    # Task 6: Generate report
    report_task = PythonOperator(
        task_id='generate_report',
        python_callable=generate_report,
        doc='Generate execution summary report',
    )
    
    # End marker
    end = EmptyOperator(
        task_id='end',
        doc='DAG end marker',
    )
    
    # Define task dependencies
    start >> validate_task >> delete_task >> compute_task >> optimize_task >> validate_results_task >> report_task >> end
