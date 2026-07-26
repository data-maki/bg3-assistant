#Requires -RunAsAdministrator

param(
    [Parameter(Mandatory)]
    [ValidateSet('Install', 'Remove')]
    [string]$Action,

    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9A-Fa-f]{40}$')]
    [string]$Thumbprint,

    [string]$CertificatePath
)

$ErrorActionPreference = 'Stop'
$expectedSubject = 'CN=BG3HonorAssistant Development'
$normalizedThumbprint = $Thumbprint.ToUpperInvariant()

if ($Action -eq 'Install') {
    if ([string]::IsNullOrWhiteSpace($CertificatePath)) {
        throw 'CertificatePath is required for Install.'
    }

    $resolvedCertificate = (Resolve-Path -LiteralPath $CertificatePath).Path
    # This helper runs in inbox Windows PowerShell 5.1 after UAC. That runtime
    # predates X509CertificateLoader, so load this public-only CER with the
    # compatible constructor after resolving and validating the exact path.
    $certificate =
        [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
            $resolvedCertificate)
    if (
        $certificate.Subject -ne $expectedSubject -or
        $certificate.Thumbprint -ne $normalizedThumbprint -or
        $certificate.HasPrivateKey
    ) {
        throw 'The public development certificate did not match the reviewed subject and thumbprint.'
    }

    Import-Certificate `
        -FilePath $resolvedCertificate `
        -CertStoreLocation 'Cert:\LocalMachine\TrustedPeople' |
        Out-Null
}
else {
    $store = [System.Security.Cryptography.X509Certificates.X509Store]::new(
        [System.Security.Cryptography.X509Certificates.StoreName]::TrustedPeople,
        [System.Security.Cryptography.X509Certificates.StoreLocation]::LocalMachine)
    try {
        $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
        $matches = $store.Certificates.Find(
            [System.Security.Cryptography.X509Certificates.X509FindType]::FindByThumbprint,
            $normalizedThumbprint,
            $false)
        foreach ($certificate in $matches) {
            if ($certificate.Subject -ne $expectedSubject) {
                throw 'Refusing to remove a certificate whose subject does not match the development identity.'
            }

            $store.Remove($certificate)
        }
    }
    finally {
        $store.Close()
        $store.Dispose()
    }
}

$present = Test-Path -LiteralPath (
    "Cert:\LocalMachine\TrustedPeople\$normalizedThumbprint")
if (($Action -eq 'Install' -and -not $present) -or
    ($Action -eq 'Remove' -and $present)) {
    throw "Development certificate $Action did not reach the expected final state."
}

Write-Output "$Action completed for $normalizedThumbprint; present=$present."
