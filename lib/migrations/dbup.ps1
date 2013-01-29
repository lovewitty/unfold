task buildmigrations {
    If(-not $config.dbup.msbuild) {
        Write-Warning "No migrations msbuild project configured"
        Write-Warning "Please add Set-Config dbup @{"
        Write-Warning "                 msbuild = '.\code\path\to\msbuild\msbuild.csproj'"
        Write-Warning "                 }"
        Write-Warning "to your deploy.ps1 file"
        return
    }

    Write-Host "Building dbup project" -Fore Green
    Invoke-Script {
        Exec {
            $buildConfig = $config.buildConfiguration
            if(-not $buildConfig) {
                $buildConfig = "Debug"
            }
            msbuild /p:Configuration="$buildConfig" /target:Rebuild $config.dbup.msbuild
        }
    }
}

Set-AfterTask build buildmigrations

task releasemigrations {
    $migrationsPath = Split-Path $config.dbup.msbuild
    $migrationsBuildOutputPath = "$migrationsPath\bin\$($config.buildConfiguration)"

    $config.migrationsdestination = ".\$($config.releasepath)\database"

    # Copy assembly output
    Write-Host "Copying migrations assembly to release folder"
    Invoke-Script -arguments $migrationsBuildOutputPath {
        param($outputPath)

        Copy-Item -Recurse $outputPath $config.migrationsdestination
    }
}

Set-AfterTask release releasemigrations

task runmigrations {
    If($config.rollback) {
        Write-Warning "Rollback is not supported by dbup"
        Write-Warning "Doing nothing..."
        return
    }

    Invoke-Script {
        # Assembly name defined in config? use it
        $migrationsAssembly = $config.dbup.assembly

        # Otherwise, we derive the name from the csproj file
        If(-not $migrationsAssembly) {
            $migrationsCsProj = Get-Item $config.dbup.msbuild
            $name = $migrationsCsProj | Select-Object -expand basename

            $csProjFolder = $(Split-path $config.dbup.msbuild)

            # derive assembly name from name of csproj and check whether it exists
            $assembly = "$csProjFolder\bin\$($config.buildConfiguration)\$name.exe" 

            If(Test-Path $assembly) {
                $migrationsAssembly = $assembly
            }
        }

        If(-not $migrationsAssembly) {
            throw "Migration error: unable to locate migration assembly"
        }

        $extraArgs = $config.dbup.args

        If(-not $extraArgs) {
            $extraArgs = ''
        }

        Exec {
            &$migrationsAssembly $extraArgs
        }
    }
}

# Only if explicitely disabled automigrate
# we don't hookup to the migrations task
If($config.automigrate -ne $false) {
    Set-BeforeTask setupiis runmigrations
}

