#!/bin/bash
set -e

# Function to log with timestamp
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Function to get secret value from either Docker secret file or environment variable
get_secret() {
    local secret_name=$1
    local env_var=$2
    local default_value=${3:-""}
    local secret_path="/run/secrets/$secret_name"
    
    if [ -f "$secret_path" ]; then
        cat "$secret_path"
    elif [ ! -z "${!env_var}" ]; then
        echo "${!env_var}"
    else
        echo "$default_value"
    fi
}

# Function to print version banner
print_version_banner() {
    # Prefer env provided by Helm; fall back to package.json in the container
    local pkg_version=""
    if [ -f "/app/server/package.json" ]; then
        pkg_version=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]\+\)".*/\1/p' /app/server/package.json | head -n1)
    fi

    version="${APP_VERSION:-${pkg_version:-unknown}}"
    commit="${APP_BUILD_SHA:-${GIT_SHA:-unknown}}"
    date="$(date +'%Y-%m-%d')"
    author="NineMinds"

    # Function to print colored text
    print_color() {
        color_code=$1
        message=$2
        echo -e "\033[${color_code}m${message}\033[0m"
    }

    # Print the first ASCII art (octopus)
    print_color "35" "
                               *******
                            ****************
                         ***********************
                      *****************************
                    *********************************
                   ************************************
                 ****************************************
                ******************************************
               *******************************************
               *********   ********************************
              ********     *********************************
              ********     *****  **************************
              ********   ******    *************************
             *****************     *************************
              ****************    **************************
              **********************************************
              **********************************************
              *********************************************
         ***  *******************************************
    *********  ******************************************
    *********   ****************************************
                ***************************************
                  ************************************  ***
           *****  ********************************** ******
         **********   *****************************    ******
       ************        ***********************         **
    ************      ***********   *************
    ***********          *************  ************ ***
    ******              ************   ************ *****
                       ***********     **********   ******
                      **********      **********     ******
                    **********       **********        *****
                  *********         *********            ****
                ********           ********                **
             ********            ********
             ***                *******
                              ******
                             ****
    "

    # Print the second ASCII art
    print_color "34" "
                 ###    ##       ######     ###          ######   #####     ### 
                ## ##   ##      ##    ##   ## ##         #     # #     #   ## ##
               ##   ##  ##      ##        ##   ##        #     # #        ##   ##
              ##     ## ##      ##  #### ##     ##       ######   #####  ##     ##
              ######### ##      ##    ## #########       #             # #########
              ##     ## ##      ##    ## ##     ##       #            #  ##     ##
              ##     ## ######## ######  ##     ##       #       ##### 	 ##     ##


    			  #####  ####### ######  #     # ####### ######  
    			 #     # #       #     # #     # #       #     # 
    			 #       #       #     # #     # #       #     # 
    			  #####  #####   ######  #     # #####   ######  
    			       # #       #   #    #   #  #       #   #   
    			 #     # #       #    #    # #   #       #    #  
    			  #####  ####### #     #    #    ####### #     # 
    "

    # Print the version information
    print_color "36" "
                        ****************************************************
                        *                                                  *
                        *               ALGA PSA NEXT.JS                   *
                        *                                                  *
                        *               Version .: $version               *
                        *               Commit  .: $commit                *
                        *               Date    .: $date                  *
                        *               Author  .: $author                *
                        *                                                  *
                        ****************************************************
    "

    # Reset color
    echo -e "\033[0m"

}

