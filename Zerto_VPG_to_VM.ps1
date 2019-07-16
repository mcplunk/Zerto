################################################ 
# Configure the variables below 
################################################ 
$ExportDataDir = "C:\Scripts\Zerto\" 
$ZertoServer = "10.16.33.9" 
$ZertoPort = "9669" 
$ZertoSite = "zrfipr10.fpicore.fpir.pvt"
$ZertoUser = "fpi\zchartim" 
$Encrypted = Get-Content C:\Scripts\encrypted_password.txt | ConvertTo-SecureString
$BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Encrypted)
$ZertoPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
################################################ 
# Nothing to configure below here 
################################################ 
################################################ 
# Setting Cert Policy - required for successful auth with the Zerto API without connecting to vsphere using PowerCLI 
################################################ 
add-type @" 
    using System.Net; 
    using System.Security.Cryptography.X509Certificates; 
    public class TrustAllCertsPolicy : ICertificatePolicy { 
        public bool CheckValidationResult( 
            ServicePoint srvPoint, X509Certificate certificate, 
            WebRequest request, int certificateProblem) { 
            return true; 
        } 
    } 
"@ 
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy 
################################################ 
# Building Zerto API string and invoking API 
################################################ 
$BaseURL = "https://" + $ZertoServer + ":"+$ZertoPort+"/v1/" 
# Authenticating with Zerto APIs 
$xZertoSessionURL = $BaseURL + "session/add" 
$AuthInfo = ("{0}:{1}" -f $ZertoUser,$ZertoPassword) 
$AuthInfo = [System.Text.Encoding]::UTF8.GetBytes($AuthInfo) 
$AuthInfo = [System.Convert]::ToBase64String($AuthInfo) 
$Headers = @{Authorization=("Basic {0}" -f $AuthInfo)} 
$SessionBody = '{"AuthenticationMethod": "1"}' 
$TypeJSON = "application/JSON" 
$TypeXML = "application/XML" 
Try  
{ 
$xZertoSessionResponse = Invoke-WebRequest -Uri $xZertoSessionURL -Headers $Headers -Method POST -Body $SessionBody -ContentType $TypeJSON 
} 
Catch { 
Write-Host $_.Exception.ToString() 
$error[0] | Format-List -Force 
} 
#Extracting x-zerto-session from the response, and adding it to the actual API 
$xZertoSession = $xZertoSessionResponse.headers.get_item("x-zerto-session") 
$ZertoSessionHeader = @{"x-zerto-session"=$xZertoSession} 

# Build List of VPGs & VMs
$VMListApiUrl = $baseURL+"vms" 
$VMList = Invoke-RestMethod -Uri $VMListApiUrl -TimeoutSec 100 -Headers $ZertoSessionHeader -ContentType $TypeXML
$VPGList = Get-Content C:\scripts\Zerto\DR_TEST_2019\VPGList.txt
$DRtestVMs = @()
$DRtestVMs = $VMList | Select-Object vpgname,VmName,SourceSite, TargetSite

foreach ($_ in $DRtestVMs) 
{ 
    if($VPGList -contains $_.VPGName)
    {
        $CurrentOrganizationName = $_.OrganizationName 
        # Assigning a ZORG called "NoZORG" if one does not exist 
        if ($CurrentOrganizationName -eq "") 
        { 
        $CurrentOrganizationName = "NoZORG" 
        } 
        # Building log file name for the ZORG found 
        $CurrentCSVName = "C:\scripts\Zerto\DR_Test_2019\DRtest_ZertoAPIExport.CSV" 
        # Setting current values for insertion into the CSV file using an array  
        $CurrentVPGArray = @() 
        $CurrentVPGArrayLine = new-object PSObject 
        $CurrentVPGArrayLine | Add-Member -MemberType NoteProperty -Name "VPGName" -Value $_.vpgname 
        $CurrentVPGArrayLine | Add-Member -MemberType NoteProperty -Name "VmName" -Value $_.VmName
        $CurrentVPGArrayLine | Add-Member -MemberType NoteProperty -Name "SourceSite" -Value $_.SourceSite
        $CurrentVPGArrayLine | Add-Member -MemberType NoteProperty -Name "TargetSite" -Value $_.TargetSite
        $CurrentVPGArray += $CurrentVPGArrayLine 
        # Testing to see if CSV already exists 
        $CurrentCSVNameTestPath = test-path $CurrentCSVName 
        # If CSV exist test False creating the CSV with no append 
        if ($CurrentCSVNameTestPath -eq $False) 
        { 
        $CurrentVPGArray | export-csv -path $CurrentCSVName -NoTypeInformation 
        } 
        # If CSV exist test True appending to the existing CSV 
        if ($CurrentCSVNameTestPath -eq $True) 
        { 
        $CurrentVPGArray | export-csv -path $CurrentCSVName -NoTypeInformation -Append 
        }
    } # End if VPGList
} # End Foreach item in $DRtestVMs