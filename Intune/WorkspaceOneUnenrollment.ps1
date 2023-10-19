#Requires -RunAsAdministrator

# Check session is admin, if not escalate to admin
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))  
{
    $arguments = "& '" +$myinvocation.mycommand.definition + "'"
    Start-Process powershell -Verb runAs -ArgumentList $arguments
    Break
}

####### Set up logging
if(Get-Item -Path C:\StackOverflow-IT\ -ErrorAction Ignore) {} else {
    New-Item C:\StackOverflow-IT\ -ItemType Directory | out-null }
if(Get-Item -Path C:\StackOverflow-IT\Logs\ -ErrorAction Ignore) {} else {
    New-Item C:\StackOverflow-IT\Logs\ -ItemType Directory | out-null }

$Logfile = "C:\StackOverflow-IT\Logs\intune-migration.txt"

# Only let the user run once based on the existance of the log file.
#if(Get-Item -Path $Logfile -ErrorAction Ignore) {Write-Output "Breaking";break}

# Set up the logging function
Function LogWrite
{
    Param ([string]$logstring)

    $timeStamp = Get-Date
    $timeStamp = $timeStamp.ToString('u')
    Add-content $Logfile -value "$timeStamp $logstring"
}


LogWrite "==== RUN STARTED ===="

# Variables
$account = "Intune"
$checkForUser = (Get-LocalUser).Name -Contains $account

# If user does not exist, create it and add it to the Administrators group.
try {
    if(!$checkForUser) {
        LogWrite "$account account does not exist."
        $password = ConvertTo-SecureString "Stack123" -AsPlainText -Force
        New-LocalUser $account -Password $password -FullName $account -Description "Migration Account"
        Add-LocalGroupMember -Group "Administrators" -Member $account
        LogWrite "Created $account account successfully."
    } else {
        LogWrite "$account account already exists"
    }
} catch {
    LogWrite "Failed to create $account account."
    exit(0)
}

# Get the serial number of the device
try {
    $getserial = get-wmiobject win32_bios | select serialnumber | select $_.values
    $serial = new-object psobject -property @{serial_number = $getserial}
    $bodydata = @{ "serial_number" = $serial.serial_number.serialnumber}
    $body = convertto-json $bodydata

    $serialnum = $serial.serial_number.serialnumber
    LogWrite "Serial found: Serial is $serialnum"

    # The main event. Web request to workfountain to unenroll the device. It sends the serial number with an auth header.
    try {
        $LoginResponse = iwr -usebasicparsing https://workfountain.stackex.com/yacktools/kandjimigration `
            -Method 'POST' `
            -Headers @{'Content-Type' = 'application/json; charset=utf-8'; 'X-KANDJI-AUTH' = 'leesaidso'} `
            -Body $body
        $status = $LoginResponse.StatusCode
        $content = $LoginResponse.Content
        LogWrite "Web request Status: $status"
        LogWrite "Web request Content: $content"
    } catch {
        LogWrite "Error in web request:"
        LogWrite $_.Exception
    }
} catch { # This could fail because it is a custom desktop with no serial number.
    LogWrite "Could not verify serial number."
}