# Function to validate required environment variables
validate_environment() {
    log "Validating environment variables..."
    
    # Required variables
    local required_vars=(
        "DB_TYPE"
        "DB_USER_ADMIN"
        "LOG_LEVEL"
        "EMAIL_ENABLE"
        "EMAIL_FROM"
        "EMAIL_PORT"
        "EMAIL_USERNAME"
        "NEXTAUTH_URL"
        "NEXTAUTH_SESSION_EXPIRES"
    )

    local missing_vars=()
    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            missing_vars+=("$var")
        fi
    done

    if [ "$DB_TYPE" != "postgres" ]; then
        log "Error: DB_TYPE must be 'postgres'"
        return 1
    fi

    # Validate LOG_LEVEL
    case "$LOG_LEVEL" in
        SYSTEM|TRACE|DEBUG|INFO|WARNING|ERROR|CRITICAL)
            ;;
        *)
            log "Error: Invalid LOG_LEVEL. Must be one of: SYSTEM, TRACE, DEBUG, INFO, WARNING, ERROR, CRITICAL"
            return 1
            ;;
    esac

    # Validate numeric values
    if ! [[ "$EMAIL_PORT" =~ ^[1-9][0-9]*$ ]]; then
        log "Error: EMAIL_PORT must be a number greater than 0"
        return 1
    fi
    if ! [[ "$NEXTAUTH_SESSION_EXPIRES" =~ ^[1-9][0-9]*$ ]]; then
        log "Error: NEXTAUTH_SESSION_EXPIRES must be a number greater than 0"
        return 1
    fi

    # Validate email format
    # local email_regex="^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$"
    # if ! [[ "$EMAIL_FROM" =~ $email_regex ]]; then
    #     log "Error: EMAIL_FROM must be a valid email address"
    #     return 1
    # fi
    # if ! [[ "$EMAIL_USERNAME" =~ $email_regex ]]; then
    #     log "Error: EMAIL_USERNAME must be a valid email address"
    #     return 1
    # fi

    # Validate URL format
    if ! [[ "$NEXTAUTH_URL" =~ ^https?:// ]]; then
        log "Error: NEXTAUTH_URL must be a valid URL"
        return 1
    fi

    if [ ${#missing_vars[@]} -ne 0 ]; then
        log "Error: Missing required environment variables: ${missing_vars[*]}"
        return 1
    fi

    log "Environment validation successful"
    return 0
}

# Function to check if postgres is ready
wait_for_postgres() {
    log "Waiting for PostgreSQL to be ready..."
    local db_host="${DB_HOST:-postgres}"
    local db_port="${DB_PORT:-5432}"
    local db_user="${DB_USER_ADMIN:-postgres}"
    local max_attempts=60
    local attempt=1

    # pg_isready is installed via apk add postgresql-client
    until pg_isready -h "$db_host" -p "$db_port" -U "$db_user" > /dev/null 2>&1 || [ $attempt -gt $max_attempts ]; do
        log "PostgreSQL is not ready yet (attempt $attempt/$max_attempts) - sleeping..."
        sleep 2
        attempt=$((attempt + 1))
    done

    if [ $attempt -gt $max_attempts ]; then
        log "Error: PostgreSQL did not become ready in time"
        return 1
    fi

    log "PostgreSQL is ready!"
    return 0
}

# Function to check if redis is ready
wait_for_redis() {
    log "Waiting for Redis to be ready..."
    local redis_password=$(get_secret "redis_password" "REDIS_PASSWORD")
    until redis-cli -h ${REDIS_HOST:-redis} -p ${REDIS_PORT:-6379} -a "$redis_password" ping 2>/dev/null; do
        log "Redis is unavailable - sleeping"
        sleep 1
    done
    log "Redis is up and running!"
}

# Function to check if hocuspocus is ready
wait_for_hocuspocus() {
    # Skip if hocuspocus is not required
    if [ -z "${REQUIRE_HOCUSPOCUS}" ] || [ "${REQUIRE_HOCUSPOCUS}" = "false" ]; then
        log "Hocuspocus check skipped - not required for this environment"
        return 0
    fi

    log "Waiting for Hocuspocus to be ready..."
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if curl -s "http://${HOCUSPOCUS_HOST:-hocuspocus}:${HOCUSPOCUS_PORT:-1234}/health" > /dev/null; then
            log "Hocuspocus is up and running!"
            return 0
        fi
        log "Hocuspocus is unavailable (attempt $attempt/$max_attempts) - sleeping"
        sleep 1
        attempt=$((attempt + 1))
    done

    if [ "${REQUIRE_HOCUSPOCUS}" = "true" ]; then
        log "Error: Hocuspocus failed to become ready after $max_attempts attempts"
        return 1
    else
        log "Warning: Hocuspocus is not available, but continuing anyway"
        return 0
    fi
}

# Function to fix database permissions (self-healing for previous deployments)
fix_permissions() {
    log "Attempting to fix database permissions..."
    
    # Get admin password (usually postgres)
    local db_password_admin=$(get_secret "postgres_password" "DB_PASSWORD_ADMIN")
    
    if [ -z "$db_password_admin" ]; then
        log "WARNING: DB_PASSWORD_ADMIN not found. Skipping permission fix."
        return 0
    fi

    local admin_user=${DB_USER_ADMIN:-postgres}
    
    # Export password for psql
    export PGPASSWORD="$db_password_admin"
    
    # Transfer ownership of knex tables if they exist
    # This prevents "relation already exists" errors when app_user tries to use/manage tables owned by postgres
    log "Transferring ownership of ALL public tables to $DB_USER_SERVER..."
    
    # Use a DO block to safely iterate and fix permissions for everything in public schema
    # This is the "God Mode" fix that ensures app_user owns everything regardless of previous failures
    psql -h "$DB_HOST" -U "$admin_user" -d "$DB_NAME_SERVER" -c "
    DO \$\$
    DECLARE
        r RECORD;
    BEGIN
        -- 1. Grant usage on schema (idempotent)
        GRANT ALL ON SCHEMA public TO $DB_USER_SERVER;

        -- 2. Take over ownership of all existing tables (including knex_migrations)
        FOR r IN (SELECT tablename FROM pg_tables WHERE schemaname = 'public') LOOP
            EXECUTE 'ALTER TABLE public.' || quote_ident(r.tablename) || ' OWNER TO $DB_USER_SERVER';
        END LOOP;

        -- 3. Take over ownership of all sequences (for serial IDs)
        FOR r IN (SELECT sequencename FROM pg_sequences WHERE schemaname = 'public') LOOP
            EXECUTE 'ALTER SEQUENCE public.' || quote_ident(r.sequencename) || ' OWNER TO $DB_USER_SERVER';
        END LOOP;
        
        RAISE NOTICE 'Permissions fixed successfully for user $DB_USER_SERVER';
    END \$\$;
    " || log "Warning: Permission fix command had partial failure (or tables usually don't exist yet)."
    
    export PGPASSWORD=""
}

# Function to run database migrations
run_migrations() {
    log "Running database migrations..."
    
    # Ensure we are in the server directory where knexfile.cjs resides
    cd /app/server
    
    # Run migrations using the production config (which uses app_user)
    # This ensures tables are owned by app_user, solving permission issues.
    log "Executing: npx knex migrate:latest --knexfile knexfile.cjs"
    
    # We call npx directly. It should find the local knex in node_modules.
    if npx knex migrate:latest --knexfile knexfile.cjs; then
        log "Migrations completed successfully"
        cd /app # Return to root
        return 0
    else
        log "Error: Migrations failed"
        cd /app # Return to root
        return 1
    fi
}

# Function to start the application
start_app() {
    # Set up application database connection using app_user
    local db_password_server=$(get_secret "db_password_server" "DB_PASSWORD_SERVER")
    export DATABASE_URL="postgresql://$DB_USER_SERVER:$db_password_server@postgres:5432/server"
    
    # Set NEXTAUTH_SECRET from Docker secret if not already set
    log "Setting NEXTAUTH_SECRET from secret file..."
    export NEXTAUTH_SECRET=$(get_secret "nextauth_secret" "NEXTAUTH_SECRET")
    
    # Debug: Check if .next directory exists
    log "DEBUG: Checking for build artifacts..."
    log "Current directory: $(pwd)"
    log "Contents of /app/server:"
    ls -la /app/server/ || true
    log "Checking for .next directory:"
    ls -la /app/server/.next/ || log ".next directory not found"
    ls -la /app/server/.next/ || log ".next directory not found"

    
    if [ "$NODE_ENV" = "development" ]; then
        log "Starting server in development mode..."
        npm run dev
    else
        log "Starting server in production mode..."
        pwd
        cd /app/server
        log "About to run npm start in directory: $(pwd)"
        
        # Try to start, but don't exit on failure - keep container running for debug
        if ! npm start; then
            log "ERROR: npm start failed, but keeping container alive for debugging"
            log "Sleeping indefinitely - you can exec into the container to troubleshoot"
            while true; do
                sleep 3600
            done
        fi
    fi
}

# Main startup process
main() {
    log "DEBUG: Starting entrypoint script (Version: fix-permissions-debug-v1)"
    print_version_banner
    
    # Validate environment
    if ! validate_environment; then
        log "Environment validation failed"
        if [ "$NODE_ENV" = "development" ]; then
            exit 1
        fi
    fi
    
    # Wait for dependencies
    if ! wait_for_postgres; then
        exit 1
    fi
    wait_for_redis
    wait_for_hocuspocus
    
    # Fix permissions before migrations
    fix_permissions

    # Migrations are handled by init-db sidecar
    # We validatd dependencies above, so we assume schema is ready.


    # Start the application
    start_app
}

# Execute main function with error handling
if ! main; then
    log "Error: Server failed to start properly"
    exit 1
fi
