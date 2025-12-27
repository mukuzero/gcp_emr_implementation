import functions_framework
import os
import logging
import psycopg2
import generate_hospital_data
from flask import jsonify

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def get_db_connection():
    """Establishes a connection to the Cloud SQL database."""
    required_vars = ['DB_HOST', 'DB_NAME', 'DB_USER', 'DB_PASSWORD']
    missing_vars = [var for var in required_vars if not os.environ.get(var)]
    
    if missing_vars:
        error_msg = f"Missing required environment variables: {', '.join(missing_vars)}"
        logger.error(error_msg)
        raise EnvironmentError(error_msg)

    try:
        conn = psycopg2.connect(
            host=os.environ.get('DB_HOST'),
            database=os.environ.get('DB_NAME'),
            user=os.environ.get('DB_USER'),
            password=os.environ.get('DB_PASSWORD')
        )
        return conn
    except Exception as e:
        logger.error(f"Failed to connect to database: {e}")
        raise

def setup_database():
    """Reads ddl.sql and executes it to set up the database schema."""
    logger.info("Starting database setup...")
    conn = get_db_connection()
    try:
        with conn.cursor() as cur:
            # Drop tables to ensure fresh schema (needed for composite PK change)
            logger.info("Dropping existing tables...")
            tables = ['transactions', 'encounters', 'patients', 'providers', 'departments', 'hospitals']
            for table in tables:
                cur.execute(f"DROP TABLE IF EXISTS {table} CASCADE;")
            
            # Read DDL file
            # Note: In Cloud Run, the source code is in the working directory
            with open('ddl.sql', 'r') as f:
                ddl_script = f.read()
            
            # Execute DDL
            # We need to handle the \echo commands which are psql specific, not SQL
            # Simple way: remove lines starting with \echo
            cleaned_ddl = "\n".join([line for line in ddl_script.splitlines() if not line.strip().startswith('\\')])
            
            cur.execute(cleaned_ddl)
        conn.commit()
        logger.info("Database setup completed successfully.")
        return True, "Database setup completed successfully."
    except Exception as e:
        conn.rollback()
        logger.error(f"Database setup failed: {e}")
        return False, f"Database setup failed: {str(e)}"
    finally:
        conn.close()

def truncate_tables():
    """Truncates all tables to clear existing data."""
    logger.info("Truncating tables...")
    conn = get_db_connection()
    try:
        with conn.cursor() as cur:
            # Order matters due to foreign keys. 
            # Truncate in reverse order of creation or use CASCADE.
            # CASCADE is safer/easier here.
            tables = ['transactions', 'encounters', 'patients', 'providers', 'departments', 'hospitals']
            for table in tables:
                cur.execute(f"TRUNCATE TABLE {table} CASCADE;")
        conn.commit()
        logger.info("Tables truncated successfully.")
        return True, "Tables truncated successfully."
    except Exception as e:
        conn.rollback()
        logger.error(f"Truncate failed: {e}")
        return False, f"Truncate failed: {str(e)}"
    finally:
        conn.close()

def load_data(truncate=True):
    """Generates synthetic data and loads it into the database."""
    if truncate:
        success, msg = truncate_tables()
        if not success:
            return False, msg

    logger.info("Starting data generation and loading...")
    
    # Change to /tmp for file generation as it's the only writable directory in Cloud Run
    original_cwd = os.getcwd()
    os.chdir('/tmp')
    
    try:
        # Generate Data
        logger.info("Generating data...")
        generate_hospital_data.main()
        
        # Load Data
        logger.info("Loading data into Cloud SQL...")
        conn = get_db_connection()
        
        tables_files = [
            ('hospitals', 'hospitals.csv'),
            # Departments (multiple files)
            ('departments', [f for f in os.listdir('.') if f.endswith('_departments.csv')]),
            # Providers (multiple files)
            ('providers', [f for f in os.listdir('.') if f.endswith('_providers.csv')]),
            # Patients (multiple files)
            ('patients', [f for f in os.listdir('.') if f.endswith('_patients.csv')]),
            # Encounters (multiple files)
            ('encounters', [f for f in os.listdir('.') if f.endswith('_encounters.csv')]),
            # Transactions (multiple files)
            ('transactions', [f for f in os.listdir('.') if f.endswith('_transactions.csv')])
        ]
        
        with conn.cursor() as cur:
            for table, files in tables_files:
                if isinstance(files, str):
                    files = [files]
                
                for file_name in files:
                    if os.path.exists(file_name):
                        logger.info(f"Loading {table} from {file_name}...")
                        with open(file_name, 'r') as f:
                            # Use copy_expert for CSV loading
                            # We assume the CSV header matches the table columns order or names
                            # The generator produces headers, so we use CSV HEADER
                            cur.copy_expert(f"COPY {table} FROM STDIN WITH CSV HEADER", f)
                    else:
                        logger.warning(f"File {file_name} not found for table {table}")
        
        conn.commit()
        conn.close()
        
        # Cleanup
        for f in os.listdir('.'):
            if f.endswith('.csv'):
                os.remove(f)
                
        logger.info("Data loading completed successfully.")
        return True, "Data loading completed successfully."
        
    except Exception as e:
        logger.error(f"Data loading failed: {e}")
        return False, f"Data loading failed: {str(e)}"
    finally:
        # Restore CWD
        os.chdir(original_cwd)

@functions_framework.http
def main(request):
    """HTTP Cloud Function Entry Point."""
    
    # Parse request args
    request_json = request.get_json(silent=True)
    request_args = request.args
    
    action = None
    if request_args and 'action' in request_args:
        action = request_args['action']
    elif request_json and 'action' in request_json:
        action = request_json['action']
        
    if action == 'setup_db':
        success, message = setup_database()
        return jsonify({"status": "success" if success else "error", "message": message}), 200 if success else 500
        
    elif action == 'load_data':
        success, message = load_data()
        return jsonify({"status": "success" if success else "error", "message": message}), 200 if success else 500
        
    elif action == 'setup_and_load':
        # Setup
        success, message = setup_database()
        if not success:
            return jsonify({"status": "error", "message": message}), 500
            
        # Load
        success, message = load_data()
        return jsonify({"status": "success" if success else "error", "message": message}), 200 if success else 500
        
    else:
        return jsonify({
            "status": "error", 
            "message": "Invalid or missing action. Use 'setup_db', 'load_data', or 'setup_and_load'."
        }), 400
