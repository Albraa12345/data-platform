# ============================================
# Windows PowerShell Setup Script
# ============================================
# Complete setup script for Windows environments

param(
    [switch]$SkipBuild,
    [switch]$SkipConnectors,
    [switch]$Verbose
)

$ErrorActionPreference = "Stop"

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "Data Platform Setup Script (Windows)" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

# Get project root
$ProjectRoot = Split-Path -Parent $PSScriptRoot

# Set environment variables
$env:AIRFLOW_UID = 50000
$env:COMPOSE_PROJECT_NAME = "data-platform"

# Step 1: Create necessary directories
Write-Host "`n[1/7] Creating directories..." -ForegroundColor Yellow
$directories = @(
    "$ProjectRoot\airflow\dags",
    "$ProjectRoot\airflow\logs", 
    "$ProjectRoot\airflow\plugins",
    "$ProjectRoot\airflow\config"
)

foreach ($dir in $directories) {
    if (!(Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Write-Host "  Created: $dir"
    }
}

# Step 2: Fix MongoDB keyfile permissions (create proper keyfile)
Write-Host "`n[2/7] Setting up MongoDB keyfile..." -ForegroundColor Yellow
$keyfilePath = "$ProjectRoot\mongodb\keyfile"
$keyfileContent = "mongodb-keyfile-content-for-replica-set-authentication-this-should-be-at-least-six-characters"
Set-Content -Path $keyfilePath -Value $keyfileContent -NoNewline

# Step 3: Start infrastructure services
Write-Host "`n[3/7] Starting infrastructure services..." -ForegroundColor Yellow
Set-Location $ProjectRoot

if (!$SkipBuild) {
    docker-compose up -d zookeeper
    Start-Sleep -Seconds 10
    
    docker-compose up -d kafka
    Start-Sleep -Seconds 15
    
    docker-compose up -d postgres mongodb
    Start-Sleep -Seconds 10
    
    docker-compose up -d mongodb-init
    Start-Sleep -Seconds 15
}

# Step 4: Start Kafka Connect
Write-Host "`n[4/7] Starting Kafka Connect (Debezium)..." -ForegroundColor Yellow
docker-compose up -d kafka-connect
Start-Sleep -Seconds 30

# Step 5: Start ClickHouse
Write-Host "`n[5/7] Starting ClickHouse..." -ForegroundColor Yellow
docker-compose up -d clickhouse
Start-Sleep -Seconds 15

# Initialize ClickHouse schema
Write-Host "  Initializing ClickHouse schema..."
$clickhouseInitFiles = Get-ChildItem -Path "$ProjectRoot\clickhouse\init\*.sql" | Sort-Object Name

foreach ($sqlFile in $clickhouseInitFiles) {
    Write-Host "  Executing: $($sqlFile.Name)"
    $sqlContent = Get-Content $sqlFile.FullName -Raw
    try {
        Invoke-RestMethod -Uri "http://localhost:8123/" -Method Post -Body $sqlContent -ContentType "text/plain" | Out-Null
        Write-Host "    Success" -ForegroundColor Green
    } catch {
        Write-Host "    Warning: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# Step 6: Setup Debezium Connectors
if (!$SkipConnectors) {
    Write-Host "`n[6/7] Setting up Debezium connectors..." -ForegroundColor Yellow
    
    # Wait for Kafka Connect to be fully ready
    $maxAttempts = 30
    $attempt = 0
    while ($attempt -lt $maxAttempts) {
        try {
            $response = Invoke-RestMethod -Uri "http://localhost:8083/connectors" -Method Get -ErrorAction Stop
            Write-Host "  Kafka Connect is ready!"
            break
        } catch {
            $attempt++
            Write-Host "  Waiting for Kafka Connect... ($attempt/$maxAttempts)"
            Start-Sleep -Seconds 5
        }
    }
    
    # Register PostgreSQL connector
    Write-Host "  Registering PostgreSQL connector..."
    $pgConfig = Get-Content "$ProjectRoot\debezium\connectors\postgres-connector.json" -Raw
    try {
        Invoke-RestMethod -Uri "http://localhost:8083/connectors" -Method Post -Body $pgConfig -ContentType "application/json" | Out-Null
        Write-Host "    PostgreSQL connector registered" -ForegroundColor Green
    } catch {
        Write-Host "    Warning: $($_.Exception.Message)" -ForegroundColor Yellow
    }
    
    Start-Sleep -Seconds 5
    
    # Register MongoDB connector
    Write-Host "  Registering MongoDB connector..."
    $mongoConfig = Get-Content "$ProjectRoot\debezium\connectors\mongodb-connector.json" -Raw
    try {
        Invoke-RestMethod -Uri "http://localhost:8083/connectors" -Method Post -Body $mongoConfig -ContentType "application/json" | Out-Null
        Write-Host "    MongoDB connector registered" -ForegroundColor Green
    } catch {
        Write-Host "    Warning: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# Step 7: Start Airflow
Write-Host "`n[7/7] Starting Airflow..." -ForegroundColor Yellow
docker-compose up -d airflow-postgres
Start-Sleep -Seconds 10

docker-compose up -d airflow-init
Start-Sleep -Seconds 30

docker-compose up -d airflow-webserver airflow-scheduler
Start-Sleep -Seconds 15

# Start Kafka UI
docker-compose up -d kafka-ui

# Summary
Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host "Setup Complete!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Services Available:" -ForegroundColor Yellow
Write-Host "  - Airflow UI:      http://localhost:8080  (admin/admin)"
Write-Host "  - Kafka UI:        http://localhost:8081"
Write-Host "  - Kafka Connect:   http://localhost:8083"
Write-Host "  - ClickHouse:      http://localhost:8123"
Write-Host "  - PostgreSQL:      localhost:5432"
Write-Host "  - MongoDB:         localhost:27017"
Write-Host ""
Write-Host "To verify the pipeline:" -ForegroundColor Yellow
Write-Host "  .\init-scripts\04_verify_pipeline.sh"
Write-Host ""
Write-Host "To view logs:" -ForegroundColor Yellow
Write-Host "  docker-compose logs -f [service-name]"
Write-Host ""
