function Invoke-ComputeMarketplaceSetup {
    param(
        [string]$ProjectDir = $PSScriptRoot,
        [string]$PsqlPath = 'C:\Program Files\PostgreSQL\17\bin\psql.exe',
        [string]$Host = 'localhost',
        [string]$User = 'postgres',
        [string]$MaintenanceDb = 'postgres',
        [string]$OltpDb = 'compute_marketplace_oltp',
        [string]$OlapDb = 'compute_marketplace_olap',
        [string]$Password
    )

    if (-not (Test-Path -LiteralPath $PsqlPath)) {
        throw "psql.exe not found at '$PsqlPath'. Update -PsqlPath or install PostgreSQL."
    }

    if (-not $ProjectDir) {
        $ProjectDir = Get-Location
    }

    if (-not (Test-Path -LiteralPath $ProjectDir)) {
        throw "Project directory not found: '$ProjectDir'."
    }

    if (-not $Password) {
        $Password = Read-Host 'PostgreSQL password for user postgres'
    }

    $oldPassword = $env:PGPASSWORD
    Push-Location -LiteralPath $ProjectDir

    try {
        $env:PGPASSWORD = $Password

        $createOltpDatabase = "SELECT format('CREATE DATABASE %I', '$OltpDb') WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = '$OltpDb') \gexec"
        & $PsqlPath -h $Host -U $User -d $MaintenanceDb -c $createOltpDatabase
        if ($LASTEXITCODE -ne 0) { throw 'Failed to create the OLTP database.' }

        & $PsqlPath -h $Host -U $User -d $OltpDb -f 'init_compute_marketplace_oltp.sql'
        if ($LASTEXITCODE -ne 0) { throw 'Failed to initialize the OLTP schema.' }

        & $PsqlPath -h $Host -U $User -d $OltpDb -f 'load_compute_marketplace_oltp.sql'
        if ($LASTEXITCODE -ne 0) { throw 'Failed to load the OLTP data.' }

        & $PsqlPath -h $Host -U $User -d $MaintenanceDb -f 'init_compute_marketplace_olap.sql'
        if ($LASTEXITCODE -ne 0) { throw 'Failed to initialize the OLAP database and schema.' }

        $oltpConnection = "host=$Host port=5432 dbname=$OltpDb user=$User password=$Password"
        & $PsqlPath -h $Host -U $User -d $MaintenanceDb -v "oltp_conn=$oltpConnection" -f 'etl_oltp_to_olap.sql'
        if ($LASTEXITCODE -ne 0) { throw 'Failed to run the OLTP to OLAP ETL.' }
    }
    finally {
        Pop-Location
        $env:PGPASSWORD = $oldPassword
    }
}
